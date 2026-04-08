
// Gcm.kt
package com.tartalabs.crypto

import java.io.InputStream
import java.io.OutputStream
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

object Gcm {
    fun decryptCekWrap(kekBytes: ByteArray, wrapIv: ByteArray, wrappedCtTag: ByteArray, aad: ByteArray? = null): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(kekBytes, "AES"), GCMParameterSpec(128, wrapIv))
        aad?.let { cipher.updateAAD(it) }
        return cipher.doFinal(wrappedCtTag) // 32B CEK
    }

    fun decryptModelTo(cekBytes: ByteArray, gcmIv: ByteArray, encIn: InputStream, out: OutputStream, aad: ByteArray? = null) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(cekBytes, "AES"), GCMParameterSpec(128, gcmIv))
        aad?.let { cipher.updateAAD(it) }
        CipherInputStream(encIn, cipher).use { cis -> cis.copyTo(out, 1 shl 16) }
    }

    // Legacy combined format: nonce|ciphertext|tag in one file/stream.
    fun decryptModelCombinedTo(cekBytes: ByteArray, combinedIn: InputStream, out: OutputStream, aad: ByteArray? = null) {
        val combined = combinedIn.readBytes()
        require(combined.size > 12 + 16) { "combined ciphertext is too short" }
        val iv = combined.copyOfRange(0, 12)
        val ctTag = combined.copyOfRange(12, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(cekBytes, "AES"), GCMParameterSpec(128, iv))
        aad?.let { cipher.updateAAD(it) }
        out.write(cipher.doFinal(ctTag))
    }
}
