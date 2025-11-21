
// SecureStore.kt
package com.tartalabs.crypto

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/*
object LicKeys {
    const val USER_CODE = "userCode32"
    const val SHARD     = "serverShard"
    const val CEK_DEV   = "cachedCek_wrapped_with_deviceKek" // optional cached CEK wrap
}

 */

class SecureStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("lic_store", Context.MODE_PRIVATE)
    private val alias = "tlabs.lic.aes"

    private fun ensureKey(): SecretKey {
        val ks = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setIsStrongBoxBacked(true)          // best effort
            .setUserAuthenticationRequired(false)
            .build()
        val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        kg.init(spec)
        return kg.generateKey()
    }

    private fun encKey(): SecretKey = ensureKey()

    fun putBytes(key: String, value: ByteArray) {
        val k = encKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = ByteArray(12).also { java.security.SecureRandom().nextBytes(it) }
        cipher.init(Cipher.ENCRYPT_MODE, k, GCMParameterSpec(128, iv))
        val out = cipher.doFinal(value)
        val packed = listOf(iv, out).joinToString(".") { Base64.encodeToString(it, Base64.NO_WRAP or Base64.URL_SAFE) }
        prefs.edit().putString(key, packed).apply()
    }

    fun getBytes(key: String): ByteArray? {
        val packed = prefs.getString(key, null) ?: return null
        val (ivB64, ctTagB64) = packed.split(".").let { it[0] to it[1] }
        val iv = Base64.decode(ivB64, Base64.NO_WRAP or Base64.URL_SAFE)
        val ctTag = Base64.decode(ctTagB64, Base64.NO_WRAP or Base64.URL_SAFE)
        val k = encKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, k, GCMParameterSpec(128, iv))
        return cipher.doFinal(ctTag)
    }

    fun remove(key: String) { prefs.edit().remove(key).apply() }
}
