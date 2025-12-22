package com.reactnativereadium

import android.content.Context
import android.util.Log
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.RCTEventEmitter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.r2.lcp.LcpService
import org.readium.r2.lcp.LcpContentProtection
import org.readium.r2.lcp.auth.LcpPassphraseAuthentication
import org.readium.navigator.media.audio.ExoAudioNavigator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.asset.AssetRetriever
import org.readium.r2.shared.publication.services.ContentProtectionService
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.streamer.parser.PublicationParser
import org.readium.r2.streamer.PublicationOpener
import java.io.File

class AudiobookPlayerView(context: Context) : FrameLayout(context) {

    private val reactContext = context as ReactContext
    private var audioNavigator: ExoAudioNavigator? = null
    private val statusText: TextView

    init {
        Log.d(TAG, "🔧 AudiobookPlayerView initialized")

        // Add status text view for debugging
        statusText = TextView(context).apply {
            text = "Initializing audiobook player..."
            textSize = 16f
            setTextColor(ContextCompat.getColor(context, android.R.color.white))
            setPadding(40, 40, 40, 40)
        }
        addView(statusText)
    }

    fun setFile(file: ReadableMap) {
        Log.d(TAG, "📥 File prop received")

        val url = file.getString("url")
        val lcpPassphrase = file.getString("lcpPassphrase")
        val licensePath = file.getString("licensePath")

        Log.d(TAG, "🎧 Loading audiobook from URL: $url")
        Log.d(TAG, "🔐 Has passphrase: ${lcpPassphrase != null}")
        Log.d(TAG, "📜 License path: $licensePath")

        if (url != null && licensePath != null && lcpPassphrase != null) {
            loadAudiobookViaLicense(url, licensePath, lcpPassphrase)
        } else {
            Log.e(TAG, "❌ ERROR: Missing required parameters")
            updateStatus("Error: Missing required parameters")
        }
    }

    private fun loadAudiobookViaLicense(url: String, licensePath: String, passphrase: String) {
        Log.d(TAG, "🚀 loadAudiobookViaLicense called")
        updateStatus("Loading audiobook via license...")

        CoroutineScope(Dispatchers.Main).launch {
            try {
                // Read license JSON from file
                val licenseFile = File(licensePath.removePrefix("file://"))
                val licenseData = licenseFile.readBytes()

                Log.d(TAG, "📜 License JSON loaded (${licenseData.size} bytes)")
                updateStatus("License loaded, acquiring publication...")

                // Initialize LCP Service
                val httpClient = DefaultHttpClient()
                val assetRetriever = AssetRetriever(httpClient, reactContext.contentResolver)

                val lcpService = LcpService(reactContext)?.let { service ->
                    Log.d(TAG, "✅ LCP Service initialized")
                    service
                } ?: run {
                    Log.e(TAG, "❌ Failed to initialize LCP Service")
                    updateStatus("Error: Failed to initialize LCP Service")
                    return@launch
                }

                // Acquire publication from license
                Log.d(TAG, "📥 Acquiring publication from license...")
                val acquired = lcpService.acquirePublication(
                    licenseDocument = licenseData,
                    onProgress = { progress ->
                        Log.d(TAG, "📥 Download progress: $progress")
                        updateStatus("Downloading: ${(progress * 100).toInt()}%")
                    }
                ).getOrElse { error ->
                    Log.e(TAG, "❌ Failed to acquire publication: $error")
                    updateStatus("Error acquiring publication: $error")
                    return@launch
                }

                Log.d(TAG, "✅ Publication acquired: ${acquired.localFile}")
                updateStatus("Opening publication...")

                // Open the downloaded publication
                val publicationOpener = PublicationOpener(
                    publicationParser = PublicationParser(
                        context = reactContext,
                        httpClient = httpClient,
                        assetRetriever = assetRetriever
                    ),
                    contentProtections = listOf(
                        LcpContentProtection(lcpService, LcpPassphraseAuthentication(passphrase))
                    )
                )

                val asset = assetRetriever.retrieve(acquired.localFile).getOrElse { error ->
                    Log.e(TAG, "❌ Failed to retrieve asset: $error")
                    updateStatus("Error retrieving asset: $error")
                    return@launch
                }

                val publicationResult = publicationOpener.open(
                    asset = asset,
                    allowUserInteraction = false
                ).getOrElse { error ->
                    Log.e(TAG, "❌ Failed to open publication: $error")
                    updateStatus("Error opening publication: $error")
                    return@launch
                }

                Log.d(TAG, "✅ Publication opened successfully")
                updateStatus("Creating audio player...")

                // Create audio navigator
                createAudioNavigator(publicationResult.publication)

            } catch (e: Exception) {
                Log.e(TAG, "❌ ERROR loading audiobook", e)
                updateStatus("Error: ${e.message}")
            }
        }
    }

    private suspend fun createAudioNavigator(publication: Publication) {
        withContext(Dispatchers.Main) {
            try {
                Log.d(TAG, "🎧 Creating ExoAudioNavigator...")

                audioNavigator = ExoAudioNavigator(
                    context = reactContext,
                    publication = publication
                )

                Log.d(TAG, "✅ ExoAudioNavigator created")
                updateStatus("Ready to play! Tap play to start.")

                // Auto-play
                audioNavigator?.play()
                Log.d(TAG, "▶️ Playback started")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to create audio navigator", e)
                updateStatus("Error creating player: ${e.message}")
            }
        }
    }

    private fun updateStatus(message: String) {
        post {
            statusText.text = message
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        audioNavigator?.close()
    }

    private fun sendEvent(eventName: String, params: WritableMap?) {
        reactContext
            .getJSModule(RCTEventEmitter::class.java)
            .receiveEvent(id, eventName, params)
    }

    companion object {
        private const val TAG = "AudiobookPlayerView"
    }
}

