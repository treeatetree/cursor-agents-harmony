package com.brian.agents.shell

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import android.webkit.WebView

/**
 * Coalesce expensive main-thread persistence work.
 */
object PersistScheduler {
    private const val TAG = "PersistScheduler"
    private val main = Handler(Looper.getMainLooper())
    private var pendingPersist = false
    private var pendingFlush = false

    private val persistRunnable = Runnable {
        pendingPersist = false
        try {
            WebViewHost.persistState()
        } catch (t: Throwable) {
            Log.w(TAG, "persist failed", t)
        }
    }

    private val flushRunnable = Runnable {
        pendingFlush = false
        try {
            CookieManager.getInstance().flush()
        } catch (t: Throwable) {
            Log.w(TAG, "flush failed", t)
        }
    }

    fun schedulePersist(delayMs: Long = 800L) {
        if (pendingPersist) {
            main.removeCallbacks(persistRunnable)
        }
        pendingPersist = true
        main.postDelayed(persistRunnable, delayMs)
    }

    fun scheduleFlush(delayMs: Long = 1200L) {
        if (pendingFlush) {
            main.removeCallbacks(flushRunnable)
        }
        pendingFlush = true
        main.postDelayed(flushRunnable, delayMs)
    }

    fun flushNow() {
        main.removeCallbacks(persistRunnable)
        main.removeCallbacks(flushRunnable)
        pendingPersist = false
        pendingFlush = false
        persistRunnable.run()
        flushRunnable.run()
    }

    fun lastAgentsUrl(context: Context): String {
        val prefs = context.getSharedPreferences("agents_shell", Context.MODE_PRIVATE)
        val last = prefs.getString("last_ok_url", null)
        return if (!last.isNullOrBlank() && last.startsWith("https://") &&
            (last.contains("cursor.com") || last.contains("cursor.sh"))
        ) {
            last
        } else {
            MainActivity.TARGET_URL
        }
    }
}
