package com.brian.agents.shell

import android.app.Application
import android.os.Build
import android.webkit.CookieManager
import android.webkit.WebView

/**
 * Kick off async WebView startup + DNS/prefetch as early as possible.
 */
class AgentsApp : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            CookieManager.getInstance().setAcceptCookie(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val process = Application.getProcessName()
                if (process != packageName) {
                    WebView.setDataDirectorySuffix(process)
                }
            }
        } catch (_: Throwable) {
        }
        WebViewHost.init(this)
        StaticAssetCache.init(this)
        WebViewWarmup.start(this)
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= TRIM_MEMORY_BACKGROUND) {
            WebViewHost.persistState()
        }
    }
}
