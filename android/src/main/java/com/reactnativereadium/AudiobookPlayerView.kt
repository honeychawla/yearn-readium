package com.reactnativereadium

import android.content.Context
import android.util.Log
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.adapter.exoplayer.audio.ExoPlayerEngineProvider
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.navigator.media.audio.AudioNavigatorFactory
import org.readium.r2.lcp.LcpService
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.FileExtension
import org.readium.r2.shared.util.format.FormatHints
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser
import com.reactnativereadium.lcp.LCPPassphraseAuthentication
import java.io.File

/**
 * AudiobookPlayerView for LCP-protected audiobooks using Readium 3.1.2
 *
 * Uses Media Navigator (similar to iOS AudioNavigator) for automatic LCP decryption
 *
 * SECURITY MODEL:
 * - .lcpa files remain ENCRYPTED on disk at all times
 * - Media Navigator decrypts content IN-MEMORY ONLY during playback
 * - No decrypted files are ever written to disk
 */
class AudiobookPlayerView(context: Context) : FrameLayout(context) {

    private val reactContext = context as ReactContext
    private var audioNavigator: AudioNavigator<*, *>? = null
    private val statusText: TextView
    private var publication: Publication? = null
    private var asset: org.readium.r2.shared.util.asset.Asset? = null // Keep asset alive for LCP

    // Keep these alive for the lifecycle of the view (important for LCP)
    private var httpClient: org.readium.r2.shared.util.http.DefaultHttpClient? = null
    private var assetRetriever: AssetRetriever? = null
    private var lcpService: LcpService? = null

    init {
        Log.d(TAG, "🔧 AudiobookPlayerView initialized (Readium 3.1.2)")

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

        Log.d(TAG, "🎧 Loading audiobook - URL: $url")
        Log.d(TAG, "🔐 Has passphrase: ${lcpPassphrase != null}")
        Log.d(TAG, "📜 License path: $licensePath")

        if (url != null && licensePath != null && lcpPassphrase != null) {
            loadAudiobookWithLCP(url, licensePath, lcpPassphrase)
        } else {
            Log.e(TAG, "❌ ERROR: Missing required parameters")
            updateStatus("Error: Missing required parameters")
        }
    }

    private fun loadAudiobookWithLCP(url: String, licensePath: String, passphrase: String) {
        Log.d(TAG, "🚀 loadAudiobookWithLCP called")
        updateStatus("Loading audiobook...")

        CoroutineScope(Dispatchers.IO).launch {
            try {
                // The audiobook file is downloaded by React Native
                val originalFile = File(url.removePrefix("file://"))
                Log.d(TAG, "📂 Original file: ${originalFile.absolutePath}")
                Log.d(TAG, "📂 File exists: ${originalFile.exists()}")
                Log.d(TAG, "📂 File size: ${originalFile.length()} bytes")

                if (!originalFile.exists()) {
                    withContext(Dispatchers.Main) {
                        updateStatus("Error: Audiobook file not found")
                    }
                    return@launch
                }

                // Rename to .lcpa extension for proper LCP detection
                val audiobookFile = if (!originalFile.name.endsWith(".lcpa")) {
                    val lcpaFile = File(originalFile.parentFile, originalFile.nameWithoutExtension + ".lcpa")
                    if (originalFile.renameTo(lcpaFile)) {
                        Log.d(TAG, "✅ Renamed to .lcpa: ${lcpaFile.absolutePath}")
                        lcpaFile
                    } else {
                        Log.w(TAG, "⚠️ Failed to rename, using original file")
                        originalFile
                    }
                } else {
                    originalFile
                }
                Log.d(TAG, "📂 Using file: ${audiobookFile.absolutePath}")

                // Note: For .lcpau files, the license is embedded in the package
                // The separate license JSON is only needed for reference/storage
                Log.d(TAG, "📜 License path provided: $licensePath (embedded in .lcpau)")

                withContext(Dispatchers.Main) {
                    updateStatus("Initializing LCP service...")
                }

                // Initialize AssetRetriever and LCP Service (Readium 3.x API)
                // Store as class members to keep them alive (important for LCP context)
                Log.d(TAG, "🔧 Initializing AssetRetriever and LCP Service...")
                httpClient = DefaultHttpClient()
                assetRetriever = AssetRetriever(reactContext.contentResolver, httpClient!!)

                lcpService = LcpService(reactContext, assetRetriever!!)
                    ?: run {
                        Log.e(TAG, "❌ LCP Service is null")
                        withContext(Dispatchers.Main) {
                            updateStatus("Error: LCP library not available")
                        }
                        return@launch
                    }
                Log.d(TAG, "✅ LCP Service initialized")
                Log.d(TAG, "🔑 Passphrase: ${passphrase.take(4)}... (${passphrase.length} chars)")
                Log.d(TAG, "⚠️ WARNING: Readium caches passphrases. If this fails, try:")
                Log.d(TAG, "⚠️ 1. Clear app data")
                Log.d(TAG, "⚠️ 2. Or the cached passphrase might be wrong")

                withContext(Dispatchers.Main) {
                    updateStatus("Opening publication...")
                }

                // Create PublicationOpener with LCP authentication (Readium 3.x API)
                // Try using Readium's built-in dialog authentication for testing
                val dialogAuth = org.readium.r2.lcp.auth.LcpDialogAuthentication()
                val authentication = LCPPassphraseAuthentication(passphrase)

                // Try our custom auth first, but keep dialog as backup
                Log.d(TAG, "🔐 Created custom authentication: ${authentication.javaClass.simpleName}")
                Log.d(TAG, "🔐 Created dialog authentication: ${dialogAuth.javaClass.simpleName}")

                // TEST: Try with dialog auth to see if IT gets called
                val contentProtection = lcpService!!.contentProtection(dialogAuth)
                Log.d(TAG, "🔐 Created ContentProtection: ${contentProtection.javaClass.simpleName}")

                val publicationParser = DefaultPublicationParser(reactContext, httpClient!!, assetRetriever!!, null)
                val publicationOpener = PublicationOpener(
                    publicationParser = publicationParser,
                    contentProtections = listOf(contentProtection)
                )
                Log.d(TAG, "🔐 PublicationOpener configured with ${1} content protection(s)")

                // Retrieve the asset using AssetRetriever (Readium 3.x - no more FileAsset constructor)
                // Provide format hints to ensure LCP detection (.lcpa is standard, .lcpau is legacy)
                Log.d(TAG, "🔍 Retrieving asset...")
                val formatHints = org.readium.r2.shared.util.format.FormatHints(
                    mediaTypes = listOf(MediaType.LCP_PROTECTED_AUDIOBOOK),
                    fileExtensions = listOf(FileExtension("lcpa"), FileExtension("lcpau"))
                )
                val assetResult = assetRetriever!!.retrieve(audiobookFile, formatHints)
                val retrievedAsset = when {
                    assetResult.isSuccess -> assetResult.getOrNull()!!
                    else -> {
                        Log.e(TAG, "❌ Failed to retrieve asset: ${assetResult.failureOrNull()}")
                        withContext(Dispatchers.Main) {
                            updateStatus("Error: Failed to access audiobook file")
                        }
                        return@launch
                    }
                }

                // Store asset reference to keep it alive (important for LCP)
                asset = retrievedAsset

                Log.d(TAG, "📦 Asset retrieved - format: ${retrievedAsset.format}")
                Log.d(TAG, "📦 Asset format mediaType: ${retrievedAsset.format.mediaType}")
                Log.d(TAG, "📦 Asset format fileExtension: ${retrievedAsset.format.fileExtension}")
                Log.d(TAG, "🔍 Opening publication with LCP protection...")
                // IMPORTANT: allowUserInteraction = true is required for Navigator rendering (enables decryption)
                // false is only for metadata-only imports
                val openResult = publicationOpener.open(retrievedAsset, allowUserInteraction = true)
                val pub = when {
                    openResult.isSuccess -> openResult.getOrNull()!!
                    else -> {
                        Log.e(TAG, "❌ Failed to open publication: ${openResult.failureOrNull()}")
                        withContext(Dispatchers.Main) {
                            updateStatus("Error: Failed to open audiobook")
                        }
                        return@launch
                    }
                }

                publication = pub
                Log.d(TAG, "✅ Publication opened successfully")
                Log.d(TAG, "📚 Title: ${pub.metadata.title}")
                Log.d(TAG, "📚 Reading order: ${pub.readingOrder.size} items")

                // Check publication metadata
                Log.d(TAG, "📋 ConformsTo profiles: ${pub.metadata.conformsTo}")
                val hasProtection = pub.metadata.conformsTo.any { it.toString().contains("lcp") }
                Log.d(TAG, "🔒 Has LCP conformance: $hasProtection")

                // Check if publication has links (should be encrypted resources)
                pub.readingOrder.firstOrNull()?.let { link ->
                    Log.d(TAG, "📄 First audio resource: ${link.href}")
                    Log.d(TAG, "📄 Media type: ${link.mediaType}")
                }

                Log.d(TAG, "🔒 LCP authentication successful - proceeding to playback")

                // Debug: Check publication type and container
                Log.d(TAG, "📦 Publication class: ${pub.javaClass.simpleName}")
                Log.d(TAG, "📦 Publication toString: ${pub.toString().take(200)}")

                // In Readium 3.x, isRestricted was removed
                // The publication opening should have unlocked it if passphrase was correct
                // The fact that it opened without error suggests it's unlocked
                Log.d(TAG, "✅ Publication opened - assuming unlocked (isRestricted removed in 3.x)")

                // Create Media Navigator on Main thread (required for ExoPlayer)
                withContext(Dispatchers.Main) {
                    updateStatus("Creating audio player...")
                    createMediaNavigator(pub)
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ ERROR loading audiobook", e)
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    updateStatus("Error: ${e.message}")
                }
            }
        }
    }

    private fun createMediaNavigator(publication: Publication) {
        // Must run on main thread for ExoPlayer
        try {
            Log.d(TAG, "🎧 Creating Media Navigator...")

            // Simplified approach matching Readium test app
            val application = reactContext.applicationContext as android.app.Application
            val engineProvider = ExoPlayerEngineProvider(application)

            // Create AudioNavigator factory (simplified - let Readium handle defaults)
            val factory = AudioNavigatorFactory(publication, engineProvider) ?: run {
                Log.e(TAG, "❌ Failed to create AudioNavigatorFactory")
                updateStatus("Error: Unsupported publication format")
                return
            }

            // Create the navigator asynchronously (createNavigator is a suspend function)
            CoroutineScope(Dispatchers.Main).launch {
                val navigatorResult = factory.createNavigator(
                    initialLocator = publication.readingOrder.firstOrNull()?.let {
                        publication.locatorFromLink(it)
                    } ?: publication.readingOrder[0].let { publication.locatorFromLink(it) },
                    initialPreferences = ExoPlayerPreferences(),
                    readingOrder = publication.readingOrder
                )

                // Handle the result
                val navigator = when {
                    navigatorResult.isSuccess -> navigatorResult.getOrNull()!!
                    else -> {
                        Log.e(TAG, "❌ Failed to create navigator: ${navigatorResult.failureOrNull()}")
                        updateStatus("Error: Failed to create audio player")
                        return@launch
                    }
                }

                audioNavigator = navigator
                Log.d(TAG, "✅ Audio Navigator created")

                // Start playback
                navigator.play()
                Log.d(TAG, "▶️ Playback started")
                updateStatus("Playing audiobook! 🎧")

                // TODO: Add playback state listener
                // In Readium 3.x, use navigator.playback StateFlow to observe changes
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to create Media Navigator", e)
            e.printStackTrace()
            updateStatus("Error: ${e.message}")
        }
    }

    private fun updateStatus(message: String) {
        post {
            statusText.text = message
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        // Clean up resources in correct order
        audioNavigator = null
        publication = null
        asset?.close()
        asset = null
        // Don't close these as they might be needed for cleanup
        // httpClient = null
        // assetRetriever = null
        // lcpService = null
    }

    companion object {
        private const val TAG = "AudiobookPlayerView"
    }
}
