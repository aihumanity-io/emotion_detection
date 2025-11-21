
// LicenseManifestParsers.kt
package com.tartalabs.crypto

import org.json.JSONObject

data class LicenseDoc(
    val userId: String,
    val modelId: String,
    val wrapType: String,               // "HKDF-SHA256+code+user+model" or "...+code+shard+user+model"
    val wrapIv: ByteArray,
    val salt: ByteArray,                // SHA256(userId)
    val shardUsed: Boolean,
    val wrappedCek: ByteArray,          // ct||tag
    val plainSha256B64Url: String
)

data class ModelManifest(
    val modelId: String,
    val gcmIv: ByteArray,
    val plainSha256B64Url: String
)

object Parsers {
    fun licenseFrom(json: String): LicenseDoc {
        val j = JSONObject(json)
        val w = j.getJSONObject("wrap")
        return LicenseDoc(
            userId = j.getString("userId"),
            modelId = j.getString("modelId"),
            wrapType = w.getString("type"),
            wrapIv = B64Url.dec(w.getString("wrapIv")),
            salt = B64Url.dec(w.getString("salt")),
            shardUsed = w.optBoolean("shardUsed", false),
            wrappedCek = B64Url.dec(j.getString("wrappedCek")),
            plainSha256B64Url = j.getString("plainSha256")
        )
    }
    fun manifestFrom(json: String): ModelManifest {
        val j = JSONObject(json)
        return ModelManifest(
            modelId = j.getString("modelId"),
            gcmIv = B64Url.dec(j.getString("gcmIv")),
            plainSha256B64Url = j.getString("plainSha256")
        )
    }
}
