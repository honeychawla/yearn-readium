package com.reactnativereadium.lcp

import android.content.Context
import android.util.Log
import org.readium.r2.lcp.LcpService
import org.readium.r2.shared.publication.ContentProtection

/**
 * LCP Service for Android Readium 2.4.1
 */
class LCPService(private val context: Context) {
    private val TAG = "LCPService"

    var lcpService: LcpService? = null

    init {
        try {
            // Initialize LcpService with just context
            lcpService = LcpService(context)
            if (lcpService != null) {
                Log.d(TAG, "✅ LCP Service initialized successfully")
            } else {
                Log.w(TAG, "⚠️ LCP Service returned null - liblcp may be missing")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to initialize LCP Service", e)
        }
    }

    /**
     * Get content protection for Streamer
     * Returns ContentProtection for use with Streamer's contentProtections parameter
     */
    fun getContentProtection(passphrase: String? = null): ContentProtection? {
        val service = lcpService ?: return null

        return try {
            val authentication = if (passphrase != null) {
                Log.d(TAG, "Creating LCP authentication with passphrase")
                LCPPassphraseAuthentication(passphrase)
            } else {
                Log.d(TAG, "Creating LCP authentication with empty passphrase (will prompt user)")
                LCPPassphraseAuthentication("")
            }

            service.contentProtection(authentication)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create content protection", e)
            null
        }
    }

    fun isAvailable(): Boolean {
        return lcpService != null
    }
}

