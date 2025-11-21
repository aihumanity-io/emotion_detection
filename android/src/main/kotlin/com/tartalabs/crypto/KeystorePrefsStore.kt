/*
 * Copyright (c) 2025.
 * David Chiu
 * Created: .
 */

package com.tartalabs.crypto

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class KeystorePrefsStore(
    context: Context,
    private val alias: String = "tlabs.lic.aes",
    prefsName: String = "lic_store"
) : SecretStore {

    private val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
    private fun ensureKey(): SecretKey {
        val ks = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }

        fun gen(strongBox: Boolean): SecretKey {
            val specB = KeyGenParameterSpec.Builder(
                alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUserAuthenticationRequired(false)
            if (strongBox) {
                try { specB.setIsStrongBoxBacked(true) } catch (_: Throwable) { /* ignore */ }
            }
            val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            kg.init(specB.build())
            return kg.generateKey()
        }

        return try { gen(true) } catch (_: Throwable) { gen(false) }
    }

    /*private fun ensureKey(): SecretKey {
        val ks = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setIsStrongBoxBacked(true) // best-effort
            .setUserAuthenticationRequired(false)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(spec); generateKey()
        }
    }*/

    override fun put(key: String, value: ByteArray) {
        val k = ensureKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, k)           // ✅ no IV param
        val iv = cipher.iv                            // <- capture the generated IV (12 bytes)
        val ctTag = cipher.doFinal(value)
        /*val iv = ByteArray(12).also { java.security.SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, k, GCMParameterSpec(128, iv))
        }
        val ctTag = cipher.doFinal(value)
         */
        val packed = listOf(iv, ctTag).joinToString(".") {
            Base64.encodeToString(it, Base64.NO_WRAP or Base64.URL_SAFE)
        }
        prefs.edit().putString(key, packed).apply()
    }

    override fun get(key: String): ByteArray? {
        val packed = prefs.getString(key, null) ?: return null
        val parts = packed.split(".")
        val iv = Base64.decode(parts[0], Base64.NO_WRAP or Base64.URL_SAFE)
        val ctTag = Base64.decode(parts[1], Base64.NO_WRAP or Base64.URL_SAFE)
        val k = ensureKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, k, GCMParameterSpec(128, iv))
        }
        return cipher.doFinal(ctTag)
    }

    override fun remove(key: String) { prefs.edit().remove(key).apply() }
}
