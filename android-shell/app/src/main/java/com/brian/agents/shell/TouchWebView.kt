package com.brian.agents.shell

import android.content.Context
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.webkit.WebView
import kotlin.math.abs
import kotlin.math.hypot

/**
 * WebView with slightly more forgiving taps: micro-drags within an enlarged
 * touch slop are clamped so the page treats them as clicks rather than scrolls.
 */
class TouchWebView(context: Context) : WebView(context) {

    private val touchSlop: Float =
        ViewConfiguration.get(context).scaledTouchSlop * 1.75f

    private var downX = 0f
    private var downY = 0f
    private var withinTapSlop = false

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                withinTapSlop = true
                parent?.requestDisallowInterceptTouchEvent(true)
            }
            MotionEvent.ACTION_MOVE -> {
                if (withinTapSlop) {
                    val dx = abs(event.x - downX)
                    val dy = abs(event.y - downY)
                    if (hypot(dx.toDouble(), dy.toDouble()) <= touchSlop) {
                        // Clamp coordinates to the down point so Chromium keeps
                        // interpreting this as a tap, not a scroll.
                        event.setLocation(downX, downY)
                    } else {
                        withinTapSlop = false
                    }
                }
                parent?.requestDisallowInterceptTouchEvent(true)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (withinTapSlop && event.actionMasked == MotionEvent.ACTION_UP) {
                    event.setLocation(downX, downY)
                }
                withinTapSlop = false
                parent?.requestDisallowInterceptTouchEvent(false)
            }
        }
        return super.onTouchEvent(event)
    }
}
