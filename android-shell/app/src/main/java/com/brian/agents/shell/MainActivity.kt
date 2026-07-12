package com.brian.agents.shell

import android.Manifest
import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.PermissionRequest
import android.webkit.SslErrorHandler
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.browser.customtabs.CustomTabColorSchemeParams
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.WebViewFeature
import android.net.http.SslError
import android.view.KeyEvent

/**
 * Immersive fullscreen WebView shell with process-retained WebView and branded splash.
 * No pull-to-refresh (conflicts with scroll). OEM swipe-back is remapped to WebView history.
 */
class MainActivity : AppCompatActivity() {

    companion object {
        const val TARGET_URL = "https://cursor.com/agents?source=harmony-android"
        private const val BG = "#141414"
        private const val PREFS = "agents_shell"
        private const val KEY_LAST_URL = "last_ok_url"
        private const val KEY_CONTENT_ZOOM = "content_zoom"
        private const val DEFAULT_CONTENT_ZOOM = 1.15f
        private val ZOOM_STEPS = floatArrayOf(
            1.00f, 1.05f, 1.10f, 1.15f, 1.20f, 1.25f, 1.30f,
            1.35f, 1.40f, 1.45f, 1.50f, 1.60f, 1.70f, 1.80f, 1.90f, 2.00f
        )
    }

    private lateinit var root: FrameLayout
    private var webContainer: FrameLayout? = null
    private var webView: WebView? = null
    private var progressBar: ProgressBar? = null
    private var splash: View? = null
    private var errorPanel: View? = null
    private var navCover: ImageView? = null
    private var statusBarTapZone: View? = null
    private var zoomChrome: LinearLayout? = null
    private var zoomLabel: TextView? = null
    private var zoomMinus: TextView? = null
    private var zoomPlus: TextView? = null
    private var zoomExpanded = false
    private var contentZoom = DEFAULT_CONTENT_ZOOM
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var pendingPermissionRequest: PermissionRequest? = null
    private var firstPaintDone = false
    private var loginBounceCount = 0
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var wasOffline = false
    private var handlingBack = false
    private var coverShownAt = 0L
    private val hideCoverRunnable = Runnable { hideNavCover(force = true) }
    private val collapseZoomRunnable = Runnable { collapseZoomChrome() }
    private val fileChooserLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val callback = filePathCallback
            filePathCallback = null
            if (callback == null) return@registerForActivityResult
            val data = result.data
            val uris = when {
                result.resultCode != RESULT_OK -> null
                data?.clipData != null -> {
                    val clip = data.clipData!!
                    Array(clip.itemCount) { i -> clip.getItemAt(i).uri }
                }
                data?.data != null -> arrayOf(data.data!!)
                else -> null
            }
            callback.onReceiveValue(uris)
        }

    private val micPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val req = pendingPermissionRequest
            pendingPermissionRequest = null
            if (req == null) return@registerForActivityResult
            if (granted) {
                req.grant(req.resources)
            } else {
                req.deny()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.parseColor(BG)
        window.navigationBarColor = Color.parseColor(BG)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        val insetsController = WindowCompat.getInsetsController(window, window.decorView)
        insetsController.isAppearanceLightStatusBars = false
        insetsController.isAppearanceLightNavigationBars = false
        // Keep resize intent; actual lift is done via IME/systemBars padding below.
        window.setSoftInputMode(
            android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN
        )
        requestHighRefreshRate()
        contentZoom = loadContentZoom()

        root = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor(BG))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        setContentView(root)

        webContainer = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.parseColor(BG))
        }

        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progress = 8
            visibility = View.VISIBLE
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(3)
            ).apply { gravity = Gravity.TOP }
        }

        splash = buildSplash()
        errorPanel = buildErrorPanel().apply { visibility = View.GONE }
        navCover = ImageView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            scaleType = ImageView.ScaleType.FIT_XY
            setBackgroundColor(Color.parseColor(BG))
            visibility = View.GONE
            elevation = 6f
        }

        // iOS-like: tap status bar → scroll page to top.
        statusBarTapZone = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0
            ).apply { gravity = Gravity.TOP }
            isClickable = true
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            contentDescription = null
            elevation = 5f
            setOnClickListener { scrollWebToTop() }
        }

        root.addView(webContainer)
        root.addView(progressBar)
        root.addView(statusBarTapZone)
        root.addView(navCover)
        root.addView(buildZoomChrome())
        root.addView(splash)
        root.addView(errorPanel)

        val warmInstant = WebViewHost.hasContent()
        if (warmInstant) {
            attachWebView(loadIfNeeded = false)
            fadeSplashIfNeeded()
            progressBar?.visibility = View.GONE
        } else {
            WebViewWarmup.whenReadyOrTimeout(1_500L) {
                if (isFinishing || isDestroyed) return@whenReadyOrTimeout
                if (webView == null) {
                    attachWebView(loadIfNeeded = true)
                }
            }
        }

        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            applyShellInsets(insets)
            insets
        }
        // Keep WebView height in sync during keyboard animation (edge-to-edge).
        ViewCompat.setWindowInsetsAnimationCallback(
            root,
            object : androidx.core.view.WindowInsetsAnimationCompat.Callback(
                androidx.core.view.WindowInsetsAnimationCompat.Callback.DISPATCH_MODE_CONTINUE_ON_SUBTREE
            ) {
                override fun onProgress(
                    insets: WindowInsetsCompat,
                    runningAnimations: MutableList<androidx.core.view.WindowInsetsAnimationCompat>
                ): WindowInsetsCompat {
                    applyShellInsets(insets)
                    return insets
                }
            }
        )

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                navigateBackOrBackground()
            }
        })

        setTaskDescription(
            ActivityManager.TaskDescription("Agents", null, Color.parseColor(BG))
        )
        registerNetworkCallback()
    }

    /**
     * Edge-to-edge: pad WebView for status/nav bars and keyboard so Cursor chrome
     * and the composer are not covered (same class of issue as IME-only padding).
     */
    private fun applyShellInsets(insets: WindowInsetsCompat) {
        val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
        val cutout = insets.getInsets(WindowInsetsCompat.Type.displayCutout())
        val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
        val imeVisible = insets.isVisible(WindowInsetsCompat.Type.ime())
        val top = maxOf(bars.top, cutout.top)
        // Only lift for a real IME — avoids layout twitch when menus/dropdowns focus.
        val bottom = if (imeVisible && ime.bottom > bars.bottom) {
            ime.bottom
        } else {
            maxOf(bars.bottom, cutout.bottom)
        }
        webContainer?.setPadding(0, top, 0, bottom)
        progressBar?.setPadding(0, top, 0, 0)
        errorPanel?.setPadding(dp(24), top + dp(24), dp(24), bottom + dp(24))
        statusBarTapZone?.let { zone ->
            val lp = zone.layoutParams as FrameLayout.LayoutParams
            if (lp.height != top) {
                lp.height = top
                lp.gravity = Gravity.TOP
                zone.layoutParams = lp
            }
            zone.isClickable = top > 0
            zone.visibility = if (top > 0) View.VISIBLE else View.GONE
        }
        zoomChrome?.let { chrome ->
            val lp = chrome.layoutParams as FrameLayout.LayoutParams
            lp.gravity = Gravity.BOTTOM or Gravity.START
            lp.bottomMargin = bottom + dp(10)
            lp.marginStart = dp(10)
            lp.marginEnd = 0
            chrome.layoutParams = lp
        }
    }

    /** Status-bar tap → scroll WebView and nested page scrollers to top. */
    private fun scrollWebToTop() {
        val wv = webView ?: return
        try {
            wv.scrollTo(0, 0)
        } catch (_: Throwable) {
        }
        // Cursor Agents often scrolls an inner container, not the document.
        wv.evaluateJavascript(
            """
            (function(){
              try {
                var opt = {top:0, left:0, behavior:'smooth'};
                window.scrollTo(opt);
                var se = document.scrollingElement || document.documentElement;
                if (se && se.scrollTo) se.scrollTo(opt);
                if (document.body && document.body.scrollTo) document.body.scrollTo(opt);
                var nodes = document.querySelectorAll('div,main,section,article,ul,ol');
                for (var i = 0; i < nodes.length; i++) {
                  var el = nodes[i];
                  if (!el || !el.scrollTop) continue;
                  var st = window.getComputedStyle(el);
                  var oy = st.overflowY;
                  if ((oy === 'auto' || oy === 'scroll' || oy === 'overlay') && el.scrollTop > 0) {
                    if (el.scrollTo) el.scrollTo(opt); else el.scrollTop = 0;
                  }
                }
              } catch (e) {}
            })();
            """.trimIndent(),
            null
        )
    }

    /**
     * Huawei / 卓易通 edge-swipe often calls [finish] instead of OnBackPressed.
     * Prefer in-page history (BFCache-friendly) over destroying the Activity.
     */
    override fun finish() {
        if (handlingBack) {
            super.finish()
            return
        }
        if (navigateBackOrBackground()) {
            return
        }
        handlingBack = true
        try {
            moveTaskToBack(true)
        } finally {
            handlingBack = false
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && event?.repeatCount == 0) {
            navigateBackOrBackground()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    /**
     * @return true if the back action was consumed (history back or moved to background).
     */
    private fun navigateBackOrBackground(): Boolean {
        val wv = webView ?: WebViewHost.peek()
        if (wv != null && wv.canGoBack()) {
            showNavCoverFromWebView(wv)
            wv.goBack()
            return true
        }
        moveTaskToBack(true)
        return true
    }

    private fun showNavCoverFromWebView(wv: WebView) {
        try {
            val cover = navCover ?: return
            val bmp = captureWebView(wv)
            if (bmp != null) {
                cover.setImageBitmap(bmp)
            } else {
                // Solid fallback still beats flashing blank/black WebView.
                cover.setImageDrawable(null)
                cover.setBackgroundColor(Color.parseColor(BG))
            }
            cover.alpha = 1f
            cover.visibility = View.VISIBLE
            coverShownAt = System.currentTimeMillis()
            cover.removeCallbacks(hideCoverRunnable)
            // Safety: never leave cover forever.
            cover.postDelayed(hideCoverRunnable, 2_500L)
        } catch (_: Throwable) {
        }
    }

    private fun captureWebView(wv: WebView): Bitmap? {
        return try {
            if (wv.width <= 0 || wv.height <= 0) return null
            val bmp = Bitmap.createBitmap(wv.width, wv.height, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bmp)
            canvas.drawColor(Color.parseColor(BG))
            wv.draw(canvas)
            bmp
        } catch (_: Throwable) {
            null
        }
    }

    private fun hideNavCover(force: Boolean = false) {
        val cover = navCover ?: return
        if (cover.visibility != View.VISIBLE) return
        if (!force && System.currentTimeMillis() - coverShownAt < 90L) {
            // Avoid flicker on instant BFCache restores.
            cover.postDelayed({ hideNavCover(force = true) }, 90L)
            return
        }
        cover.removeCallbacks(hideCoverRunnable)
        cover.animate()
            .alpha(0f)
            .setDuration(120L)
            .withEndAction {
                cover.visibility = View.GONE
                cover.setImageDrawable(null)
                cover.alpha = 1f
            }
            .start()
    }

    private fun scheduleHideNavCover(delayMs: Long) {
        val cover = navCover ?: return
        if (cover.visibility != View.VISIBLE) return
        cover.removeCallbacks(hideCoverRunnable)
        cover.postDelayed(hideCoverRunnable, delayMs.coerceAtLeast(0L))
    }

    /** When landing back on Agents list, refresh disk/profile prefetch (not login/CF). */
    private fun maybeRewarmAgentsList(url: String?) {
        if (url.isNullOrBlank()) return
        val path = try {
            Uri.parse(url).path?.lowercase() ?: return
        } catch (_: Throwable) {
            return
        }
        if (path == "/agents" || path == "/agents/") {
            WebViewWarmup.rewarmAgents(applicationContext)
        }
    }

    /** Prefer history entry when reopening a URL still in the back-forward list. */
    private fun navigateSmart(wv: WebView, url: String) {
        try {
            val list = wv.copyBackForwardList()
            val target = canonicalizeUrl(url)
            for (i in 0 until list.size) {
                val item = list.getItemAtIndex(i) ?: continue
                if (canonicalizeUrl(item.url ?: continue) == target) {
                    val steps = i - list.currentIndex
                    if (steps != 0) {
                        showNavCoverFromWebView(wv)
                        wv.goBackOrForward(steps)
                        return
                    }
                }
            }
        } catch (_: Throwable) {
        }
        showNavCoverFromWebView(wv)
        wv.loadUrl(url)
    }

    private fun canonicalizeUrl(url: String): String {
        return try {
            val u = Uri.parse(url)
            buildString {
                append(u.scheme).append("://").append(u.host)
                append(u.path ?: "/")
            }.trimEnd('/').lowercase()
        } catch (_: Throwable) {
            url.substringBefore('?').trimEnd('/').lowercase()
        }
    }

    private fun buildSplash(): View {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor(BG))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            elevation = 4f
        }
        val icon = ImageView(this).apply {
            setImageResource(R.drawable.splash_logo)
            scaleType = ImageView.ScaleType.FIT_CENTER
            val size = dp(88)
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
            val plate = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#1F1F1F"))
            }
            background = plate
            setPadding(dp(10), dp(10), dp(10), dp(10))
        }
        val label = TextView(this).apply {
            text = "Agents"
            setTextColor(Color.parseColor("#CCCCCC"))
            textSize = 14f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dp(16)
            }
        }
        box.addView(icon)
        box.addView(label)
        return box
    }

    private fun requestHighRefreshRate() {
        try {
            val attrs = window.attributes
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val modes = display?.supportedModes ?: return
                val best = modes.maxByOrNull { it.refreshRate } ?: return
                attrs.preferredDisplayModeId = best.modeId
                window.attributes = attrs
            }
        } catch (_: Throwable) {
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun attachWebView(loadIfNeeded: Boolean) {
        CookieManager.getInstance().setAcceptCookie(true)
        val wv = WebViewHost.obtain(this)
        applyCacheMode(wv)
        wv.webViewClient = ShellWebViewClient()
        wv.webChromeClient = ShellWebChromeClient()
        wv.setDownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
            handleDownload(url, userAgent, contentDisposition, mimeType)
        }

        val container = webContainer ?: root
        (wv.parent as? ViewGroup)?.removeView(wv)
        container.addView(
            wv,
            0,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        webView = wv
        wv.onResume()

        if (!isOnline()) {
            wasOffline = true
            // Don't cover a retained page with the offline sheet.
            if (wv.url.isNullOrBlank() || wv.url == "about:blank") {
                showError(
                    getString(R.string.offline_title),
                    getString(R.string.offline_hint)
                )
            }
        }

        if (loadIfNeeded && !WebViewHost.hasContent()) {
            val startUrl = resolveStartUrl()
            maybePrerenderThenLoad(wv, startUrl)
        } else if (WebViewHost.hasContent()) {
            // Restored / retained document — reload only if blank.
            if (wv.url.isNullOrBlank() || wv.url == "about:blank") {
                maybePrerenderThenLoad(wv, resolveStartUrl())
            } else {
                fadeSplashIfNeeded()
                applyContentZoom(wv)
            }
        }
    }

    private fun applyCacheMode(wv: WebView) {
        wv.settings.cacheMode = if (isOnline()) {
            WebSettings.LOAD_DEFAULT
        } else {
            WebSettings.LOAD_CACHE_ELSE_NETWORK
        }
    }

    private fun resolveStartUrl(): String {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val last = prefs.getString(KEY_LAST_URL, null)
        return if (!last.isNullOrBlank() && last.startsWith("https://") &&
            (last.contains("cursor.com") || last.contains("cursor.sh"))
        ) {
            last
        } else {
            TARGET_URL
        }
    }

    private fun rememberUrl(url: String?) {
        if (url.isNullOrBlank()) return
        if (!(url.contains("cursor.com") || url.contains("cursor.sh"))) return
        if (url.contains("login") || url.contains("signin")) return
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(KEY_LAST_URL, url)
            .apply()
    }

    private fun maybePrerenderThenLoad(wv: WebView, url: String) {
        navigateSmart(wv, url)
    }

    private fun reloadCurrent() {
        val wv = webView ?: return
        applyCacheMode(wv)
        val url = wv.url?.takeIf { it.startsWith("http") } ?: resolveStartUrl()
        showNavCoverFromWebView(wv)
        wv.loadUrl(url)
    }

    private inner class ShellWebViewClient : WebViewClient() {
        override fun shouldInterceptRequest(
            view: WebView?,
            request: WebResourceRequest?
        ): WebResourceResponse? {
            if (request == null) return null
            return try {
                StaticAssetCache.intercept(request)
            } catch (_: Throwable) {
                null
            }
        }

        override fun shouldOverrideUrlLoading(
            view: WebView?,
            request: WebResourceRequest?
        ): Boolean {
            val uri = request?.url ?: return false
            val scheme = uri.scheme?.lowercase() ?: return true
            return when (scheme) {
                "http", "https", "about", "blob", "data" -> {
                    // Full navigations: freeze last frame to avoid black flash.
                    if (request.isForMainFrame && view != null) {
                        val next = uri.toString()
                        val cur = view.url
                        if (!cur.isNullOrBlank() && canonicalizeUrl(cur) != canonicalizeUrl(next)) {
                            showNavCoverFromWebView(view)
                        }
                    }
                    false
                }
                "mailto", "tel", "sms", "intent", "market" -> {
                    openExternal(uri)
                    true
                }
                else -> {
                    openExternal(uri)
                    true
                }
            }
        }

        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
            progressBar?.visibility = View.VISIBLE
            maybeHintSession(url)
            // If navigation started without a cover (e.g. SPA), keep dark bg only.
        }

        override fun onPageCommitVisible(view: WebView?, url: String?) {
            // First paint of new document — safer moment to drop the freeze frame.
            scheduleHideNavCover(60L)
            fadeSplashIfNeeded()
            maybeRewarmAgentsList(url)
        }

        override fun onPageFinished(view: WebView?, url: String?) {
            fadeSplashIfNeeded()
            progressBar?.visibility = View.GONE
            hideError()
            scheduleHideNavCover(80L)
            // textZoom is sticky on the WebView; only clear leftover CSS zoom once.
            clearLegacyCssZoom(view)
            rememberUrl(url)
            WebViewHost.markLoaded()
            PersistScheduler.scheduleFlush()
            PersistScheduler.schedulePersist()
            maybeRewarmAgentsList(url)
        }

        override fun onReceivedError(
            view: WebView?,
            request: WebResourceRequest?,
            error: WebResourceError?
        ) {
            if (request?.isForMainFrame != true) return
            if (!isOnline()) {
                wasOffline = true
                view?.settings?.cacheMode = WebSettings.LOAD_CACHE_ELSE_NETWORK
                // Keep showing the last painted page; only overlay if blank.
                if (view?.url.isNullOrBlank() || view?.url == "about:blank") {
                    showError(
                        getString(R.string.offline_title),
                        getString(R.string.offline_hint)
                    )
                }
            } else {
                showError(
                    getString(R.string.load_failed_title),
                    error?.description?.toString() ?: ""
                )
            }
            fadeSplashIfNeeded()
        }

        override fun onReceivedHttpError(
            view: WebView?,
            request: WebResourceRequest?,
            errorResponse: WebResourceResponse?
        ) {
        }

        override fun onReceivedSslError(
            view: WebView?,
            handler: SslErrorHandler?,
            error: SslError?
        ) {
            handler?.cancel()
            showError(getString(R.string.load_failed_title), "SSL error")
            fadeSplashIfNeeded()
        }
    }

    private inner class ShellWebChromeClient : WebChromeClient() {
        override fun onProgressChanged(view: WebView?, newProgress: Int) {
            progressBar?.progress = newProgress
            progressBar?.visibility = if (newProgress in 1..99) View.VISIBLE else View.GONE
            if (newProgress >= 90) {
                scheduleHideNavCover(50L)
            }
            if (newProgress >= 95) {
                fadeSplashIfNeeded()
            }
        }

        override fun onShowFileChooser(
            webView: WebView?,
            filePathCallback: ValueCallback<Array<Uri>>?,
            fileChooserParams: FileChooserParams?
        ): Boolean {
            this@MainActivity.filePathCallback?.onReceiveValue(null)
            this@MainActivity.filePathCallback = filePathCallback
            val intent = try {
                fileChooserParams?.createIntent() ?: Intent(Intent.ACTION_GET_CONTENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }
            } catch (_: Exception) {
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                }
            }
            return try {
                fileChooserLauncher.launch(intent)
                true
            } catch (_: ActivityNotFoundException) {
                this@MainActivity.filePathCallback = null
                filePathCallback?.onReceiveValue(null)
                false
            }
        }

        override fun onPermissionRequest(request: PermissionRequest?) {
            if (request == null) return
            val needsAudio = request.resources.any {
                it == PermissionRequest.RESOURCE_AUDIO_CAPTURE
            }
            if (needsAudio) {
                if (ContextCompat.checkSelfPermission(
                        this@MainActivity,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    request.grant(request.resources)
                } else {
                    pendingPermissionRequest = request
                    micPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                }
            } else {
                val safe = request.resources.filter {
                    it != PermissionRequest.RESOURCE_VIDEO_CAPTURE
                }.toTypedArray()
                if (safe.isNotEmpty()) request.grant(safe) else request.deny()
            }
        }

        override fun onCreateWindow(
            view: WebView?,
            isDialog: Boolean,
            isUserGesture: Boolean,
            resultMsg: android.os.Message?
        ): Boolean {
            val transport = resultMsg?.obj as? WebView.WebViewTransport ?: return false
            val temp = WebView(this@MainActivity).apply {
                settings.javaScriptEnabled = true
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        v: WebView?,
                        request: WebResourceRequest?
                    ): Boolean {
                        val url = request?.url?.toString() ?: return true
                        this@MainActivity.webView?.loadUrl(url)
                        // Tear down the transient popup WebView to avoid leaks.
                        v?.post {
                            try {
                                v.stopLoading()
                                v.destroy()
                            } catch (_: Throwable) {
                            }
                        }
                        return true
                    }
                }
            }
            transport.webView = temp
            resultMsg.sendToTarget()
            return true
        }
    }

    private fun handleDownload(
        url: String,
        userAgent: String,
        contentDisposition: String,
        mimeType: String
    ) {
        try {
            val request = DownloadManager.Request(Uri.parse(url)).apply {
                setMimeType(mimeType)
                addRequestHeader("User-Agent", userAgent)
                val cookies = CookieManager.getInstance().getCookie(url)
                if (!cookies.isNullOrEmpty()) {
                    addRequestHeader("Cookie", cookies)
                }
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                setDestinationInExternalPublicDir(
                    Environment.DIRECTORY_DOWNLOADS,
                    URLUtil.guessFileName(url, contentDisposition, mimeType)
                )
                setAllowedOverMetered(true)
                setAllowedOverRoaming(true)
            }
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            dm.enqueue(request)
            Toast.makeText(this, "Downloading…", Toast.LENGTH_SHORT).show()
        } catch (_: Exception) {
            openExternal(Uri.parse(url))
        }
    }

    private fun buildErrorPanel(): View {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor(BG))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            elevation = 8f
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }
        val title = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
        }
        val hint = TextView(this).apply {
            setTextColor(Color.parseColor("#AAAAAA"))
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, dp(24))
        }
        val retry = Button(this).apply {
            text = getString(R.string.retry)
            setOnClickListener {
                hideError()
                reloadCurrent()
            }
        }
        val browser = Button(this).apply {
            text = getString(R.string.open_in_browser)
            setOnClickListener { openEmergencyBrowser() }
        }
        box.addView(title)
        box.addView(hint)
        box.addView(retry)
        box.addView(browser)
        box.tag = mapOf("title" to title, "hint" to hint)
        return box
    }

    @Suppress("UNCHECKED_CAST")
    private fun showError(title: String, hint: String) {
        val panel = errorPanel ?: return
        val tags = panel.tag as? Map<String, TextView>
        tags?.get("title")?.text = title
        tags?.get("hint")?.text = hint
        panel.visibility = View.VISIBLE
    }

    private fun hideError() {
        errorPanel?.visibility = View.GONE
    }

    /**
     * Use WebSettings.textZoom so layout stays inside the viewport (CSS zoom was
     * pushing the composer off-screen and twitching dropdowns).
     */
    private fun applyContentZoom(wv: WebView?) {
        if (wv == null) return
        val target = (contentZoom * 100f).toInt().coerceIn(100, 200)
        try {
            if (wv.settings.textZoom != target) {
                wv.settings.textZoom = target
            }
        } catch (_: Throwable) {
        }
        clearLegacyCssZoom(wv)
    }

    /** Remove old documentElement.zoom from ≤1.6.8 which broke fixed bottom UI. */
    private fun clearLegacyCssZoom(wv: WebView?) {
        if (wv == null) return
        wv.evaluateJavascript(
            """
            (function(){
              try {
                var root = document.documentElement;
                if (!root || root.dataset.agentsCssZoomCleared === '1') return;
                root.style.zoom = '';
                if (document.body) document.body.style.zoom = '';
                delete root.dataset.agentsShellZoom;
                root.dataset.agentsCssZoomCleared = '1';
              } catch (e) {}
            })();
            """.trimIndent(),
            null
        )
    }

    private fun loadContentZoom(): Float {
        val raw = getSharedPreferences(PREFS, MODE_PRIVATE)
            .getFloat(KEY_CONTENT_ZOOM, DEFAULT_CONTENT_ZOOM)
        return nearestZoomStep(raw)
    }

    private fun saveContentZoom() {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putFloat(KEY_CONTENT_ZOOM, contentZoom)
            .apply()
    }

    private fun nearestZoomStep(value: Float): Float {
        var best = ZOOM_STEPS[0]
        var bestDist = kotlin.math.abs(value - best)
        for (step in ZOOM_STEPS) {
            val d = kotlin.math.abs(value - step)
            if (d < bestDist) {
                best = step
                bestDist = d
            }
        }
        return best
    }

    private fun zoomLabelText(): String = "${(contentZoom * 100f).toInt()}%"

    private fun buildZoomChrome(): View {
        val minus = TextView(this).apply {
            text = "−"
            setTextColor(Color.parseColor("#DDDDDD"))
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(6), dp(10), dp(6))
            visibility = View.GONE
            setOnClickListener {
                bumpZoom(-1)
                keepZoomExpanded()
            }
        }
        val label = TextView(this).apply {
            text = zoomLabelText()
            setTextColor(Color.parseColor("#CCCCCC"))
            textSize = 11f
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            setOnClickListener {
                if (zoomExpanded) {
                    collapseZoomChrome()
                } else {
                    expandZoomChrome()
                }
            }
        }
        val plus = TextView(this).apply {
            text = "+"
            setTextColor(Color.parseColor("#DDDDDD"))
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(6), dp(10), dp(6))
            visibility = View.GONE
            setOnClickListener {
                bumpZoom(+1)
                keepZoomExpanded()
            }
        }
        zoomMinus = minus
        zoomLabel = label
        zoomPlus = plus

        val plate = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(16).toFloat()
            setColor(Color.parseColor("#66141414"))
            setStroke(dp(1), Color.parseColor("#33FFFFFF"))
        }
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = plate
            alpha = 0.38f
            elevation = 4f
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.START
                bottomMargin = dp(10)
                marginStart = dp(10)
            }
            addView(minus)
            addView(label)
            addView(plus)
        }
        zoomChrome = row
        return row
    }

    private fun expandZoomChrome() {
        zoomExpanded = true
        zoomMinus?.visibility = View.VISIBLE
        zoomPlus?.visibility = View.VISIBLE
        zoomChrome?.animate()?.alpha(0.72f)?.setDuration(120)?.start()
        keepZoomExpanded()
    }

    private fun collapseZoomChrome() {
        zoomExpanded = false
        zoomMinus?.visibility = View.GONE
        zoomPlus?.visibility = View.GONE
        zoomLabel?.text = zoomLabelText()
        zoomChrome?.animate()?.alpha(0.38f)?.setDuration(160)?.start()
        zoomChrome?.removeCallbacks(collapseZoomRunnable)
    }

    private fun keepZoomExpanded() {
        zoomChrome?.removeCallbacks(collapseZoomRunnable)
        zoomChrome?.postDelayed(collapseZoomRunnable, 2_800L)
    }

    private fun bumpZoom(dir: Int) {
        val idx = ZOOM_STEPS.indexOfFirst { kotlin.math.abs(it - contentZoom) < 0.001f }
            .let { cur ->
                if (cur >= 0) cur
                else ZOOM_STEPS.indexOfFirst { kotlin.math.abs(it - DEFAULT_CONTENT_ZOOM) < 0.001f }
                    .coerceAtLeast(0)
            }
            .coerceIn(0, ZOOM_STEPS.lastIndex)
        val next = (idx + dir).coerceIn(0, ZOOM_STEPS.lastIndex)
        contentZoom = ZOOM_STEPS[next]
        zoomLabel?.text = zoomLabelText()
        saveContentZoom()
        applyContentZoom(webView)
    }

    private fun fadeSplashIfNeeded() {
        if (firstPaintDone) return
        firstPaintDone = true
        splash?.animate()
            ?.alpha(0f)
            ?.setDuration(180)
            ?.withEndAction {
                splash?.visibility = View.GONE
            }
            ?.start()
    }

    private fun maybeHintSession(url: String?) {
        if (url.isNullOrEmpty()) return
        val lower = url.lowercase()
        val looksLogin = lower.contains("login") || lower.contains("signin") ||
            (lower.contains("auth") && lower.contains("cursor"))
        if (looksLogin && !lower.contains("/agents")) {
            loginBounceCount++
            if (loginBounceCount == 3) {
                Toast.makeText(this, R.string.session_hint, Toast.LENGTH_SHORT).show()
            }
        } else if (lower.contains("/agents")) {
            loginBounceCount = 0
        }
    }

    private fun openEmergencyBrowser() {
        try {
            val dark = CustomTabColorSchemeParams.Builder()
                .setToolbarColor(Color.parseColor(BG))
                .setNavigationBarColor(Color.parseColor(BG))
                .build()
            CustomTabsIntent.Builder()
                .setDefaultColorSchemeParams(dark)
                .build()
                .launchUrl(this, Uri.parse(TARGET_URL))
        } catch (_: Exception) {
            openExternal(Uri.parse(TARGET_URL))
        }
    }

    private fun openExternal(uri: Uri) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
        } catch (_: ActivityNotFoundException) {
        }
    }

    private fun flushCookies() {
        PersistScheduler.scheduleFlush(0L)
    }

    private fun isOnline(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun registerNetworkCallback() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                runOnUiThread {
                    if (wasOffline) {
                        wasOffline = false
                        hideError()
                        webView?.let {
                            it.settings.cacheMode = WebSettings.LOAD_DEFAULT
                            if (it.url.isNullOrBlank() || it.url == "about:blank") {
                                reloadCurrent()
                            }
                        }
                    } else {
                        webView?.settings?.cacheMode = WebSettings.LOAD_DEFAULT
                    }
                }
            }

            override fun onLost(network: Network) {
                runOnUiThread {
                    // Only mark offline if no other network remains.
                    if (!isOnline()) {
                        wasOffline = true
                        webView?.settings?.cacheMode = WebSettings.LOAD_CACHE_ELSE_NETWORK
                    }
                }
            }
        }
        networkCallback = callback
        try {
            cm.registerNetworkCallback(
                NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build(),
                callback
            )
        } catch (_: Throwable) {
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onPause() {
        PersistScheduler.scheduleFlush(200L)
        PersistScheduler.schedulePersist(200L)
        webView?.onPause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        webView?.onResume()
    }

    override fun onStop() {
        PersistScheduler.flushNow()
        super.onStop()
    }

    override fun onDestroy() {
        networkCallback?.let {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.unregisterNetworkCallback(it)
            } catch (_: Throwable) {
            }
        }
        networkCallback = null
        PersistScheduler.flushNow()
        // Detach retained WebView — do NOT destroy (warm start).
        WebViewHost.detach()
        webView = null
        super.onDestroy()
    }
}
