package com.tartalabs.emotiondetection.sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class EmotionCameraAdaptersTest {
    @Test
    fun cameraPredictionSkipsFramesWithoutFace() {
        val core = CameraCore()
        val sdk = EmotionNativeSdk(core)
        val detector = RecordingFaceDetector(face = null)
        val session = EmotionCameraPredictionSession(sdk, "aih_fer2025", detector)

        prepare(sdk)
        val prediction = session.predict(frame())

        assertNull(prediction)
        assertEquals(1, detector.detectedImages.size)
        assertEquals(0, core.predictCount)
    }

    @Test
    fun cameraPredictionUsesSdkWhenFaceIsDetected() {
        val core = CameraCore()
        val sdk = EmotionNativeSdk(core)
        val detector = RecordingFaceDetector(
            face = EmotionFaceBox(x = 0.1f, y = 0.2f, width = 0.3f, height = 0.4f, confidence = 0.95f)
        )
        val session = EmotionCameraPredictionSession(sdk, "aih_fer2025", detector)

        prepare(sdk)
        val prediction = session.predict(frame())

        assertEquals(4, prediction?.topLabelIndex)
        assertEquals(1, core.predictCount)
        assertEquals(detector.detectedImages.first(), core.lastImage)
    }

    @Test
    fun fakeFrameSourceSmoke() {
        val source = FakeFrameSource(frames = listOf(frame(), frame(timestampMs = 2)))
        val timestamps = mutableListOf<Long>()

        source.start { timestamps += it.timestampMs }
        source.stop()

        assertEquals(listOf(1L, 2L), timestamps)
        assertEquals(true, source.didStop)
    }

    private fun prepare(sdk: EmotionNativeSdk) {
        val model = EmotionModelConfig(
            modelId = "aih_fer2025",
            manifestPath = "/models/manifest.json",
            encryptedModelPath = "/models/model.enc"
        )
        sdk.initialize()
        sdk.registerModel(model)
        sdk.warmUp(model.modelId)
    }

    private fun frame(timestampMs: Long = 1L) = EmotionCameraFrame(
        image = EmotionImage(width = 1, height = 1, rgbBytes = byteArrayOf(255.toByte(), 0, 0)),
        timestampMs = timestampMs
    )
}

private class RecordingFaceDetector(
    private val face: EmotionFaceBox?
) : EmotionFaceDetector {
    val detectedImages = mutableListOf<EmotionImage>()

    override fun detectFace(image: EmotionImage): EmotionFaceBox? {
        detectedImages += image
        return face
    }
}

private class CameraCore : EmotionNativeCore {
    var predictCount = 0
    var lastImage: EmotionImage? = null

    override fun initialize(config: EmotionSdkConfig): EmotionSdkStatus = EmotionSdkStatus.OK

    override fun registerModel(config: EmotionModelConfig): EmotionSdkStatus = EmotionSdkStatus.OK

    override fun warmUp(modelId: String): EmotionSdkStatus = EmotionSdkStatus.OK

    override fun predict(modelId: String, image: EmotionImage): Result<EmotionPrediction> {
        predictCount += 1
        lastImage = image
        return Result.success(
            EmotionPrediction(
                topLabelIndex = 4,
                topProbability = 0.9f,
                scores = listOf(EmotionClassScore(labelIndex = 4, probability = 0.9f))
            )
        )
    }

    override fun unload(modelId: String): EmotionSdkStatus = EmotionSdkStatus.OK

    override fun shutdown(): EmotionSdkStatus = EmotionSdkStatus.OK
}

private class FakeFrameSource(
    private val frames: List<EmotionCameraFrame>
) : EmotionCameraFrameSource {
    var didStop = false

    override fun start(onFrame: (EmotionCameraFrame) -> Unit) {
        frames.forEach(onFrame)
    }

    override fun stop() {
        didStop = true
    }
}
