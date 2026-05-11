package com.tartalabs.emotiondetection.sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class EmotionNativeSdkTest {
    @Test
    fun lifecycleForwardsCallsInOrder() {
        val core = FakeCore()
        val sdk = EmotionNativeSdk(core)
        val model = modelConfig()
        val image = EmotionImage(width = 1, height = 1, rgbBytes = byteArrayOf(255.toByte(), 0, 0))

        sdk.initialize()
        sdk.registerModel(model)
        sdk.warmUp(model.modelId)
        val prediction = sdk.predict(model.modelId, image)
        sdk.unload(model.modelId)
        sdk.shutdown()

        assertEquals(4, prediction.topLabelIndex)
        assertEquals(
            listOf(
                "initialize",
                "register:aih_fer2025",
                "warmUp:aih_fer2025",
                "predict:aih_fer2025",
                "unload:aih_fer2025",
                "shutdown"
            ),
            core.events
        )
    }

    @Test
    fun predictRequiresRegisteredModel() {
        val sdk = EmotionNativeSdk(FakeCore())
        val image = EmotionImage(width = 1, height = 1, rgbBytes = byteArrayOf(0, 0, 0))

        assertEquals(
            EmotionSdkStatus.NOT_INITIALIZED,
            assertFailsWith<EmotionSdkException> {
                sdk.predict("missing", image)
            }.status
        )

        sdk.initialize()
        assertEquals(
            EmotionSdkStatus.MODEL_NOT_FOUND,
            assertFailsWith<EmotionSdkException> {
                sdk.predict("missing", image)
            }.status
        )
    }

    @Test
    fun failedRegisterDoesNotMarkModelRegistered() {
        val sdk = EmotionNativeSdk(FakeCore(registerStatus = EmotionSdkStatus.MANIFEST_INVALID))
        val model = modelConfig()

        sdk.initialize()
        assertEquals(
            EmotionSdkStatus.MANIFEST_INVALID,
            assertFailsWith<EmotionSdkException> {
                sdk.registerModel(model)
            }.status
        )
        assertEquals(
            EmotionSdkStatus.MODEL_NOT_FOUND,
            assertFailsWith<EmotionSdkException> {
                sdk.warmUp(model.modelId)
            }.status
        )
    }

    @Test
    fun imageValidatesRgbByteCount() {
        assertEquals(
            IllegalArgumentException::class,
            assertFailsWith<IllegalArgumentException> {
                EmotionImage(width = 2, height = 1, rgbBytes = byteArrayOf(1, 2, 3))
            }::class
        )
    }

    private fun modelConfig() = EmotionModelConfig(
        modelId = "aih_fer2025",
        manifestPath = "/models/manifest.json",
        encryptedModelPath = "/models/model.enc"
    )
}

private class FakeCore(
    private val registerStatus: EmotionSdkStatus = EmotionSdkStatus.OK
) : EmotionNativeCore {
    val events = mutableListOf<String>()

    override fun initialize(config: EmotionSdkConfig): EmotionSdkStatus {
        events += "initialize"
        return EmotionSdkStatus.OK
    }

    override fun registerModel(config: EmotionModelConfig): EmotionSdkStatus {
        events += "register:${config.modelId}"
        return registerStatus
    }

    override fun warmUp(modelId: String): EmotionSdkStatus {
        events += "warmUp:$modelId"
        return EmotionSdkStatus.OK
    }

    override fun predict(modelId: String, image: EmotionImage): Result<EmotionPrediction> {
        events += "predict:$modelId"
        return Result.success(
            EmotionPrediction(
                topLabelIndex = 4,
                topProbability = 0.9f,
                scores = listOf(EmotionClassScore(labelIndex = 4, probability = 0.9f))
            )
        )
    }

    override fun unload(modelId: String): EmotionSdkStatus {
        events += "unload:$modelId"
        return EmotionSdkStatus.OK
    }

    override fun shutdown(): EmotionSdkStatus {
        events += "shutdown"
        return EmotionSdkStatus.OK
    }
}
