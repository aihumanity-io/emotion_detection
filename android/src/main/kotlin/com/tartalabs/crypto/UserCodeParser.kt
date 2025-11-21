/*
 * Copyright (c) 2025.
 * David Chiu
 * Created:   9-11-2025
 */

package com.tartalabs.crypto

// UserCodeParser.kt

object UserCodeParser {

    /** Parse a user code string into exactly 32 bytes. Supports:
     *  - plain base64 or base64url (with or without '=' padding)
     *  - "b64:<...>" or "base64:<...>" prefixes
     *  - hex via "hex:<...>" or "0x..." (even-length, no spaces)
     */
    fun parse32(input: String): ByteArray {
        val s = input.trim()

        // prefixed forms
        val lower = s.lowercase()
        return when {
            lower.startsWith("b64:") || lower.startsWith("base64:") ->
                decodeB64(s.substringAfter(':'))
            lower.startsWith("hex:") ->
                decodeHex(s.substringAfter(':'))
            lower.startsWith("0x") ->
                decodeHex(s)
            else -> {
                // try base64/base64url first
                decodeB64(s)
            }
        }.also { bytes ->
            require(bytes.size == 32) {
                "User code must decode to 32 bytes, got ${bytes.size}."
            }
        }
    }

    private fun decodeB64(s: String): ByteArray {
        // URL-safe and std base64 with optional missing padding
        val t = s.trim()
        val urlSafe = t.replace('+', '-').replace('/', '_').trimEnd('=')
        val pad = (4 - (urlSafe.length % 4)) % 4
        val padded = urlSafe + "=".repeat(pad)
        return android.util.Base64.decode(padded, android.util.Base64.NO_WRAP or android.util.Base64.URL_SAFE)
    }

    private fun decodeHex(hexIn: String): ByteArray {
        val h = hexIn.trim().removePrefix("0x").replace(" ", "")
        require(h.length % 2 == 0) { "Hex string must have even length" }
        val out = ByteArray(h.length / 2)
        var i = 0
        while (i < h.length) {
            val byteStr = h.substring(i, i + 2)
            out[i / 2] = byteStr.toInt(16).toByte()
            i += 2
        }
        return out
    }
}
