
// DeviceKek.kt
package com.tartalabs.crypto

import android.content.Context

/**
 * Derive a device KEK from a random 32B seed protected by the Keystore SecureStore itself.
 * We reuse SecureStore to hold that seed; then HKDF(seed, salt, info) yields a 32B device KEK.
 */

class DeviceKek(
    private val store: SecretStore,
    private val seedKey: String
) {
    private fun getOrCreateSeed(): ByteArray {
        store.get(seedKey)?.let { return it }
        val seed = ByteArray(32).also { java.security.SecureRandom().nextBytes(it) }
        store.put(seedKey, seed)
        return seed
    }

    fun derive(modelId: String): ByteArray {
        val seed = getOrCreateSeed()
        val salt = Hash.sha256("device.kek".toByteArray())
        val info = "model:$modelId".toByteArray()
        return HKDF.sha256(seed, salt, info, 32)
    }
}

