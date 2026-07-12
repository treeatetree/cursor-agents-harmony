@file:OptIn(
    WebViewCompat.ExperimentalAsyncStartUp::class,
    Profile.ExperimentalUrlPrefetch::class,
    Profile.ExperimentalWarmUpRendererProcess::class
)

package com.brian.agents.shell

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.webkit.PrefetchException
import androidx.webkit.Profile
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import androidx.webkit.WebViewOutcomeReceiver
import androidx.webkit.WebViewStartUpConfig
import java.net.InetAddress
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Async WebView engine warmup, DNS pre-resolve, and optional URL prefetch.
 * All feature APIs are guarded — older system WebView degrades silently.
 */
object WebViewWarmup {
    private const val TAG = "WebViewWarmup"
    private val ready = AtomicBoolean(false)
    private val starting = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bgExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "agents-webview-warmup").apply { isDaemon = true }
    }
    private val waiters = CopyOnWriteArrayList<() -> Unit>()

    val isReady: Boolean get() = ready.get()

    fun start(appContext: Context) {
        if (ready.get() || !starting.compareAndSet(false, true)) {
            if (ready.get()) notifyWaiters()
            return
        }
        val context = appContext.applicationContext
        bgExecutor.execute {
            preResolveDns()
        }
        try {
            val config = WebViewStartUpConfig.Builder(bgExecutor).build()
            WebViewCompat.startUpWebView(
                context,
                config,
                object : WebViewOutcomeReceiver<androidx.webkit.WebViewStartUpResult, androidx.webkit.WebViewStartupException> {
                    override fun onResult(result: androidx.webkit.WebViewStartUpResult) {
                        ready.set(true)
                        prefetchAgentsUrl(context)
                        notifyWaiters()
                    }

                    override fun onError(error: androidx.webkit.WebViewStartupException) {
                        Log.w(TAG, "startUpWebView error: ${error.message}")
                        ready.set(true)
                        notifyWaiters()
                    }
                }
            )
        } catch (t: Throwable) {
            Log.w(TAG, "startUpWebView failed; continuing without async startup", t)
            ready.set(true)
            notifyWaiters()
        }
    }

    /**
     * Runs [block] on the main thread once warmup is ready, or after [timeoutMs].
     */
    fun whenReadyOrTimeout(timeoutMs: Long, block: () -> Unit) {
        if (ready.get()) {
            mainHandler.post(block)
            return
        }
        var ran = false
        val runOnce = {
            if (!ran) {
                ran = true
                block()
            }
        }
        waiters.add(runOnce)
        mainHandler.postDelayed({
            waiters.remove(runOnce)
            runOnce()
        }, timeoutMs)
        if (ready.get()) {
            waiters.remove(runOnce)
            mainHandler.post(runOnce)
        }
    }

    private fun notifyWaiters() {
        mainHandler.post {
            val copy = waiters.toList()
            waiters.clear()
            copy.forEach { it.invoke() }
        }
    }

    private fun preResolveDns() {
        val hosts = listOf(
            "cursor.com",
            "www.cursor.com",
            "challenges.cloudflare.com"
        )
        for (host in hosts) {
            try {
                InetAddress.getAllByName(host)
            } catch (_: Throwable) {
            }
        }
    }

    /** Re-warm Agents list (Profile prefetch + disk HTML cache). */
    fun rewarmAgents(context: Context) {
        StaticAssetCache.prefetchAgentsHtml(MainActivity.TARGET_URL)
        prefetchAgentsUrl(context.applicationContext)
    }

    private fun prefetchAgentsUrl(context: Context) {
        try {
            if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) return
            if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROFILE_URL_PREFETCH)) return
            val profile = ProfileStore.getInstance().getProfile(Profile.DEFAULT_PROFILE_NAME)
                ?: return
            val url = PersistScheduler.lastAgentsUrl(context)
            profile.prefetchUrlAsync(
                url,
                null,
                bgExecutor,
                object : WebViewOutcomeReceiver<Void?, PrefetchException> {
                    override fun onResult(result: Void?) {
                        Log.d(TAG, "prefetch ok: $url")
                    }

                    override fun onError(error: PrefetchException) {
                        Log.d(TAG, "prefetch error: ${error.message}")
                    }
                }
            )
            // Also warm default agents entry if different from last URL.
            if (url != MainActivity.TARGET_URL) {
                try {
                    profile.prefetchUrlAsync(
                        MainActivity.TARGET_URL,
                        null,
                        bgExecutor,
                        object : WebViewOutcomeReceiver<Void?, PrefetchException> {
                            override fun onResult(result: Void?) {}
                            override fun onError(error: PrefetchException) {}
                        }
                    )
                } catch (_: Throwable) {
                }
            }
            try {
                if (WebViewFeature.isFeatureSupported(WebViewFeature.WARM_UP_RENDERER_PROCESS)) {
                    profile.warmUpRendererProcess()
                }
            } catch (_: Throwable) {
            }
        } catch (t: Throwable) {
            Log.w(TAG, "prefetch skipped", t)
        }
    }
}
