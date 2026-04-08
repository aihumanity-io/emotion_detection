package com.tartalabs.crypto

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.security.MessageDigest
import java.text.SimpleDateFormat
import android.util.Base64
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

fun ensureUserCode(
    licMgr: LicenseManager,
    store: SecretStore,
    keys: LicenseKeys,
    userCode32: ByteArray
) {
    require(userCode32.size == 32) { "userCode32 must be 32 bytes" }
    val existing = store.get(keys.userCode)
    if (existing != null && MessageDigest.isEqual(existing, userCode32)) return
    licMgr.saveUserCode(userCode32)
    store.remove(keys.deviceWrappedCek)
}

private fun loadModelFileEncrypted(
    appContext: Context,
    modelId: String,
    licMgr: LicenseManager
): MappedByteBuffer {
    val assets = appContext.assets
    val manifestJson = assets.open("$modelId.manifest.json")
        .bufferedReader().use { it.readText() }
    val decryptedModelFile: File = licMgr.openModel(
        manifestJson = manifestJson,
        modelBase = modelId,
        verify = true
    )
    FileInputStream(decryptedModelFile).channel.use { ch ->
        return ch.map(FileChannel.MapMode.READ_ONLY, 0, ch.size())
    }
}

fun ensureActiveLicense(context: Context, modelId: String): File {
    val dstDir = File(context.filesDir, "licenses").apply { mkdirs() }
    val dst = File(dstDir, "$modelId.license.json")
    if (dst.exists()) return dst
    try {
        context.assets.open("licenses/$modelId.license.json").use { input ->
            val tmp = File.createTempFile("$modelId.", ".tmp", dstDir)
            tmp.outputStream().use { output -> input.copyTo(output) }
            if (!tmp.renameTo(dst)) throw IllegalStateException("rename failed")
        }
        return dst
    } catch (e: Exception) {
        throw IllegalStateException("No license found. Ask user to import a license.", e)
    }
}

fun loadModelFile(
    appContext: Context,
    modelBase: String,
    licMgr: LicenseManager?
): MappedByteBuffer {
    val assets = appContext.assets
    fun assetExists(name: String): Boolean = try {
        assets.open(name).close(); true
    } catch (_: Exception) {
        false
    }
    return if (assetExists("$modelBase.manifest.json")) {
        requireNotNull(licMgr) { "LicenseManager required for encrypted model" }
        loadModelFileEncrypted(appContext, modelBase, licMgr)
    } else {
        val afd = assets.openFd(modelBase)
        FileInputStream(afd.fileDescriptor).channel.use { ch ->
            ch.map(FileChannel.MapMode.READ_ONLY, afd.startOffset, afd.declaredLength)
        }
    }
}

class LicenseManager(
    private val appContext: Context,
    private val store: SecretStore,
    private val keys: LicenseKeys
) {
    private val deviceKek = DeviceKek(store, keys.deviceSeed)

    fun saveUserCode(userCode32: ByteArray, modelId: String? = null) {
        require(userCode32.size == 32) { "userCode32 must be 32 bytes" }
        store.put(scopedKey(keys.userCode, modelId), userCode32)
        removeCachedCek(modelId)
    }

    fun saveShard(shard: ByteArray, modelId: String? = null) {
        require(shard.isNotEmpty()) { "shard must be non-empty" }
        store.put(scopedKey(keys.shard, modelId), shard)
        removeCachedCek(modelId)
    }

    fun saveModelLicense(modelId: String, licenseJson: String) {
        val parsed = Parsers.licenseFromJson(licenseJson)
        val bytes = licenseJson.toByteArray(Charsets.UTF_8)
        val ids = linkedSetOf(modelId.trim(), parsed.modelId.trim()).filter { it.isNotBlank() }
        for (id in ids) {
            store.put(licenseKey(id), bytes)
            removeCachedCek(id)
        }
    }

    fun clearUserCode(modelId: String? = null) {
        if (modelId.isNullOrBlank()) {
            store.remove(keys.userCode)
            clearScopedKeys(keys.userCode)
            store.remove(keys.deviceWrappedCek)
            clearScopedKeys(keys.deviceWrappedCek)
            return
        }
        store.remove(scopedKey(keys.userCode, modelId))
        store.remove(scopedKey(keys.deviceWrappedCek, modelId))
    }

    fun clearShard(modelId: String? = null) {
        if (modelId.isNullOrBlank()) {
            store.remove(keys.shard)
            clearScopedKeys(keys.shard)
            store.remove(keys.deviceWrappedCek)
            clearScopedKeys(keys.deviceWrappedCek)
            return
        }
        store.remove(scopedKey(keys.shard, modelId))
        store.remove(scopedKey(keys.deviceWrappedCek, modelId))
    }

    fun clearModelLicense(modelId: String) {
        val requestedId = modelId.trim()
        if (requestedId.isBlank()) return
        val ids = linkedSetOf(requestedId)
        val stored = store.get(licenseKey(requestedId))
        if (stored != null) {
            try {
                val parsed = Parsers.licenseFromJson(stored.toString(Charsets.UTF_8))
                if (parsed.modelId.isNotBlank()) ids.add(parsed.modelId.trim())
            } catch (_: Exception) {
                // ignore malformed cached license while clearing
            }
        }
        for (id in ids) {
            store.remove(licenseKey(id))
            removeCachedCek(id)
        }
    }

    fun clearSecrets(modelId: String? = null) {
        if (modelId.isNullOrBlank()) {
            store.remove(keys.userCode)
            clearScopedKeys(keys.userCode)
            store.remove(keys.shard)
            clearScopedKeys(keys.shard)
            store.remove(keys.deviceWrappedCek)
            clearScopedKeys(keys.deviceWrappedCek)
            clearScopedKeys(LICENSE_PREFIX)
            return
        }
        store.remove(scopedKey(keys.userCode, modelId))
        store.remove(scopedKey(keys.shard, modelId))
        store.remove(scopedKey(keys.deviceWrappedCek, modelId))
        store.remove(licenseKey(modelId))
    }

    fun openModel(
        manifestJson: String,
        modelBase: String,
        verify: Boolean = true
    ): File {
        val man = Parsers.manifestFrom(manifestJson)
        val effectiveModelId = if (man.modelId.isBlank()) modelBase else man.modelId
        val modelCandidates = linkedSetOf(modelBase, effectiveModelId)
            .map { it.trim() }.filter { it.isNotBlank() }
        val aadBytes = man.aad.takeIf { it.isNotBlank() }?.toByteArray()
        val distMode = Parsers.detectDistributionMode(man)
        Log.i(
            TAG,
            "openModel modelBase=$modelBase modelId=$effectiveModelId mode=$distMode " +
                "shardRequired=${man.wrap.shardRequired} wrapType='${man.wrap.type}'"
        )

        val cachedKey = scopedKey(keys.deviceWrappedCek, effectiveModelId)
        val cached = store.get(cachedKey)
        val cekFromCache = cached?.let { buf ->
            if (buf.size <= 12) return@let null
            val devKek = deviceKek.derive(effectiveModelId)
            try {
                val iv = buf.copyOfRange(0, 12)
                val ctTag = buf.copyOfRange(12, buf.size)
                Gcm.decryptCekWrap(devKek, iv, ctTag)
            } catch (e: Exception) {
                Log.w(TAG, "cached CEK unwrap failed: ${e.message}")
                null
            }
        }

        val cek = cekFromCache ?: run {
            val userCode = loadFirstScoped(keys.userCode, modelCandidates)
                ?: error("Missing userCode32 for model candidates: $modelCandidates")
            val shard = loadFirstScoped(keys.shard, modelCandidates)

            val derived = when (distMode) {
                DistributionMode.UNIFIED -> unwrapFromLicense(
                    manifest = man,
                    candidates = modelCandidates,
                    userCode = userCode,
                    shard = shard
                )
                DistributionMode.PER_DEVELOPER -> {
                    val fromManifest = try {
                        unwrapFromManifest(man, userCode, shard)
                    } catch (e: Exception) {
                        Log.w(TAG, "manifest unwrap failed, trying license fallback: ${e.message}")
                        null
                    }
                    fromManifest ?: unwrapFromLicense(
                        manifest = man,
                        candidates = modelCandidates,
                        userCode = userCode,
                        shard = shard
                    )
                }
            }

            val devKek = deviceKek.derive(effectiveModelId)
            val iv = ByteArray(12).also { java.security.SecureRandom().nextBytes(it) }
            val ctTag = Cipher.getInstance("AES/GCM/NoPadding").run {
                init(Cipher.ENCRYPT_MODE, SecretKeySpec(devKek, "AES"), GCMParameterSpec(128, iv))
                doFinal(derived)
            }
            store.put(cachedKey, iv + ctTag)
            derived
        }

        val tmp = File.createTempFile(sanitizeModelId(effectiveModelId), ".bin", appContext.cacheDir)
        openAssetFirst("${modelBase}.enc", "${effectiveModelId}.enc").use { enc ->
            tmp.outputStream().use { out ->
                if (man.gcmIv != null) {
                    Gcm.decryptModelTo(cek, man.gcmIv, enc, out, aad = aadBytes)
                } else {
                    Gcm.decryptModelCombinedTo(cek, enc, out, aad = aadBytes)
                }
            }
        }
        Log.i(TAG, "decrypt ok modelId=$effectiveModelId out=${tmp.absolutePath}")

        if (verify) {
            val expectedB64 = man.plainSha256B64Url
            if (!expectedB64.isNullOrBlank()) {
                val sha = sha256OfFile(tmp)
                val expected = B64Url.dec(expectedB64)
                if (!sha.contentEquals(expected)) {
                    Log.e(TAG, "Integrity check failed modelId=$effectiveModelId")
                }
                require(sha.contentEquals(expected)) { "Integrity check failed: SHA-256 mismatch" }
            } else {
                Log.w(TAG, "Skipping integrity check; plainSha256 missing in manifest")
            }
        }
        return tmp
    }

    private fun unwrapFromManifest(
        man: ModelManifest,
        userCode: ByteArray,
        shard: ByteArray?
    ): ByteArray? {
        val wrapped = man.wrappedCek ?: return null
        val wrapIv = man.wrap.iv ?: return null
        val wrapSalt = man.wrap.salt ?: return null
        val typeRequiresShard = man.wrap.type.contains("+shard+", ignoreCase = true)
        val shardRequired = man.wrap.shardRequired || typeRequiresShard
        if (shardRequired && shard == null) error("Manifest requires shard, but none stored")

        val info = (man.kdfInfo?.takeIf { it.isNotBlank() } ?: "model:${man.modelId}")
            .toByteArray()
        val aadCandidates = legacyAadCandidates(man.aad, shard)
        val keyInputs = mutableListOf<ByteArray>()
        if (shardRequired) {
            keyInputs.add(userCode + (shard ?: ByteArray(0)))
        } else {
            keyInputs.add(userCode)
            if (shard != null) keyInputs.add(userCode + shard)
        }

        var lastErr: Exception? = null
        for (ikm in keyInputs) {
            val kekBytes = HKDF.sha256(ikm, wrapSalt, info, 32)
            for (aad in aadCandidates) {
                try {
                    return Gcm.decryptCekWrap(kekBytes, wrapIv, wrapped, aad)
                } catch (e: Exception) {
                    lastErr = e
                }
            }
        }
        throw lastErr ?: IllegalStateException("Failed to unwrap CEK from manifest")
    }

    private fun unwrapFromLicense(
        manifest: ModelManifest,
        candidates: List<String>,
        userCode: ByteArray,
        shard: ByteArray?
    ): ByteArray {
        val license = loadLicense(candidates)
        if (!manifest.plainSha256B64Url.isNullOrBlank() &&
            !license.plainSha256.isNullOrBlank() &&
            manifest.plainSha256B64Url != license.plainSha256) {
            error("License plainSha256 mismatch for model ${license.modelId}")
        }
        if (!manifest.algo.isNullOrBlank() &&
            !license.algo.isNullOrBlank() &&
            !manifest.algo.equals(license.algo, ignoreCase = true)) {
            error("License algo mismatch for model ${license.modelId}")
        }
        val expiry = license.expiresAt?.takeIf { it.isNotBlank() }?.let { raw ->
            parseExpiryEpochMillis(raw) ?: error("Invalid license expiresAt format: $raw")
        }
        if (expiry != null && System.currentTimeMillis() >= expiry) {
            error("License expired for model ${license.modelId}")
        }
        if (license.wrap.shardUsed && shard == null) {
            error("License wrap requires shard for model ${license.modelId}")
        }

        val ikm = if (license.wrap.shardUsed) userCode + (shard ?: ByteArray(0)) else userCode
        val info = "model:${license.modelId}".toByteArray()
        val kekBytes = HKDF.sha256(ikm, license.wrap.salt, info, 32)
        val aad = license.wrap.aad?.takeIf { it.isNotBlank() }?.toByteArray()
        return Gcm.decryptCekWrap(
            kekBytes = kekBytes,
            wrapIv = license.wrap.wrapIv,
            wrappedCtTag = license.wrappedCek,
            aad = aad
        )
    }

    private fun loadLicense(candidates: List<String>): LicenseDoc {
        val tried = linkedSetOf<String>()

        for (candidate in candidates) {
            val stored = store.get(licenseKey(candidate))
            if (stored != null) {
                try {
                    val json = stored.toString(Charsets.UTF_8)
                    return Parsers.licenseFromJson(json)
                } catch (e: Exception) {
                    Log.w(TAG, "stored license parse failed for $candidate: ${e.message}")
                }
            }
        }

        for (candidate in candidates) {
            val names = listOf(
                "licenses/$candidate.android.license.json",
                "licenses/$candidate.license.json",
                "licenses/$candidate.json",
                "$candidate.android.license.json",
                "$candidate.license.json",
                "$candidate.json"
            )
            for (name in names) {
                if (!tried.add(name)) continue
                try {
                    val json = appContext.assets.open(name).bufferedReader().use { it.readText() }
                    return Parsers.licenseFromJson(json)
                } catch (_: Exception) {
                    // ignore
                }
            }
        }
        error("Missing license for model candidates: $candidates")
    }

    private fun legacyAadCandidates(manifestAad: String, shard: ByteArray?): List<ByteArray> {
        val out = mutableListOf<ByteArray>()
        val seen = linkedSetOf<String>()
        fun add(value: String) {
            if (value.isEmpty()) return
            if (!seen.add(value)) return
            out.add(value.toByteArray())
        }

        add(manifestAad)
        if (shard == null || shard.isEmpty()) return out

        val stdNoPad = Base64.encodeToString(shard, Base64.NO_WRAP)
        val stdPad = ensurePadding(stdNoPad)
        val urlNoPad = Base64.encodeToString(shard, Base64.URL_SAFE or Base64.NO_WRAP)
        val urlPad = ensurePadding(urlNoPad)

        add("$manifestAad|shard:$stdNoPad")
        add("$manifestAad|shard:$stdPad")
        add("$manifestAad|shard:$urlNoPad")
        add("$manifestAad|shard:$urlPad")

        return out
    }

    private fun ensurePadding(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return trimmed
        val missing = (4 - (trimmed.length % 4)) % 4
        if (missing == 0) return trimmed
        return trimmed + "=".repeat(missing)
    }

    private fun loadFirstScoped(base: String, candidates: List<String>): ByteArray? {
        for (id in candidates) {
            store.get(scopedKey(base, id))?.let { return it }
        }
        return store.get(base)
    }

    private fun openAssetFirst(vararg names: String): InputStream {
        var lastErr: Exception? = null
        for (name in names) {
            try {
                return appContext.assets.open(name)
            } catch (e: Exception) {
                lastErr = e
            }
        }
        throw lastErr ?: IllegalStateException("No asset found from candidates: ${names.toList()}")
    }

    private fun removeCachedCek(modelId: String?) {
        if (modelId.isNullOrBlank()) {
            store.remove(keys.deviceWrappedCek)
            clearScopedKeys(keys.deviceWrappedCek)
        } else {
            store.remove(scopedKey(keys.deviceWrappedCek, modelId))
        }
    }

    private fun clearScopedKeys(base: String) {
        (store as? PrefixRemovableSecretStore)?.removeByPrefix("$base.")
    }

    private fun parseExpiryEpochMillis(raw: String): Long? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null

        trimmed.toLongOrNull()?.let { value ->
            return if (value > 1_000_000_000_000L) value else value * 1000L
        }

        val patterns = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSSX",
            "yyyy-MM-dd'T'HH:mm:ssX",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'"
        )
        for (pattern in patterns) {
            try {
                val fmt = SimpleDateFormat(pattern, Locale.US).apply {
                    isLenient = false
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                val date = fmt.parse(trimmed)
                if (date != null) return date.time
            } catch (_: Exception) {
                // try next parser
            }
        }
        return null
    }

    private fun licenseKey(modelId: String): String = scopedKey(LICENSE_PREFIX, modelId)

    private fun scopedKey(base: String, modelId: String?): String {
        if (modelId.isNullOrBlank()) return base
        return "$base.${sanitizeModelId(modelId)}"
    }

    private fun sanitizeModelId(value: String): String =
        value.trim().lowercase().replace(Regex("[^a-z0-9._-]"), "_")

    private fun sha256OfFile(f: File): ByteArray {
        FileInputStream(f).use { fis ->
            val ch = fis.channel
            val map = ch.map(FileChannel.MapMode.READ_ONLY, 0L, ch.size())
            val all = ByteArray(map.remaining())
            map.get(all)
            return Hash.sha256(all)
        }
    }

    private operator fun ByteArray.plus(other: ByteArray): ByteArray =
        ByteArray(this.size + other.size).also {
            System.arraycopy(this, 0, it, 0, this.size)
            System.arraycopy(other, 0, it, this.size, other.size)
        }

    companion object {
        private const val TAG = "LicenseManager"
        private const val LICENSE_PREFIX = "emotion.lic.license.v1"
    }
}
