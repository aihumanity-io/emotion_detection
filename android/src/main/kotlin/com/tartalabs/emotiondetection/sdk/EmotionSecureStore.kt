package com.tartalabs.emotiondetection.sdk

import com.tartalabs.crypto.SecretStore

interface EmotionSecureStore {
    fun set(namespace: String, key: String, value: ByteArray): EmotionSdkStatus
    fun get(namespace: String, key: String): Result<ByteArray>
    fun delete(namespace: String, key: String): EmotionSdkStatus
}

class AndroidKeystoreSecureStore(
    private val store: SecretStore
) : EmotionSecureStore {
    override fun set(namespace: String, key: String, value: ByteArray): EmotionSdkStatus {
        if (!valid(namespace, key) || value.isEmpty()) {
            return EmotionSdkStatus.INVALID_ARGUMENT
        }
        store.put(storageKey(namespace, key), value)
        return EmotionSdkStatus.OK
    }

    override fun get(namespace: String, key: String): Result<ByteArray> {
        if (!valid(namespace, key)) {
            return Result.failure(EmotionSdkException(EmotionSdkStatus.INVALID_ARGUMENT))
        }
        return store.get(storageKey(namespace, key))?.let { value ->
            Result.success(value)
        } ?: Result.failure(EmotionSdkException(EmotionSdkStatus.MODEL_NOT_FOUND))
    }

    override fun delete(namespace: String, key: String): EmotionSdkStatus {
        if (!valid(namespace, key)) {
            return EmotionSdkStatus.INVALID_ARGUMENT
        }
        store.remove(storageKey(namespace, key))
        return EmotionSdkStatus.OK
    }

    private fun valid(namespace: String, key: String): Boolean =
        namespace.isNotBlank() && key.isNotBlank()

    private fun storageKey(namespace: String, key: String): String = "$namespace:$key"
}
