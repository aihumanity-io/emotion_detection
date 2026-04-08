
// LicenseManifestParsers.kt
package com.tartalabs.crypto

import android.util.Base64
import org.json.JSONObject

data class WrapDoc(
    val type: String,
    val iv: ByteArray?,
    val salt: ByteArray?,
    val shardRequired: Boolean
)

data class ModelManifest(
    val modelId: String,
    val aad: String,
    val gcmIv: ByteArray?,
    val plainSha256B64Url: String?,
    val wrappedCek: ByteArray?,
    val distributionMode: String?,
    val algo: String?,
    val kdfInfo: String?,
    val wrap: WrapDoc
)

data class LicenseWrapDoc(
    val type: String,
    val wrapIv: ByteArray,
    val salt: ByteArray,
    val shardUsed: Boolean,
    val aad: String?
)

data class LicenseDoc(
    val version: Int?,
    val modelId: String,
    val algo: String?,
    val plainSha256: String?,
    val wrappedCek: ByteArray,
    val wrap: LicenseWrapDoc,
    val expiresAt: String?
)

enum class DistributionMode {
    UNIFIED,
    PER_DEVELOPER
}

object Parsers {
    private fun firstNonBlank(vararg values: String?): String? {
        for (v in values) {
            if (!v.isNullOrBlank()) return v.trim()
        }
        return null
    }

    private fun decodeB64Any(raw: String): ByteArray {
        val s = raw.trim()
        return try {
            B64Url.dec(s)
        } catch (_: IllegalArgumentException) {
            Base64.decode(s, Base64.NO_WRAP)
        }
    }

    private fun optB64(j: JSONObject, key: String): ByteArray? {
        val raw = j.optString(key, "")
        if (raw.isBlank()) return null
        return decodeB64Any(raw)
    }

    private fun optStringOrNull(j: JSONObject, key: String): String? {
        if (!j.has(key) || j.isNull(key)) return null
        val value = j.optString(key, "")
        return value.takeIf { it.isNotBlank() }
    }

    fun detectDistributionMode(man: ModelManifest): DistributionMode {
        val mode = man.distributionMode?.trim()?.lowercase()
        if (mode == "unified") return DistributionMode.UNIFIED
        if (mode == "per-developer") return DistributionMode.PER_DEVELOPER
        if (man.wrap.type.equals("external", ignoreCase = true)) return DistributionMode.UNIFIED
        if (man.wrap.type.equals("rsa-oaep-256", ignoreCase = true)) return DistributionMode.UNIFIED
        if (man.wrappedCek != null) return DistributionMode.PER_DEVELOPER
        return DistributionMode.UNIFIED
    }

    fun manifestFrom(json: String): ModelManifest {
        val j = JSONObject(json)
        val w = j.optJSONObject("wrap")
        val wrapType = w?.optString("type", "")?.trim().orEmpty()
        var wrappedCek = optB64(j, "wrappedCek")
        val wrappedLegacy = optB64(j, "wrapped_cek_b64")
        var wrapIv = w?.optString("iv", "")?.takeIf { it.isNotBlank() }?.let { decodeB64Any(it) }
        var wrapSalt = w?.optString("salt", "")?.takeIf { it.isNotBlank() }?.let { decodeB64Any(it) }
        val kdfInfo = j.optString("kdf_info", "").takeIf { it.isNotBlank() }

        // Legacy packed CEK wrap: wrapped_cek_b64 contains iv|ciphertext|tag.
        if (wrappedCek == null && wrappedLegacy != null) {
            if (wrappedLegacy.size > 12 + 16) {
                wrapIv = wrappedLegacy.copyOfRange(0, 12)
                wrappedCek = wrappedLegacy.copyOfRange(12, wrappedLegacy.size)
            } else {
                wrappedCek = wrappedLegacy
            }
            if (wrapSalt == null && kdfInfo != null) {
                wrapSalt = j.optString("aad", "").toByteArray()
            }
        }

        val modelId = firstNonBlank(
            optStringOrNull(j, "modelId"),
            optStringOrNull(j, "model_id"),
            optStringOrNull(j, "model_name")
        ) ?: error("Manifest missing modelId/model_id/model_name")

        val algo = firstNonBlank(optStringOrNull(j, "algo"), optStringOrNull(j, "algorithm"))
        val plainSha = j.optString("plainSha256", "").takeIf { it.isNotBlank() }
        val gcmIv = j.optString("gcmIv", "").takeIf { it.isNotBlank() }?.let { decodeB64Any(it) }
        val distMode = j.optString("distributionMode", "").takeIf { it.isNotBlank() }
        val wrapDoc = WrapDoc(
            type = wrapType,
            iv = wrapIv,
            salt = wrapSalt,
            shardRequired = (w?.optBoolean("shardRequired", false) == true)
                || j.optBoolean("shardRequired", false)
                || j.optBoolean("shard_required", false)
        )
        return ModelManifest(
            modelId = modelId,
            aad = j.optString("aad", ""),
            gcmIv = gcmIv,
            plainSha256B64Url = plainSha,
            wrappedCek = wrappedCek,
            distributionMode = distMode,
            algo = algo,
            kdfInfo = kdfInfo,
            wrap = wrapDoc
        )
    }

    fun licenseFromJson(json: String): LicenseDoc {
        val root = JSONObject(json)
        val j = root.optJSONObject("license") ?: root
        val w = j.optJSONObject("wrap") ?: error("License missing wrap object")
        val modelId = firstNonBlank(
            optStringOrNull(j, "modelId"),
            optStringOrNull(j, "model_id")
        ) ?: error("License missing modelId")
        val wrapIvRaw = firstNonBlank(
            optStringOrNull(w, "wrapIv"),
            optStringOrNull(w, "iv")
        ) ?: error("License wrap missing wrapIv")
        val saltRaw = firstNonBlank(optStringOrNull(w, "salt"))
            ?: error("License wrap missing salt")
        val wrappedRaw = firstNonBlank(
            optStringOrNull(j, "wrappedCek"),
            optStringOrNull(j, "wrapped_cek_b64")
        ) ?: error("License missing wrappedCek")
        val algo = firstNonBlank(optStringOrNull(j, "algo"), optStringOrNull(j, "algorithm"))
        val plainSha = firstNonBlank(optStringOrNull(j, "plainSha256"))
        val wrap = LicenseWrapDoc(
            type = w.optString("type", ""),
            wrapIv = decodeB64Any(wrapIvRaw),
            salt = decodeB64Any(saltRaw),
            shardUsed = w.optBoolean("shardUsed",
                w.optBoolean("shard_required", w.optBoolean("shardRequired", false))),
            aad = firstNonBlank(optStringOrNull(w, "aad"))
        )
        return LicenseDoc(
            version = if (j.has("version")) j.optInt("version") else null,
            modelId = modelId,
            algo = algo,
            plainSha256 = plainSha,
            wrappedCek = decodeB64Any(wrappedRaw),
            wrap = wrap,
            expiresAt = firstNonBlank(optStringOrNull(j, "expiresAt"))
        )
    }
}
