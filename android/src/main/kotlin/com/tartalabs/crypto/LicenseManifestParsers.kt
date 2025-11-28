
// LicenseManifestParsers.kt
package com.tartalabs.crypto

import org.json.JSONObject

data class WrapDoc(
    val type: String,
    val iv: ByteArray,
    val salt: ByteArray,
    val shardRequired: Boolean
)

data class ModelManifest(
    val modelId: String,
    val aad: String,
    val gcmIv: ByteArray,
    val plainSha256B64Url: String,
    val wrappedCek: ByteArray,
    val wrap: WrapDoc
)

object Parsers {
    fun manifestFrom(json: String): ModelManifest {
        val j = JSONObject(json)
        val w = j.getJSONObject("wrap")
        val wrapDoc = WrapDoc(
            type = w.getString("type"),
            iv = B64Url.dec(w.getString("iv")),
            salt = B64Url.dec(w.getString("salt")),
            shardRequired = w.optBoolean("shardRequired", false)
        )
        return ModelManifest(
            modelId = j.getString("modelId"),
            aad = j.optString("aad", ""),
            gcmIv = B64Url.dec(j.getString("gcmIv")),
            plainSha256B64Url = j.getString("plainSha256"),
            wrappedCek = B64Url.dec(j.getString("wrappedCek")),
            wrap = wrapDoc
        )
    }
}
