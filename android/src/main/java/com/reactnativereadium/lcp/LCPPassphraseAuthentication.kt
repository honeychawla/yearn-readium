package com.reactnativereadium.lcp

import android.util.Log
import org.readium.r2.lcp.LcpAuthenticating
import java.security.MessageDigest

/**
 * LCP authentication that automatically provides a hashed passphrase
 * For Readium Android 2.4.1
 */
class LCPPassphraseAuthentication(
    private val passphrase: String
) : LcpAuthenticating {

    private val TAG = "LCPPassphraseAuth"

    private fun hashPassphrase(passphrase: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hashBytes = digest.digest(passphrase.toByteArray())
        return hashBytes.joinToString("") { "%02x".format(it) }
    }

    override suspend fun retrievePassphrase(
        license: LcpAuthenticating.AuthenticatedLicense,
        reason: LcpAuthenticating.AuthenticationReason,
        allowUserInteraction: Boolean,
        sender: Any?
    ): String {
        Log.d(TAG, "✅ Providing plaintext passphrase - Readium will hash internally (reason: $reason)")
        Log.d(TAG, "Passphrase: ${passphrase.take(8)}...")
        // Return plaintext - Readium will hash it with SHA-256 internally
        return passphrase
    }
}
