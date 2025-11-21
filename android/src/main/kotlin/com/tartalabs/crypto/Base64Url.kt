/*
 * Copyright (c) 2025.
 * David Chiu
 * Created:   9, 11, 2025
 */

package com.tartalabs.crypto

import android.util.Base64

object Base64Url {
    private const val FLAGS = Base64.NO_WRAP or Base64.URL_SAFE

    /** Encode to URL-safe Base64 without padding (=). */
    fun enc(bytes: ByteArray): String =
        Base64.encodeToString(bytes, FLAGS).trimEnd('=')

    /** Decode from URL-safe Base64 with optional missing padding. */
    fun dec(s: String): ByteArray {
        val pad = (4 - (s.length % 4)) % 4
        val padded = if (pad == 0) s else s + "=".repeat(pad)
        return Base64.decode(padded, FLAGS)
    }
}

