package com.reactnativereadium.lcp

import android.util.Log
import org.readium.r2.lcp.LcpAuthenticating

/**
 * LCP authentication that automatically provides a passphrase
 * Updated for Readium 3.x
 */
class LCPPassphraseAuthentication(
    private val passphrase: String
) : LcpAuthenticating {

    private val TAG = "LCPPassphraseAuth"

    /**
     * Readium 3.x keeps retrievePassphrase but removed the 'sender' parameter
     */
    override suspend fun retrievePassphrase(
        license: LcpAuthenticating.AuthenticatedLicense,
        reason: LcpAuthenticating.AuthenticationReason,
        allowUserInteraction: Boolean
    ): String {
        Log.d(TAG, "🔐🔐🔐 retrievePassphrase CALLED! 🔐🔐🔐")
        Log.d(TAG, "✅ Providing passphrase (reason: $reason)")
        Log.d(TAG, "📏 Passphrase length: ${passphrase.length}")
        Log.d(TAG, "🔑 Passphrase preview: ${passphrase.take(4)}...")
        Log.d(TAG, "🔑 Full passphrase: $passphrase")
        Log.d(TAG, "🔒 Allow user interaction: $allowUserInteraction")

        // Return plaintext - Readium will hash it with SHA-256 internally
        Log.d(TAG, "🔐 Returning passphrase to Readium")
        return passphrase
    }
}
