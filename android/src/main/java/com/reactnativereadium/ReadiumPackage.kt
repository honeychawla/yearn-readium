package com.reactnativereadium

import android.util.Log
import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager


class ReadiumPackage : ReactPackage {

    init {
        Log.d(TAG, "✅ ReadiumPackage initialized")
    }

    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> {
        Log.d(TAG, "createNativeModules called")
        return emptyList()
    }

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> {
        Log.d(TAG, "createViewManagers called")
        val managers = listOf(
            ReadiumViewManager(reactContext),
            AudiobookPlayerViewManager()
        )
        Log.d(TAG, "Registered ${managers.size} view managers: ${managers.map { it.name }}")
        return managers
    }

    companion object {
        private const val TAG = "ReadiumPackage"
    }
}
