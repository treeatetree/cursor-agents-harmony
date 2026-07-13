package com.brian.agents.shell

import android.content.Context
import android.util.LruCache
import android.util.Log
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Aggressive disk + memory cache for Cursor first-party static assets + Agents HTML.
 * Skips Cloudflare, auth providers, APIs, and login/HTML challenge pages.
 *
 * Strategy: cache-hit / stale-while-revalidate first; only block on network when cold.
 */
object StaticAssetCache {
    private const val TAG = "StaticAssetCache"
    private const val MAX_BYTES = 512L * 1024L * 1024L // 512MB disk
    private const val MAX_ENTRY = 16L * 1024L * 1024L
    private const val DEFAULT_TTL_MS = 45L * 24 * 60 * 60 * 1000 // 45d
    private const val IMMUTABLE_TTL_MS = 180L * 24 * 60 * 60 * 1000 // 180d
    private const val HTML_TTL_MS = 24L * 60 * 60 * 1000 // 24h fresh
    private const val HTML_STALE_MS = 14L * 24 * 60 * 60 * 1000 // 14d stale
    private const val STATIC_STALE_MS = 120L * 24 * 60 * 60 * 1000 // 120d stale
    private const val MEM_MAX_ENTRY = 1024 * 1024

    private val io = Executors.newFixedThreadPool(4) { r ->
        Thread(r, "static-asset-cache").apply { isDaemon = true }
    }
    private val cachedBytes = AtomicLong(0)
    @Volatile private var dir: File? = null

    /** Hot small assets for same-session navigations. */
    private val memCache = object : LruCache<String, MemEntry>(96 * 1024 * 1024) {
        override fun sizeOf(key: String, value: MemEntry): Int = value.bytes.size
    }

    private data class MemEntry(
        val bytes: ByteArray,
        val mime: String,
        val encoding: String?,
        val expiry: Long
    )

    private val STATIC_EXT = setOf(
        ".js", ".css", ".mjs", ".cjs", ".map",
        ".woff", ".woff2", ".ttf", ".otf", ".eot",
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico", ".avif",
        ".wasm", ".json", ".txt"
    )

    fun init(context: Context) {
        if (dir != null) return
        val d = File(context.cacheDir, "static_assets_v3")
        if (!d.exists()) d.mkdirs()
        dir = d
        io.execute { recount(d) }
        // Opportunistic warm of the Agents shell HTML.
        prefetchAgentsHtml("https://cursor.com/agents?source=harmony-android")
    }

    fun intercept(request: WebResourceRequest): WebResourceResponse? {
        val kind = classify(request) ?: return null
        val url = request.url?.toString() ?: return null
        val d = dir ?: return null
        val keys = cacheKeysFor(url)

        // 1) Memory hot path (try normalized keys)
        for (key in keys) {
            memCache.get(key)?.let { mem ->
                val now = System.currentTimeMillis()
                if (now <= mem.expiry) {
                    return responseFromBytes(mem.bytes, mem.mime, mem.encoding)
                }
                if (now <= mem.expiry + staleWindow(kind)) {
                    refreshAsync(d, url, request.requestHeaders, kind)
                    return responseFromBytes(mem.bytes, mem.mime, mem.encoding)
                }
                memCache.remove(key)
            }
        }

        // 2) Disk: fresh or stale-while-revalidate
        val disk = keys.firstNotNullOfOrNull { readDisk(d, it) }
        if (disk == null) {
            // Cold STATIC miss: don't block Chromium — fill cache in background.
            if (kind == Kind.STATIC) {
                refreshAsync(d, url, request.requestHeaders, kind)
                return null
            }
            return coldFetch(d, url, request.requestHeaders, kind)
        }
        val now = System.currentTimeMillis()
        if (now <= disk.expiry) {
            putMem(disk.url, disk)
            return responseFromFile(disk)
        }
        if (now <= disk.expiry + staleWindow(kind)) {
            refreshAsync(d, url, request.requestHeaders, kind)
            putMem(disk.url, disk.copy(expiry = now + softTtl(kind)))
            return responseFromFile(disk)
        }

        if (kind == Kind.STATIC) {
            refreshAsync(d, url, request.requestHeaders, kind)
            return responseFromFile(disk) // last resort stale forever for static
        }
        return coldFetch(d, url, request.requestHeaders, kind) ?: responseFromFile(disk)
    }

    /**
     * Background-warm the Agents list HTML into the disk cache (skips CF/login).
     */
    fun prefetchAgentsHtml(url: String = "https://cursor.com/agents") {
        val d = dir ?: return
        io.execute {
            try {
                val candidates = linkedSetOf(
                    url,
                    url.substringBefore('?').ifBlank { "https://cursor.com/agents" },
                    "https://cursor.com/agents",
                    "https://cursor.com/agents/"
                )
                for (target in candidates) {
                    val existing = readDisk(d, target)
                    val now = System.currentTimeMillis()
                    if (existing != null && now <= existing.expiry) continue
                    fetchAndCache(d, target, null, Kind.HTML)
                }
            } catch (t: Throwable) {
                Log.d(TAG, "prefetchAgentsHtml: ${t.message}")
            }
        }
    }

    private enum class Kind { STATIC, HTML }

    private fun staleWindow(kind: Kind): Long = when (kind) {
        Kind.HTML -> HTML_STALE_MS
        Kind.STATIC -> STATIC_STALE_MS
    }

    private fun softTtl(kind: Kind): Long = when (kind) {
        Kind.HTML -> HTML_TTL_MS / 4
        Kind.STATIC -> DEFAULT_TTL_MS / 10
    }

    private fun classify(request: WebResourceRequest): Kind? {
        if (!request.method.equals("GET", ignoreCase = true)) return null
        val uri = request.url ?: return null
        val host = uri.host?.lowercase() ?: return null

        if (host.contains("cloudflare") ||
            host.contains("challenges.") ||
            host.endsWith("google.com") ||
            host.endsWith("gstatic.com") ||
            host.endsWith("googleapis.com") ||
            host.contains("microsoftonline") ||
            host.contains("github.com") ||
            host.contains("authenticator.")
        ) {
            return null
        }

        val cursorHost = host == "cursor.com" || host.endsWith(".cursor.com") ||
            host == "cursor.sh" || host.endsWith(".cursor.sh")
        if (!cursorHost) return null

        val path = uri.path?.lowercase() ?: return null
        if (path.contains("/api/") ||
            path.contains("/graphql") ||
            path.contains("/auth") ||
            path.contains("/login") ||
            path.contains("/signin") ||
            path.contains("/sign-up") ||
            path.contains("/callback")
        ) {
            return null
        }

        if (request.isForMainFrame) {
            // Cache most Cursor HTML shells except auth/login (already filtered).
            return Kind.HTML
        }

        if (path.contains("/_next/static/")) return Kind.STATIC
        if (path.contains("/_next/data/")) {
            // Personalized page props — do not cache.
            return null
        }

        if (path.startsWith("/assets/") || path.startsWith("/static/") ||
            path.startsWith("/fonts/") || path.startsWith("/_next/image")
        ) {
            return Kind.STATIC
        }

        val lastDot = path.lastIndexOf('.')
        if (lastDot < 0) return null
        val ext = path.substring(lastDot)
        if (ext == ".json" && path.contains("/_next/")) return Kind.STATIC
        if (ext == ".json") return null
        return if (ext in STATIC_EXT) Kind.STATIC else null
    }

    private data class DiskEntry(
        val bin: File,
        val mime: String,
        val encoding: String?,
        val expiry: Long,
        val url: String
    )

    private fun keyFor(url: String): String {
        val md = MessageDigest.getInstance("SHA-256")
        val dig = md.digest(url.toByteArray(Charsets.UTF_8))
        return dig.joinToString("") { "%02x".format(it) }
    }

    /** Prefer stable keys so ?source= / tracking query still hit the same entry. */
    private fun cacheKeysFor(url: String): List<String> {
        val raw = url
        val noHash = url.substringBefore('#')
        val noQuery = noHash.substringBefore('?')
        return linkedSetOf(raw, noHash, noQuery).toList()
    }

    private fun filesFor(dir: File, url: String): Pair<File, File> {
        val key = keyFor(url)
        return File(dir, "$key.bin") to File(dir, "$key.meta")
    }

    private fun readDisk(dir: File, url: String): DiskEntry? {
        val (bin, meta) = filesFor(dir, url)
        if (!bin.exists() || !meta.exists()) return null
        return try {
            val lines = meta.readLines()
            val mime = lines.getOrNull(0) ?: return null
            val encoding = lines.getOrNull(1)?.takeIf { it.isNotBlank() && it != "null" }
            val expiry = lines.getOrNull(2)?.toLongOrNull() ?: 0L
            DiskEntry(bin, mime, encoding, expiry, url)
        } catch (_: Throwable) {
            null
        }
    }

    private fun responseFromFile(entry: DiskEntry): WebResourceResponse? {
        return try {
            val stream = BufferedInputStream(FileInputStream(entry.bin), 64 * 1024)
            WebResourceResponse(entry.mime, entry.encoding, stream)
        } catch (_: Throwable) {
            null
        }
    }

    private fun responseFromBytes(
        bytes: ByteArray,
        mime: String,
        encoding: String?
    ): WebResourceResponse =
        WebResourceResponse(mime, encoding, ByteArrayInputStream(bytes))

    private fun putMem(url: String, entry: DiskEntry) {
        try {
            if (entry.bin.length() > MEM_MAX_ENTRY) return
            val bytes = entry.bin.readBytes()
            memCache.put(url, MemEntry(bytes, entry.mime, entry.encoding, entry.expiry))
        } catch (_: Throwable) {
        }
    }

    private fun putMem(
        url: String,
        bytes: ByteArray,
        mime: String,
        encoding: String?,
        expiry: Long
    ) {
        if (bytes.size > MEM_MAX_ENTRY) return
        memCache.put(url, MemEntry(bytes, mime, encoding, expiry))
    }

    private fun refreshAsync(
        dir: File,
        url: String,
        reqHeaders: Map<String, String>?,
        kind: Kind
    ) {
        io.execute {
            try {
                fetchAndCache(dir, url, reqHeaders, kind)
            } catch (t: Throwable) {
                Log.d(TAG, "refreshAsync: ${t.message}")
            }
        }
    }

    private fun coldFetch(
        dir: File,
        url: String,
        reqHeaders: Map<String, String>?,
        kind: Kind
    ): WebResourceResponse? {
        return try {
            fetchAndCache(dir, url, reqHeaders, kind)
        } catch (t: Throwable) {
            Log.d(TAG, "coldFetch miss for $url: ${t.message}")
            null
        }
    }

    private fun fetchAndCache(
        dir: File,
        url: String,
        reqHeaders: Map<String, String>?,
        kind: Kind
    ): WebResourceResponse? {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 8_000
            readTimeout = 16_000
            requestMethod = "GET"
            setRequestProperty(
                "Accept",
                if (kind == Kind.HTML) {
                    "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
                } else {
                    "*/*"
                }
            )
            val cookie = CookieManager.getInstance().getCookie(url)
            if (!cookie.isNullOrBlank()) {
                setRequestProperty("Cookie", cookie)
            }
            reqHeaders?.forEach { (k, v) ->
                val key = k.lowercase()
                if (key == "user-agent" || key == "accept-language" ||
                    key == "accept" || key == "sec-ch-ua" || key == "sec-ch-ua-mobile"
                ) {
                    setRequestProperty(k, v)
                }
            }
        }
        return try {
            val code = conn.responseCode
            if (code !in 200..299) return null
            val mime = (conn.contentType ?: guessMime(url, kind)).substringBefore(';').trim()
            if (kind == Kind.STATIC) {
                if (mime.contains("text/html", true)) return null
                if (mime.contains("json", true) && !url.contains("/_next/")) return null
            }
            if (kind == Kind.HTML && !mime.contains("text/html", true) &&
                !mime.contains("application/xhtml", true)
            ) {
                return null
            }
            val bytes = conn.inputStream.use { it.readBytes() }
            if (bytes.isEmpty() || bytes.size > MAX_ENTRY) return null
            if (kind == Kind.HTML) {
                val head = String(bytes, 0, minOf(bytes.size, 800), Charsets.UTF_8).lowercase()
                if ("just a moment" in head || "cf-browser-verification" in head ||
                    "challenges.cloudflare" in head
                ) {
                    return null
                }
            }

            val encoding = conn.contentEncoding
            val cacheControl = conn.getHeaderField("Cache-Control")?.lowercase().orEmpty()
            val hashedStatic = url.contains("/_next/static/")
            // Content-addressed Next assets: cache even if origin says no-store.
            if ("no-store" in cacheControl && kind == Kind.STATIC && !hashedStatic) {
                return responseFromBytes(bytes, mime, encoding)
            }
            val ttl = when (kind) {
                Kind.HTML -> HTML_TTL_MS
                Kind.STATIC -> when {
                    "immutable" in cacheControl || hashedStatic -> IMMUTABLE_TTL_MS
                    else -> DEFAULT_TTL_MS
                }
            }
            val expiry = System.currentTimeMillis() + ttl
            // Store under normalized key for HTML so query variants share one entry.
            val storeUrl = if (kind == Kind.HTML) url.substringBefore('#').substringBefore('?')
                .ifBlank { url } else url
            putMem(storeUrl, bytes, mime, encoding, expiry)
            putMem(url, bytes, mime, encoding, expiry)

            io.execute {
                try {
                    ensureSpace(dir, bytes.size.toLong())
                    val (bin, meta) = filesFor(dir, storeUrl)
                    val prev = if (bin.exists()) bin.length() else 0L
                    bin.writeBytes(bytes)
                    meta.writeText(
                        buildString {
                            append(mime).append('\n')
                            append(encoding ?: "null").append('\n')
                            append(expiry).append('\n')
                            append(storeUrl)
                        }
                    )
                    cachedBytes.addAndGet(bytes.size.toLong() - prev)
                    if (kind == Kind.HTML) {
                        warmLinkedAssets(String(bytes, Charsets.UTF_8), storeUrl)
                    }
                } catch (t: Throwable) {
                    Log.d(TAG, "write failed: ${t.message}")
                }
            }

            responseFromBytes(bytes, mime, encoding)
        } finally {
            conn.disconnect()
        }
    }

    private fun warmLinkedAssets(html: String, baseUrl: String) {
        val d = dir ?: return
        try {
            val base = URL(baseUrl)
            val re = Regex("""(?:src|href)\s*=\s*["']([^"']+\.(?:js|mjs|cjs|css|woff2?|ttf))["']""", RegexOption.IGNORE_CASE)
            var n = 0
            for (m in re.findAll(html)) {
                if (n >= 40) break
                val raw = m.groupValues[1]
                if (raw.startsWith("data:")) continue
                val abs = try {
                    URL(base, raw).toString()
                } catch (_: Throwable) {
                    continue
                }
                if (!abs.contains("cursor.com") && !abs.contains("cursor.sh")) continue
                if (readDisk(d, abs) != null) continue
                n++
                refreshAsync(d, abs, null, Kind.STATIC)
            }
        } catch (t: Throwable) {
            Log.d(TAG, "warmLinkedAssets: ${t.message}")
        }
    }

    private fun guessMime(url: String, kind: Kind): String {
        if (kind == Kind.HTML) return "text/html"
        val p = url.lowercase().substringBefore('?')
        return when {
            p.endsWith(".js") || p.endsWith(".mjs") -> "application/javascript"
            p.endsWith(".css") -> "text/css"
            p.endsWith(".woff2") -> "font/woff2"
            p.endsWith(".woff") -> "font/woff"
            p.endsWith(".ttf") -> "font/ttf"
            p.endsWith(".png") -> "image/png"
            p.endsWith(".jpg") || p.endsWith(".jpeg") -> "image/jpeg"
            p.endsWith(".webp") -> "image/webp"
            p.endsWith(".svg") -> "image/svg+xml"
            p.endsWith(".wasm") -> "application/wasm"
            p.endsWith(".map") -> "application/json"
            else -> "application/octet-stream"
        }
    }

    private fun recount(dir: File) {
        var sum = 0L
        dir.listFiles()?.forEach { f ->
            if (f.name.endsWith(".bin")) sum += f.length()
        }
        cachedBytes.set(sum)
    }

    private fun ensureSpace(dir: File, incoming: Long) {
        if (cachedBytes.get() + incoming <= MAX_BYTES) return
        val bins = dir.listFiles { f -> f.name.endsWith(".bin") }
            ?.sortedBy { it.lastModified() }
            ?: return
        for (bin in bins) {
            if (cachedBytes.get() + incoming <= MAX_BYTES) break
            val meta = File(dir, bin.nameWithoutExtension + ".meta")
            val len = bin.length()
            bin.delete()
            meta.delete()
            cachedBytes.addAndGet(-len)
        }
    }
}
