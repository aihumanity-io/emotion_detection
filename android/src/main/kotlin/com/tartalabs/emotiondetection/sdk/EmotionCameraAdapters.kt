package com.tartalabs.emotiondetection.sdk

data class EmotionFaceBox(
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
    val confidence: Float
)

data class EmotionCameraFrame(
    val image: EmotionImage,
    val timestampMs: Long
)

fun interface EmotionFaceDetector {
    fun detectFace(image: EmotionImage): EmotionFaceBox?
}

interface EmotionCameraFrameSource {
    fun start(onFrame: (EmotionCameraFrame) -> Unit)
    fun stop()
}

class EmotionCameraPredictionSession(
    private val sdk: EmotionNativeSdk,
    private val modelId: String,
    private val faceDetector: EmotionFaceDetector
) {
    fun predict(frame: EmotionCameraFrame): EmotionPrediction? {
        faceDetector.detectFace(frame.image) ?: return null
        return sdk.predict(modelId, frame.image)
    }
}
