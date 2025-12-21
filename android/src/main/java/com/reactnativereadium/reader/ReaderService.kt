package com.reactnativereadium.reader

import android.annotation.SuppressLint
import android.util.Log
import androidx.lifecycle.ViewModelStore
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.util.RNLog
import com.reactnativereadium.lcp.LCPService
import com.reactnativereadium.utils.LinkOrLocator
import java.io.File
import java.io.IOException
import java.net.ServerSocket
import org.readium.r2.shared.extensions.mediaType
import org.readium.r2.shared.extensions.tryOrNull
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.asset.FileAsset
import org.readium.r2.shared.publication.Publication
import org.readium.r2.streamer.server.Server
import org.readium.r2.streamer.Streamer


class ReaderService(
  private val reactContext: ReactApplicationContext
) {
  private var streamer = Streamer(reactContext)
  private val lcpService = LCPService(reactContext)
  // see R2App.onCreate
  private var server: Server
  // val channel = EventChannel(Channel<Event>(Channel.BUFFERED), viewModelScope)
  private var store = ViewModelStore()

  private val TAG = "ReaderService"

  companion object {
    @SuppressLint("StaticFieldLeak")
    lateinit var server: Server
      private set

    lateinit var R2DIRECTORY: String
      private set

    var isServerStarted = false
      private set
  }

  init {
    val s = ServerSocket(0)
    s.close()
    server = Server(s.localPort, reactContext)
    this.startServer()
  }

  fun locatorFromLinkOrLocator(
    location: LinkOrLocator?,
    publication: Publication,
  ): Locator? {

    if (location == null) return null

    when (location) {
      is LinkOrLocator.Link -> {
        return publication.locatorFromLink(location.link)
      }
      is LinkOrLocator.Locator -> {
        return location.locator
      }
    }

    return null
  }

  suspend fun openPublication(
    fileName: String,
    initialLocation: LinkOrLocator?,
    lcpPassphrase: String? = null,
    callback: suspend (fragment: BaseReaderFragment) -> Unit
  ) {
    // Initialize Streamer with LCP if available
    if (lcpService.isAvailable()) {
      Log.d(TAG, "[LCP] LCP Service available, creating Streamer with content protection")
      val contentProtection = lcpService.getContentProtection(lcpPassphrase)
      Log.d(TAG, "[LCP] ContentProtection object: $contentProtection")
      if (contentProtection != null) {
        try {
          Log.d(TAG, "[LCP] About to create Streamer WITH contentProtections...")
          // Create Streamer WITH contentProtections parameter
          streamer = Streamer(reactContext, contentProtections = listOf(contentProtection))
          Log.d(TAG, "[LCP] ✅✅✅ Streamer created WITH LCP content protection")
        } catch (e: Exception) {
          Log.e(TAG, "[LCP] ❌❌❌ EXCEPTION creating Streamer with LCP: ${e.message}", e)
          e.printStackTrace()
        }
      } else {
        Log.e(TAG, "[LCP] ❌ ContentProtection is NULL!")
      }
    } else {
      Log.w(TAG, "[LCP] LCP Service not available")
    }

    val file = File(fileName)
    val asset = FileAsset(file, file.mediaType())

    Log.d(TAG, "[LCP] About to call streamer.open() on asset: ${file.path}")

    streamer.open(
      asset,
      allowUserInteraction = true,
      sender = reactContext
    )
      .onSuccess { publication ->
          Log.d(TAG, "[LCP] 🎉🎉🎉 streamer.open() SUCCESS!")

          // In Readium 2.4.x, if the publication opens successfully, LCP protection
          // has been properly handled. Protection errors would be caught during
          // the opening process via onFailure, not here.
          Log.d(TAG, "[LCP] ✅ Publication opened successfully!")

          val locator = locatorFromLinkOrLocator(initialLocation, publication)
          val readerFragment = EpubReaderFragment.newInstance()
          readerFragment.initFactory(publication, locator)
          callback.invoke(readerFragment)

      }
      .onFailure { error ->
        Log.e(TAG, "[LCP] ❌❌❌ streamer.open() FAILED: $error")
        tryOrNull { asset.file.delete() }
        RNLog.w(reactContext, "Error executing ReaderService.openPublication")
        // TODO: implement failure event
      }
  }

  private fun startServer() {
    if (!server.isAlive) {
      try {
        server.start()
      } catch (e: IOException) {
        RNLog.e(reactContext, "Unable to start the Readium server.")
      }
      if (server.isAlive) {
        // // Add your own resources here
        // server.loadCustomResource(assets.open("scripts/test.js"), "test.js")
        // server.loadCustomResource(assets.open("styles/test.css"), "test.css")
        // server.loadCustomFont(assets.open("fonts/test.otf"), applicationContext, "test.otf")

        isServerStarted = true
      }
    }
  }

  sealed class Event {

    class ImportPublicationFailed(val errorMessage: String?) : Event()

    object UnableToMovePublication : Event()

    object ImportPublicationSuccess : Event()

    object ImportDatabaseFailed : Event()

    class OpenBookError(val errorMessage: String?) : Event()
  }
}
