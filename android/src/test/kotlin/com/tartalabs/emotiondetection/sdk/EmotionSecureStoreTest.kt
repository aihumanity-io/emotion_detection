package com.tartalabs.emotiondetection.sdk

import com.tartalabs.crypto.SecretStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class EmotionSecureStoreTest {
    @Test
    fun setGetUpdateAndDelete() {
        val store = AndroidKeystoreSecureStore(FakeSecretStore())

        assertEquals(EmotionSdkStatus.OK, store.set("models", "user32", byteArrayOf(1, 2, 3)))
        assertTrue(store.get("models", "user32").getOrThrow().contentEquals(byteArrayOf(1, 2, 3)))

        assertEquals(EmotionSdkStatus.OK, store.set("models", "user32", byteArrayOf(4, 5)))
        assertTrue(store.get("models", "user32").getOrThrow().contentEquals(byteArrayOf(4, 5)))

        assertEquals(EmotionSdkStatus.OK, store.delete("models", "user32"))
        assertEquals(
            EmotionSdkStatus.MODEL_NOT_FOUND,
            assertFailsWith<EmotionSdkException> {
                store.get("models", "user32").getOrThrow()
            }.status
        )
    }

    @Test
    fun namespacesAreIsolated() {
        val store = AndroidKeystoreSecureStore(FakeSecretStore())

        assertEquals(EmotionSdkStatus.OK, store.set("a", "shared", byteArrayOf(1)))
        assertEquals(EmotionSdkStatus.OK, store.set("b", "shared", byteArrayOf(2)))

        assertTrue(store.get("a", "shared").getOrThrow().contentEquals(byteArrayOf(1)))
        assertTrue(store.get("b", "shared").getOrThrow().contentEquals(byteArrayOf(2)))
    }

    @Test
    fun invalidInputsFailClosed() {
        val store = AndroidKeystoreSecureStore(FakeSecretStore())

        assertEquals(EmotionSdkStatus.INVALID_ARGUMENT, store.set("", "key", byteArrayOf(1)))
        assertEquals(EmotionSdkStatus.INVALID_ARGUMENT, store.set("namespace", "", byteArrayOf(1)))
        assertEquals(EmotionSdkStatus.INVALID_ARGUMENT, store.set("namespace", "key", byteArrayOf()))
        assertEquals(EmotionSdkStatus.INVALID_ARGUMENT, store.delete("", "key"))
        assertEquals(
            EmotionSdkStatus.INVALID_ARGUMENT,
            assertFailsWith<EmotionSdkException> {
                store.get("", "key").getOrThrow()
            }.status
        )
    }
}

private class FakeSecretStore : SecretStore {
    private val values = mutableMapOf<String, ByteArray>()

    override fun put(key: String, value: ByteArray) {
        values[key] = value.copyOf()
    }

    override fun get(key: String): ByteArray? = values[key]?.copyOf()

    override fun remove(key: String) {
        values.remove(key)
    }
}
