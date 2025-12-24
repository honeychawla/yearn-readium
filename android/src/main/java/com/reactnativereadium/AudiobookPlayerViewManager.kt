package com.reactnativereadium

import com.facebook.react.bridge.ReadableMap
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp

class AudiobookPlayerViewManager : SimpleViewManager<AudiobookPlayerView>() {

    override fun getName() = "AudiobookPlayerView"

    override fun createViewInstance(reactContext: ThemedReactContext): AudiobookPlayerView {
        return AudiobookPlayerView(reactContext)
    }

    @ReactProp(name = "file")
    fun setFile(view: AudiobookPlayerView, file: ReadableMap) {
        view.setFile(file)
    }
}
