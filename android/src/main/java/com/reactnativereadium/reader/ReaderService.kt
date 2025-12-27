package com.reactnativereadium.reader

import android.annotation.SuppressLint
import androidx.lifecycle.ViewModelStore
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.util.RNLog
import com.reactnativereadium.lcp.LCPPassphraseAuthentication
import com.reactnativereadium.utils.LinkOrLocator
import java.io.File
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.streamer.parser.DefaultPublicationParser
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.lcp.LcpService


class ReaderService(
  private val reactContext: ReactApplicationContext
) {
  private val httpClient = DefaultHttpClient()
  private val assetRetriever = AssetRetriever(reactContext.contentResolver, httpClient)
  private val publicationParser = DefaultPublicationParser(reactContext, httpClient, assetRetriever, null)

  // LCP service for content protection - initialize if needed
  private val lcpService: LcpService? = null // Will be initialized when LCP is needed

  // Content protections should be added when opening specific publications
  // For now, create opener without LCP (will be added per-publication as needed)
  private val publicationOpener = PublicationOpener(
    publicationParser = publicationParser,
    contentProtections = emptyList()
  )

  private var store = ViewModelStore()

  companion object {
    lateinit var R2DIRECTORY: String
      private set

    // Server is removed in Readium 3.x - publications are served directly by navigators
    @Deprecated("Server is no longer used in Readium 3.x")
    var isServerStarted = false
      private set
  }

  init {
    // Server initialization removed - no longer needed in Readium 3.x
    // Publications are now served directly by navigators without a central server
    isServerStarted = true // Set to true for backward compatibility
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
    callback: suspend (fragment: BaseReaderFragment) -> Unit
  ) {
    val file = File(fileName)

    // Retrieve asset using AssetRetriever (Readium 3.x)
    val assetResult = assetRetriever.retrieve(file)
    val asset = when {
      assetResult.isSuccess -> assetResult.getOrNull()
      else -> {
        RNLog.w(reactContext, "Error retrieving asset: ${assetResult.failureOrNull()}")
        try { file.delete() } catch (e: Exception) { }
        return
      }
    } ?: return

    val result = publicationOpener.open(
      asset,
      allowUserInteraction = false
    )

    if (result.isSuccess) {
      val publication = result.getOrNull()
      if (publication != null) {
        val locator = locatorFromLinkOrLocator(initialLocation, publication)
        val readerFragment = EpubReaderFragment.newInstance()
        readerFragment.initFactory(publication, locator)
        callback.invoke(readerFragment)
      } else {
        RNLog.w(reactContext, "Error: Publication is null")
      }
    } else {
      val exception = result.failureOrNull()
      RNLog.w(reactContext, "Error executing ReaderService.openPublication: $exception")
      // Attempt to clean up the file
      try {
        file.delete()
      } catch (e: Exception) {
        // Ignore deletion errors
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
