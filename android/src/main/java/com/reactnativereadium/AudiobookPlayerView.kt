package com.reactnativereadium

import android.content.Context
import android.net.Uri
import android.util.Log
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.RCTEventEmitter
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.source.ProgressiveMediaSource
import com.google.android.exoplayer2.upstream.DataSource
import com.google.android.exoplayer2.upstream.DataSpec
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.r2.lcp.LcpService
import org.readium.r2.shared.extensions.tryOrNull
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.asset.FileAsset
import org.readium.r2.streamer.Streamer
import com.reactnativereadium.lcp.LCPPassphraseAuthentication
import java.io.File
import java.io.InputStream

/**
 * AudiobookPlayerView for LCP-protected audiobooks using Readium 2.4.1
 *
 * SECURITY MODEL:
 * - .lcpa files remain ENCRYPTED on disk at all times
 * - Readium's Streamer decrypts content IN-MEMORY ONLY during playback
 * - ExoPlayer streams the decrypted audio from memory
 * - No decrypted files are ever written to disk
 */
class AudiobookPlayerView(context: Context) : FrameLayout(context) {

    private val reactContext = context as ReactContext
    private var player: ExoPlayer? = null
    private val statusText: TextView
    private var publication: Publication? = null

    init {
        Log.d(TAG, "🔧 AudiobookPlayerView initialized")

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
            loadAudiobookViaLicense(url, licensePath, lcpPassphrase)
        } else {
            Log.e(TAG, "❌ ERROR: Missing required parameters")
            updateStatus("Error: Missing required parameters")
        }
    }

    private fun loadAudiobookViaLicense(url: String, licensePath: String, passphrase: String) {
        Log.d(TAG, "🚀 loadAudiobookViaLicense called")
        updateStatus("Loading audiobook via license...")

        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Read license JSON from file
                val licenseFile = File(licensePath.removePrefix("file://"))
                val licenseData = licenseFile.readBytes()

                Log.d(TAG, "📜 License JSON loaded (${licenseData.size} bytes)")
                withContext(Dispatchers.Main) {
                    updateStatus("License loaded, acquiring publication...")
                }

                // Initialize LCP Service (Readium 2.4.1 API)
                val lcpService = LcpService(reactContext)
                if (lcpService == null) {
                    Log.e(TAG, "❌ LCP Service is null - liblcp.so missing?")
                    withContext(Dispatchers.Main) {
                        updateStatus("Error: LCP library not available")
                    }
                    return@launch
                }
                Log.d(TAG, "✅ LCP Service initialized")

                // CRITICAL FIX: Clear passphrase cache to force re-authentication
                // The cached hash from iOS doesn't work on Android
                try {
                    // Clear the passphrase database
                    val lcpDir = File(reactContext.filesDir, "lcp")
                    if (lcpDir.exists()) {
                        lcpDir.deleteRecursively()
                        Log.d(TAG, "🗑️ Cleared LCP passphrase cache in filesDir")
                    }
                    // Also check cache dir
                    val lcpCacheDir = File(reactContext.cacheDir, "lcp")
                    if (lcpCacheDir.exists()) {
                        lcpCacheDir.deleteRecursively()
                        Log.d(TAG, "🗑️ Cleared LCP passphrase cache in cacheDir")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Could not clear LCP cache: $e")
                }

                // Ensure cache directory exists and is writable
                val cacheDir = reactContext.cacheDir
                if (!cacheDir.exists()) {
                    cacheDir.mkdirs()
                }
                Log.d(TAG, "📁 Cache dir: ${cacheDir.absolutePath}")
                Log.d(TAG, "📁 Cache writable: ${cacheDir.canWrite()}")

                // Acquire publication from license document (Readium 2.4.1 API: lcpl parameter)
                Log.d(TAG, "📥 Acquiring publication from license...")
                val acquisitionResult = lcpService.acquirePublication(
                    lcpl = licenseData,
                    onProgress = { progress: Double ->
                        Log.d(TAG, "📥 Download progress: $progress")
                        CoroutineScope(Dispatchers.Main).launch {
                            updateStatus("Downloading: ${(progress * 100).toInt()}%")
                        }
                    }
                )

                // Debug: Log the result type
                Log.d(TAG, "📊 Acquisition result type: ${acquisitionResult::class.java.simpleName}")
                Log.d(TAG, "📊 Acquisition result: $acquisitionResult")

                // Work around metadata version mismatch - use fold() which is a core method
                val acquired = acquisitionResult.fold(
                    onSuccess = { it },
                    onFailure = { error ->
                        Log.e(TAG, "❌ Failed to acquire publication: $error")

                        // Provide helpful error messages
                        val errorMsg = when {
                            error.toString().contains("WriteFailed") -> "Storage full or write permission denied. Free up space and try again."
                            error.toString().contains("Network") -> "Network error during download"
                            else -> "Acquisition failed: $error"
                        }

                        withContext(Dispatchers.Main) {
                            updateStatus(errorMsg)
                        }
                        return@launch
                    }
                )

                Log.d(TAG, "✅ Publication acquired: ${acquired.localFile}")
                Log.d(TAG, "📁 File exists: ${acquired.localFile.exists()}")
                Log.d(TAG, "📁 File size: ${acquired.localFile.length()} bytes")

                withContext(Dispatchers.Main) {
                    updateStatus("Opening publication with LCP protection...")
                }

                // CRITICAL: Must use ContentProtection even after acquisition
                // Acquisition downloads the file but doesn't decrypt it
                val streamer = Streamer(
                    context = reactContext,
                    contentProtections = listOf(
                        lcpService.contentProtection(LCPPassphraseAuthentication(passphrase))
                    )
                )

                val asset = FileAsset(acquired.localFile)
                Log.d(TAG, "🔍 Opening publication WITH ContentProtection")

                val publicationResult = streamer.open(
                    asset = asset,
                    allowUserInteraction = false,
                    sender = reactContext
                )

                // Use fold() to extract publication
                val pub = publicationResult.fold(
                    onSuccess = { it },
                    onFailure = { error ->
                        Log.e(TAG, "❌ Failed to open publication: $error")
                        withContext(Dispatchers.Main) {
                            updateStatus("Error opening publication: $error")
                        }
                        return@launch
                    }
                )

                publication = pub
                Log.d(TAG, "✅ Publication opened successfully")
                Log.d(TAG, "📚 Title: ${publication!!.metadata.title}")
                Log.d(TAG, "📚 Reading order has ${publication!!.readingOrder.size} items")

                // CRITICAL: Check if publication is still restricted
                // In Readium 2.4.1, check the rights via LCP service
                val contentProtectionService = publication!!.findService(org.readium.r2.shared.publication.services.ContentProtectionService::class)
                Log.d(TAG, "🔍 ContentProtectionService: $contentProtectionService")

                if (contentProtectionService != null) {
                    Log.d(TAG, "🔒 Publication has content protection")
                    val rights = contentProtectionService.rights
                    Log.d(TAG, "🔒 Rights type: ${rights::class.java.simpleName}")
                    Log.d(TAG, "🔒 Rights: $rights")

                    // AllRestricted means the publication cannot be read
                    // This usually means the passphrase was wrong or license is invalid
                    if (rights is org.readium.r2.shared.publication.services.ContentProtectionService.UserRights.AllRestricted) {
                        Log.e(TAG, "❌ CRITICAL: Publication is AllRestricted - cannot read content!")
                        Log.e(TAG, "This means either:")
                        Log.e(TAG, "  1. Passphrase is incorrect")
                        Log.e(TAG, "  2. License is expired/revoked")
                        Log.e(TAG, "  3. License doesn't grant read rights")
                        withContext(Dispatchers.Main) {
                            updateStatus("Error: Publication is restricted. Check passphrase or license validity.")
                        }
                        return@launch
                    }
                } else {
                    Log.d(TAG, "✅ No content protection service (publication unlocked)")
                }

                withContext(Dispatchers.Main) {
                    updateStatus("Creating audio player...")
                }

                // Create ExoPlayer and play decrypted audio
                createAudioPlayer(publication!!)

            } catch (e: Exception) {
                Log.e(TAG, "❌ ERROR loading audiobook", e)
                withContext(Dispatchers.Main) {
                    updateStatus("Error: ${e.message}")
                }
            }
        }
    }

    private suspend fun createAudioPlayer(publication: Publication) {
        withContext(Dispatchers.Main) {
            try {
                Log.d(TAG, "🎧 Creating ExoPlayer for audiobook...")

                // Initialize ExoPlayer
                player = ExoPlayer.Builder(reactContext).build()

                if (publication.readingOrder.isNotEmpty()) {
                    val firstLink = publication.readingOrder[0]
                    Log.d(TAG, "🎵 First audio link: ${firstLink.href}")
                    Log.d(TAG, "🎵 Media type: ${firstLink.mediaType}")

                    // Test: Read a SMALL chunk to verify decryption works (avoid OOM)
                    val testResource = publication.get(firstLink)
                    val testResult = kotlinx.coroutines.runBlocking {
                        testResource.read(0L..1024L) // Just read first 1KB
                    }

                    val testData = testResult.fold(
                        onSuccess = { it },
                        onFailure = { error ->
                            Log.e(TAG, "❌ Test chunk read failed: $error")
                            null
                        }
                    )

                    if (testData != null && testData.size > 0) {
                        Log.d(TAG, "✅ Test chunk read: ${testData.size} bytes")
                        Log.d(TAG, "🔓 Decryption working! First 16 bytes: ${testData.take(16).map { "%02x".format(it) }.joinToString("")}")
                    } else {
                        Log.e(TAG, "❌ Chunk read returned empty/null data")
                    }

                    // Get decrypted resource through Readium Publication
                    // KEY SECURITY FEATURE: This decrypts in-memory, file stays encrypted on disk!
                    val resource = publication.get(firstLink)

                    // Create custom DataSource that reads from Readium's decrypted Resource
                    val dataSourceFactory = ReadiumDataSource.Factory(publication, firstLink)
                    val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                        .createMediaSource(MediaItem.fromUri(Uri.parse("readium://audio/${firstLink.href}")))

                    player?.setMediaSource(mediaSource)
                    player?.prepare()
                    player?.play()

                    Log.d(TAG, "✅ ExoPlayer created and playing")
                    Log.d(TAG, "🔒 Security: Audio decrypted in-memory only, file encrypted on disk")
                    updateStatus("Playing audiobook! 🎧")

                    // Listen to playback state
                    player?.addListener(object : Player.Listener {
                        override fun onPlaybackStateChanged(state: Int) {
                            when (state) {
                                Player.STATE_BUFFERING -> updateStatus("Buffering...")
                                Player.STATE_READY -> updateStatus("Ready ✅")
                                Player.STATE_ENDED -> updateStatus("Playback ended")
                            }
                        }
                    })
                } else {
                    Log.e(TAG, "❌ No audio files in publication")
                    updateStatus("Error: No audio files found")
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to create audio player", e)
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
        player?.release()
        publication?.close()
    }

    private fun sendEvent(eventName: String, params: WritableMap?) {
        reactContext
            .getJSModule(RCTEventEmitter::class.java)
            .receiveEvent(id, eventName, params)
    }

    companion object {
        private const val TAG = "AudiobookPlayerView"
    }

    /**
     * Streaming DataSource that reads from Readium's decrypted Resource in chunks
     * This maintains encryption at rest - only decrypts chunks in memory during playback
     *
     * KEY: Uses range requests to avoid loading 735MB file into memory all at once
     */
    class ReadiumDataSource(
        private val publication: Publication,
        private val link: org.readium.r2.shared.publication.Link
    ) : DataSource {

        private var resource: org.readium.r2.shared.fetcher.Resource? = null
        private var currentPosition: Long = 0
        private var opened = false
        private var totalLength: Long = -1L

        override fun open(dataSpec: DataSpec): Long {
            if (opened) return -1L
            opened = true

            // Get decrypted resource from Readium Publication
            // Files stay encrypted on disk, chunks decrypted on-demand
            resource = publication.get(link)
            currentPosition = dataSpec.position

            // Try to get length from resource
            totalLength = kotlinx.coroutines.runBlocking {
                resource?.length()?.fold(
                    onSuccess = { it },
                    onFailure = { -1L }
                ) ?: -1L
            }

            Log.d("ReadiumDataSource", "✅ Opened resource for ${link.href}")
            Log.d("ReadiumDataSource", "📏 Starting position: $currentPosition")
            Log.d("ReadiumDataSource", "📏 Resource length: $totalLength")

            return totalLength
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            val res = resource ?: return -1

            // Read a chunk from current position
            val range = currentPosition until (currentPosition + length)

            val byteArray = kotlinx.coroutines.runBlocking {
                val result = res.read(range)
                result.fold(
                    onSuccess = { it },
                    onFailure = { error ->
                        Log.e("ReadiumDataSource", "Chunk read failed at $currentPosition: $error")
                        null
                    }
                )
            }

            if (byteArray == null || byteArray.isEmpty()) {
                return -1 // End of stream
            }

            // Copy to buffer
            val bytesToCopy = minOf(byteArray.size, length)
            System.arraycopy(byteArray, 0, buffer, offset, bytesToCopy)
            currentPosition += bytesToCopy

            return bytesToCopy
        }

        override fun close() {
            // Resource.close() is suspend in Readium 2.4.1
            resource?.let { res ->
                kotlinx.coroutines.runBlocking {
                    res.close()
                }
            }
            resource = null
            opened = false
            currentPosition = 0
        }

        override fun getUri(): Uri? = Uri.parse("readium://audio/${link.href}")
        override fun addTransferListener(transferListener: com.google.android.exoplayer2.upstream.TransferListener) {}

        class Factory(
            private val publication: Publication,
            private val link: org.readium.r2.shared.publication.Link
        ) : DataSource.Factory {
            override fun createDataSource(): DataSource = ReadiumDataSource(publication, link)
        }
    }
}
