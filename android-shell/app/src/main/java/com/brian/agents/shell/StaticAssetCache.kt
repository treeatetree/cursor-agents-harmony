package com.brian.agents.shell

import android.content.Context
import android.util.Log
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Aggressive disk cache for Cursor first-party static assets + Agents HTML shells.
 * Skips Cloudflare, auth providers, APIs, and login/HTML challenge pages.
 */
object StaticAssetCache {
    private const val TAG = "StaticAssetCache"
    private const val MAX_BYTES = 160L * 1024L * 1024L // 160MB
    private const val MAX_ENTRY = 8L * 1024L * 1024L
    private const val DEFAULT_TTL_MS = 14L * 24 * 60 * 60 * 1000
    private const val IMMUTABLE_TTL_MS = 45L * 24 * 60 * 60 * 1000
    private const val HTML_TTL_MS = 45L * 60 * 1000 // 45 minutes for agents HTML

    private val io = Executors.newSingleThreadExecutor { r ->
        Thread(r, "static-asset-cache").apply { isDaemon = true }
    }
    private val cachedBytes = AtomicLong(0)
    @Volatile private var dir: File? = null

    private val STATIC_EXT = setOf(
        ".js", ".css", ".mjs", ".cjs",
        ".woff", ".woff2", ".ttf", ".otf", ".eot",
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico", ".avif",
        ".wasm", ".json" // next build manifests / i18n chunks (not API)
    )

    fun init(context: Context) {
        if (dir != null) return
        // bump dir name when format changes
        val d = File(context.cacheDir, "static_assets_v2")
        if (!d.exists()) d.mkdirs()
        dir = d
        io.execute { recount(d) }
    }

    fun intercept(request: WebResourceRequest): WebResourceResponse? {
        val kind = classify(request) ?: return null
        val url = request.url?.toString() ?: return null
        val d = dir ?: return null

        val hit = readHit(d, url)
        if (hit != null) return hit

        return try {
            fetchAndCache(d, url, request.requestHeaders, kind)
        } catch (t: Throwable) {
            Log.d(TAG, "fetch miss for $url: ${t.message}")
            null
        }
    }

    /**
     * Background-warm the Agents list HTML into the disk cache (skips CF/login).
     * Safe to call repeatedly; work runs on the cache IO thread.
     */
    fun prefetchAgentsHtml(url: String = "https://cursor.com/agents") {
        val d = dir ?: return
        io.execute {
            try {
                val candidates = linkedSetOf(
                    url,
                    url.substringBefore('?').ifBlank { "https://cursor.com/agents" },
                    "https://cursor.com/agents"
                )
                for (target in candidates) {
                    val hit = readHit(d, target)
                    if (hit != null) {
                        try {
                            hit.data?.close()
                        } catch (_: Throwable) {
                        }
                        continue
                    }
                    fetchAndCache(d, target, null, Kind.HTML)
                }
            } catch (t: Throwable) {
                Log.d(TAG, "prefetchAgentsHtml: ${t.message}")
            }
        }
    }

    private enum class Kind { STATIC, HTML }

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

        // Agents HTML shell (main frame OK) — aggressive but short TTL.
        if (request.isForMainFrame) {
            return if (path == "/agents" || path.startsWith("/agents/") ||
                path.startsWith("/dashboard") || path == "/"
            ) {
                Kind.HTML
            } else {
                null
            }
        }

        if (path.contains("/_next/static/") || path.contains("/_next/data/")) {
            // _next/data can be personalized — only allow if path looks like build-id static data
            // Safer: allow _next/static always; _next/data only without "user" segments
            if (path.contains("/_next/data/")) {
                // Next data routes often include page props; skip to avoid stale private data.
                return null
            }
            return Kind.STATIC
        }

        // Common CDN-ish paths on cursor
        if (path.startsWith("/assets/") || path.startsWith("/static/") || path.startsWith("/fonts/")) {
            return Kind.STATIC
        }

        val lastDot = path.lastIndexOf('.')
        if (lastDot < 0) return null
        val ext = path.substring(lastDot)
        // Don't treat .json under /api as static — already excluded.
        if (ext == ".json" && path.contains("/_next/")) return Kind.STATIC
        if (ext == ".json") return null
        return if (ext in STATIC_EXT) Kind.STATIC else null
    }

    private fun keyFor(url: String): String {
        val md = MessageDigest.getInstance("SHA-256")
        val dig = md.digest(url.toByteArray(Charsets.UTF_8))
        return dig.joinToString("") { "%02x".format(it) }
    }

    private fun filesFor(dir: File, url: String): Pair<File, File> {
        val key = keyFor(url)
        return File(dir, "$key.bin") to File(dir, "$key.meta")
    }

    private fun readHit(dir: File, url: String): WebResourceResponse? {
        val (bin, meta) = filesFor(dir, url)
        if (!bin.exists() || !meta.exists()) return null
        return try {
            val lines = meta.readLines()
            val mime = lines.getOrNull(0) ?: return null
            val encoding = lines.getOrNull(1)?.takeIf { it.isNotBlank() && it != "null" }
            val expiry = lines.getOrNull(2)?.toLongOrNull() ?: 0L
            if (System.currentTimeMillis() > expiry) {
                bin.delete()
                meta.delete()
                return null
            }
            val bytes = bin.readBytes()
            WebResourceResponse(mime, encoding, ByteArrayInputStream(bytes))
        } catch (_: Throwable) {
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
            connectTimeout = 12_000
            readTimeout = 20_000
            requestMethod = "GET"
            setRequestProperty("Accept", if (kind == Kind.HTML) {
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            } else {
                "*/*"
            })
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
            // Reject CF interstitial HTML even on agents URL.
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
            if ("no-store" in cacheControl && kind == Kind.STATIC) {
                // Still allow HTML short cache; for static respect no-store.
                return WebResourceResponse(mime, encoding, ByteArrayInputStream(bytes))
            }
            val ttl = when (kind) {
                Kind.HTML -> HTML_TTL_MS
                Kind.STATIC -> when {
                    "immutable" in cacheControl -> IMMUTABLE_TTL_MS
                    url.contains("/_next/static/") -> IMMUTABLE_TTL_MS
                    else -> DEFAULT_TTL_MS
                }
            }
            val expiry = System.currentTimeMillis() + ttl

            io.execute {
                try {
                    ensureSpace(dir, bytes.size.toLong())
                    val (bin, meta) = filesFor(dir, url)
                    bin.writeBytes(bytes)
                    meta.writeText(
                        buildString {
                            append(mime).append('\n')
                            append(encoding ?: "null").append('\n')
                            append(expiry).append('\n')
                            append(url)
                        }
                    )
                    cachedBytes.addAndGet(bytes.size.toLong())
                } catch (t: Throwable) {
                    Log.d(TAG, "write failed: ${t.message}")
                }
            }

            WebResourceResponse(mime, encoding, ByteArrayInputStream(bytes))
        } finally {
            conn.disconnect()
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
