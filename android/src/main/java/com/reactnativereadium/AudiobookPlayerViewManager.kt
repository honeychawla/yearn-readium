package com.reactnativereadium

import android.util.Log
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp

class AudiobookPlayerViewManager : SimpleViewManager<AudiobookPlayerView>() {

    init {
        Log.d(TAG, "✅ AudiobookPlayerViewManager initialized")
    }

    override fun getName(): String {
        Log.d(TAG, "getName() called, returning: AudiobookPlayerView")
        return "AudiobookPlayerView"
    }

    override fun createViewInstance(reactContext: ThemedReactContext): AudiobookPlayerView {
        Log.d(TAG, "✅ createViewInstance called")
        return AudiobookPlayerView(reactContext)
    }

    @ReactProp(name = "file")
    fun setFile(view: AudiobookPlayerView, file: ReadableMap?) {
        Log.d(TAG, "📥 setFile called")
        file?.let { view.setFile(it) }
    }

    override fun getExportedCustomDirectEventTypeConstants(): MutableMap<String, Any> {
        return MapBuilder.of(
            "onLocationChange", MapBuilder.of("registrationName", "onLocationChange"),
            "onPlaybackStateChange", MapBuilder.of("registrationName", "onPlaybackStateChange")
        )
    }

    companion object {
        private const val TAG = "AudiobookPlayerViewMgr"
    }
}
