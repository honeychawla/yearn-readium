package com.reactnativereadium.lcp

import android.util.Log
import org.readium.r2.lcp.LcpAuthenticating

/**
 * LCP authentication that automatically provides a passphrase
 * For Readium Android 2.4.1
 */
class LCPPassphraseAuthentication(
    private val passphrase: String
) : LcpAuthenticating {

    private val TAG = "LCPPassphraseAuth"

    override suspend fun retrievePassphrase(
        license: LcpAuthenticating.AuthenticatedLicense,
        reason: LcpAuthenticating.AuthenticationReason,
        allowUserInteraction: Boolean,
        sender: Any?
    ): String {
        Log.d(TAG, "✅ Providing passphrase (reason: $reason)")
        Log.d(TAG, "📏 Passphrase length: ${passphrase.length}")
        Log.d(TAG, "🔑 Passphrase preview: ${passphrase.take(4)}...")
        // Return plaintext - Readium will hash it with SHA-256 internally
        return passphrase
    }
}
