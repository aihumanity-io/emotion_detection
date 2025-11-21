package com.tartalabs.crypto

// HashAndKdf.kt

import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object Hash {
    fun sha256(data: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(data)
}

object HKDF {
    fun sha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(if (salt.isEmpty()) ByteArray(32) else salt, "HmacSHA256"))
        val prk = mac.doFinal(ikm)
        var t = ByteArray(0)
        val okm = ByteArrayOutputStream()
        var counter = 1
        while (okm.size() < length) {
            mac.init(SecretKeySpec(prk, "HmacSHA256"))
            mac.update(t); mac.update(info); mac.update(counter.toByte())
            t = mac.doFinal()
            val toWrite = minOf(t.size, length - okm.size())
            okm.write(t, 0, toWrite)
            counter++
        }
        return okm.toByteArray()
    }
}

object B64Url {
    fun enc(b: ByteArray) = android.util.Base64.encodeToString(b, android.util.Base64.NO_WRAP or android.util.Base64.URL_SAFE)
    fun dec(s: String) = android.util.Base64.decode(s, android.util.Base64.NO_WRAP or android.util.Base64.URL_SAFE)
}
