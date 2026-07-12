package com.brian.agents.shell

import android.content.Context
import android.webkit.WebView

/**
 * Plain WebView subclass kept for a stable type name / future touch tweaks.
 * Custom tap-clamping was removed — it fought dropdown / scroll gestures.
 */
class TouchWebView(context: Context) : WebView(context)
