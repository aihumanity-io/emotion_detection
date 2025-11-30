package com.tartalabs.crypto

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

import java.security.MessageDigest

fun ensureUserCode(licMgr: LicenseManager, store: SecretStore, keys: LicenseKeys, userCode32: ByteArray) {
    require(userCode32.size == 32) { "userCode32 must be 32 bytes" }
    val existing = store.get(keys.userCode)
    if (existing != null && MessageDigest.isEqual(existing, userCode32)) {
        // Same value already stored -> no-op
        return
    }
    // Code is new or missing: save it and invalidate cached CEK
    licMgr.saveUserCode(userCode32)
    store.remove(keys.deviceWrappedCek) // force re-unwrap & rewrap on next open
}

// Returns a MappedByteBuffer of the *decrypted* model.
// Param `modelId` is the base name you used when packaging, e.g. "mobilenetv1_2024-11-03-19-24-14".
private fun loadModelFileEncrypted(appContext: Context, modelId: String, licMgr: LicenseManager): MappedByteBuffer {
    val assets = appContext.assets

    // 1) Read manifest from assets (shared for everyone)
    val manifestJson = assets.open("$modelId.manifest.json")
        .bufferedReader().use { it.readText() }
    // 2) Read per-user license from app-private storage
    //val licFile = File(appContext.filesDir, "licenses/$modelId.license.json")

    //require(licFile.exists()) { "Missing license for $modelId. Ask user to import it." }
    //val licenseJson = licFile.readText()

    // 3) Decrypt model.enc (from assets) to a temp file (LicenseManager already streams/decrypts)
    val decryptedModelFile: File = licMgr.openModel(
        manifestJson = manifestJson,
        verify = true
    )

    // 4) Memory-map the decrypted file
    FileInputStream(decryptedModelFile).channel.use { ch ->
        return ch.map(FileChannel.MapMode.READ_ONLY, 0, ch.size())
    }
}
//
// helper to load from file storage then assets for the license file
//
fun ensureActiveLicense(context: Context, modelId: String): File {
    val dstDir = File(context.filesDir, "licenses").apply { mkdirs() }
    val dst = File(dstDir, "$modelId.license.json")
    if (dst.exists()) return dst

    // Fallback to bundled asset on first run (if you included one)
    try {
        context.assets.open("licenses/$modelId.license.json").use { input ->
            // atomic write: write to tmp then rename
            val tmp = File.createTempFile("$modelId.", ".tmp", dstDir)
            tmp.outputStream().use { output -> input.copyTo(output) }
            if (!tmp.renameTo(dst)) throw IllegalStateException("rename failed")
        }
        return dst
    } catch (e: Exception) {
        throw IllegalStateException("No license found. Ask user to import a license.", e)
    }
}


fun loadModelFile(appContext: Context, modelBase: String, licMgr: LicenseManager?): MappedByteBuffer {
    val assets = appContext.assets

    fun assetExists(name: String): Boolean = try {
        assets.open(name).close(); true
    } catch (_: Exception) { false }

    return if (assetExists("$modelBase.manifest.json")) {
        // Encrypted bundle: requires LicenseManager
        requireNotNull(licMgr) { "LicenseManager required for encrypted model" }
        loadModelFileEncrypted(appContext, modelBase, licMgr)
    } else {
        // Legacy raw .tflite in assets (your original approach)
        val afd = assets.openFd(modelBase) // e.g., "models/mobilenetv2636.tflite"
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

    // app supplies bytes; we just store under provided key names
    fun saveUserCode(userCode32: ByteArray) {
        require(userCode32.size == 32) { "userCode32 must be 32 bytes" }
        store.put(keys.userCode, userCode32)
        store.remove(keys.deviceWrappedCek) // force re-unwrap on next open
    }
    fun saveShard(shard: ByteArray) {
        store.put(keys.shard, shard)
        store.remove(keys.deviceWrappedCek)
    }
    fun clearSecrets() {
        store.remove(keys.userCode); store.remove(keys.shard); store.remove(keys.deviceWrappedCek)
    }

    fun openModel(manifestJson: String, verify: Boolean = true): File {
        val man = Parsers.manifestFrom(manifestJson)
        val aadBytes = if (man.aad.isNotEmpty()) man.aad.toByteArray() else null
        Log.i(
            "LicenseManager",
            "openModel modelId=${man.modelId} shardRequired=${man.wrap.shardRequired} " +
                    "aad='${man.aad}' wrap.iv.len=${man.wrap.iv.size} wrap.salt.len=${man.wrap.salt.size}"
        )

        // 1) try cached CEK (device-KEK rewrap)
        val cached = store.get(keys.deviceWrappedCek)
        val cek: ByteArray = (cached?.let { buf ->
            val devKek = deviceKek.derive(man.modelId)
            try {
                val iv = buf.copyOfRange(0, 12)
                val ctTag = buf.copyOfRange(12, buf.size)
                Gcm.decryptCekWrap(devKek, iv, ctTag)
            } catch (e: Exception) { Log.w("LicenseManager", "cached CEK unwrap failed: ${e.message}"); null }
        }) ?: run {
            // 2) derive KEK from userCode (+shard) and unwrap CEK from license
            val userCode = store.get(keys.userCode) ?: error("Missing userCode32")
            val shard = store.get(keys.shard)
            Log.i(
                "LicenseManager",
                "unwrap with userCode.len=${userCode.size} shard.len=${shard?.size ?: 0} " +
                        "shardRequired=${man.wrap.shardRequired} userHash=${Hash.sha256(userCode).toHexPrefix()} shardHash=${shard?.let { Hash.sha256(it).toHexPrefix() }}"
            )
            if (man.wrap.shardRequired && shard == null) {
                error("Manifest expects shard, but none stored")
            }
            val ikm = if (shard != null) userCode + shard else userCode
            val info = man.aad.toByteArray()
            val kekBytes = HKDF.sha256(ikm, man.wrap.salt, info, 32)
            try {
                Log.i(
                    "LicenseManager",
                    "unwrap input modelId=${man.modelId} kekHash=${Hash.sha256(kekBytes).toHexPrefix()} info='${man.aad}' saltHash=${Hash.sha256(man.wrap.salt).toHexPrefix()} ivHash=${Hash.sha256(man.wrap.iv).toHexPrefix()}"
                )
                val cekBytes = Gcm.decryptCekWrap(kekBytes, man.wrap.iv, man.wrappedCek, aadBytes)
                Log.i(
                    "LicenseManager",
                    "unwrap success modelId=${man.modelId} shardPresent=${shard != null} cek.len=${cekBytes.size} " +
                            "kekHash=${Hash.sha256(kekBytes).toHexPrefix()} info='${man.aad}'"
                )
                // 3) rewrap CEK with device KEK and cache as IV||ct+tag
                val devKek = deviceKek.derive(man.modelId)
                val iv = ByteArray(12).also { java.security.SecureRandom().nextBytes(it) }
                val ctTag = Cipher.getInstance("AES/GCM/NoPadding").run {
                    init(Cipher.ENCRYPT_MODE, SecretKeySpec(devKek, "AES"), GCMParameterSpec(128, iv))
                    doFinal(cekBytes)
                }
                store.put(keys.deviceWrappedCek, iv + ctTag)
                cekBytes
            } catch (e: Exception) {
                Log.e("LicenseManager", "unwrap failed modelId=${man.modelId}: ${e.message}")
                throw e
            }

        }

        // 4) decrypt model.enc from assets → temp file
        val tmp = File.createTempFile(man.modelId, ".bin", appContext.cacheDir)
        appContext.assets.open("${man.modelId}.enc").use { enc ->
            tmp.outputStream().use { out ->
                Gcm.decryptModelTo(cek, man.gcmIv, enc, out, aad = aadBytes)
            }
        }
        Log.i("LicenseManager", "decrypt ok modelId=${man.modelId} out=${tmp.absolutePath}")

        // 5) verify integrity (optional)
        if (verify) {
            val sha = sha256OfFile(tmp)
            val expected = B64Url.dec(man.plainSha256B64Url)
            if (!sha.contentEquals(expected)) {
                Log.e("LicenseManager", "Integrity check failed modelId=${man.modelId}")
            }
            require(sha.contentEquals(expected)) { "Integrity check failed: SHA-256 mismatch" }
        }
        return tmp
    }

    private fun sha256OfFile(f: File): ByteArray {
        FileInputStream(f).use { fis ->
            val ch = fis.channel
            val map = ch.map(FileChannel.MapMode.READ_ONLY, 0L, ch.size())
            val all = ByteArray(map.remaining()); map.get(all)
            return Hash.sha256(all)
        }
    }

    private operator fun ByteArray.plus(other: ByteArray): ByteArray =
        ByteArray(this.size + other.size).also {
            System.arraycopy(this, 0, it, 0, this.size)
            System.arraycopy(other, 0, it, this.size, other.size)
        }
}
