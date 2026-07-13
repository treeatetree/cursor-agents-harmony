package com.brian.agents.shell

import android.annotation.SuppressLint
import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Parcel
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.webkit.BackForwardCacheSettings
import androidx.webkit.Profile
import androidx.webkit.ProfileStore
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature

/**
 * Process-retained WebView: detach/attach across Activity instances for near-instant warm starts.
 * Uses [MutableContextWrapper] so the WebView does not permanently leak an Activity.
 */
@OptIn(WebSettingsCompat.ExperimentalBackForwardCacheSettings::class, Profile.ExperimentalUrlPrefetch::class)
object WebViewHost {
    private const val TAG = "WebViewHost"
    private const val PREFS = "agents_shell"
    private const val KEY_STATE = "webview_state_v1"
    private const val BG = "#141414"

    private var appContext: Context? = null
    private var contextWrapper: MutableContextWrapper? = null
    private var webView: WebView? = null
    private var hasLoadedOnce = false

    fun init(context: Context) {
        if (appContext != null) return
        appContext = context.applicationContext
    }

    fun peek(): WebView? = webView

    fun hasContent(): Boolean = hasLoadedOnce && webView != null

    @SuppressLint("SetJavaScriptEnabled")
    fun obtain(activity: Context): WebView {
        init(activity)
        val existing = webView
        if (existing != null) {
            contextWrapper?.baseContext = activity
            (existing.parent as? ViewGroup)?.removeView(existing)
            return existing
        }

        val wrapper = MutableContextWrapper(activity)
        contextWrapper = wrapper
        val wv = TouchWebView(wrapper).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.parseColor(BG))
            overScrollMode = View.OVER_SCROLL_NEVER
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            setLayerType(View.LAYER_TYPE_HARDWARE, null)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // Smoother scroll while off-screen tiles rasterize.
                try {
                    // setOffscreenPreRaster is on View for WebView on API 23+
                    javaClass.getMethod("setOffscreenPreRaster", Boolean::class.javaPrimitiveType)
                        .invoke(this, true)
                } catch (_: Throwable) {
                }
            }

            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.loadsImagesAutomatically = true
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            settings.setSupportZoom(true)
            settings.builtInZoomControls = true
            settings.displayZoomControls = false
            settings.setSupportMultipleWindows(true)
            settings.javaScriptCanOpenWindowsAutomatically = true
            settings.allowFileAccess = false
            settings.allowContentAccess = true
            settings.textZoom = 100

            applyPerfSettings(settings)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_IMPORTANT, true)
                } catch (_: Throwable) {
                }
            }
        }
        webView = wv
        restoreStateIfAny(wv)
        return wv
    }

    fun applyPerfSettings(settings: WebSettings) {
        try {
            if (WebViewFeature.isFeatureSupported(WebViewFeature.REQUESTED_WITH_HEADER_ALLOW_LIST)) {
                WebSettingsCompat.setRequestedWithHeaderOriginAllowList(settings, emptySet())
            }
        } catch (_: Throwable) {
        }
        try {
            if (WebViewFeature.isFeatureSupported(WebViewFeature.BACK_FORWARD_CACHE)) {
                WebSettingsCompat.setBackForwardCacheEnabled(settings, true)
            }
        } catch (_: Throwable) {
        }
        try {
            if (WebViewFeature.isFeatureSupported(WebViewFeature.BACK_FORWARD_CACHE_SETTINGS_EXPERIMENTAL_V3)) {
                val bf: BackForwardCacheSettings =
                    WebSettingsCompat.getBackForwardCacheSettings(settings)
                bf.setTimeoutSeconds(1_800)
                bf.setMaxPagesInCache(24)
            }
        } catch (t: Throwable) {
            Log.d(TAG, "BFCache settings skipped: ${t.message}")
        }
        try {
            if (WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE) &&
                WebViewFeature.isFeatureSupported(WebViewFeature.PREFETCH_CACHE_V1)
            ) {
                val profile = ProfileStore.getInstance().getProfile(Profile.DEFAULT_PROFILE_NAME)
                profile?.getPrefetchCache()?.apply {
                    setMaxPrefetches(16)
                    setPrefetchTtlSeconds(1_200)
                }
            }
        } catch (t: Throwable) {
            Log.d(TAG, "PrefetchCache skipped: ${t.message}")
        }
    }

    fun markLoaded() {
        hasLoadedOnce = true
    }

    fun detach() {
        val wv = webView ?: return
        persistState(wv)
        (wv.parent as? ViewGroup)?.removeView(wv)
        contextWrapper?.baseContext = appContext ?: return
        try {
            wv.onPause()
        } catch (_: Throwable) {
        }
    }

    fun destroy() {
        val wv = webView ?: return
        persistState(wv)
        try {
            (wv.parent as? ViewGroup)?.removeView(wv)
            wv.stopLoading()
            wv.destroy()
        } catch (_: Throwable) {
        }
        webView = null
        contextWrapper = null
        hasLoadedOnce = false
    }

    fun persistState(wv: WebView? = webView) {
        val target = wv ?: return
        try {
            val bundle = Bundle()
            target.saveState(bundle)
            val parcel = Parcel.obtain()
            try {
                parcel.writeBundle(bundle)
                val bytes = parcel.marshall()
                val encoded = Base64.encodeToString(bytes, Base64.NO_WRAP)
                appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    ?.edit()
                    ?.putString(KEY_STATE, encoded)
                    ?.apply()
            } finally {
                parcel.recycle()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "persistState failed", t)
        }
    }

    private fun restoreStateIfAny(wv: WebView) {
        try {
            val encoded = appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                ?.getString(KEY_STATE, null) ?: return
            val bytes = Base64.decode(encoded, Base64.NO_WRAP)
            val parcel = Parcel.obtain()
            try {
                parcel.unmarshall(bytes, 0, bytes.size)
                parcel.setDataPosition(0)
                val bundle = parcel.readBundle(WebViewHost::class.java.classLoader) ?: return
                wv.restoreState(bundle)
                hasLoadedOnce = true
            } finally {
                parcel.recycle()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "restoreState failed", t)
        }
    }
}
