package com.tartalabs.emotiondetection.sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EmotionFlutterBridgePayloadsTest {
    @Test
    fun registerModelPayloadUsesDefaults() {
        val payload = EmotionRegisterModelPayload.from(
            mapOf(
                "modelId" to "aih_fer2025"
            )
        )

        assertEquals("aih_fer2025", payload.modelId)
        assertEquals("aih_fer2025", payload.resourceBase)
        assertEquals("onnx.enc", payload.encryptedExtension)
        assertEquals("model_runtime", payload.hkdfInfo)
        assertNull(payload.masterKeyBase64)
    }

    @Test
    fun registerModelPayloadReadsOptionalFields() {
        val payload = EmotionRegisterModelPayload.from(
            mapOf(
                "modelId" to "aih_fer2025",
                "resourceBase" to "face_v1",
                "encExt" to "bin.enc",
                "hkdfInfo" to "custom",
                "masterKeyB64" to "abc"
            )
        )

        assertEquals("face_v1", payload.resourceBase)
        assertEquals("bin.enc", payload.encryptedExtension)
        assertEquals("custom", payload.hkdfInfo)
        assertEquals("abc", payload.masterKeyBase64)
    }

    @Test
    fun predictPayloadRequiresInputsMap() {
        val payload = EmotionPredictPayload.from(
            mapOf(
                "modelId" to "aih_fer2025",
                "inputs" to mapOf("width" to 1, "height" to 1)
            )
        )

        assertEquals("aih_fer2025", payload.modelId)
        assertEquals(1, payload.inputs["width"])
        assertFailsWith<EmotionFlutterBridgeException> {
            EmotionPredictPayload.from(mapOf("modelId" to "aih_fer2025"))
        }
    }

    @Test
    fun userCodePayloadValidatesRequiredFields() {
        val payload = EmotionUserCodePayload.from(
            mapOf(
                "userName" to "david",
                "userCodeB64" to "abc",
                "requireBiometrics" to true,
                "modelId" to "aih_fer2025"
            )
        )

        assertEquals("david", payload.userName)
        assertEquals("abc", payload.userCodeBase64)
        assertEquals("aih_fer2025", payload.modelId)
        assertTrue(payload.requireBiometrics)
        assertFailsWith<EmotionFlutterBridgeException> {
            EmotionUserCodePayload.from(mapOf("userName" to "david"))
        }
    }
}
