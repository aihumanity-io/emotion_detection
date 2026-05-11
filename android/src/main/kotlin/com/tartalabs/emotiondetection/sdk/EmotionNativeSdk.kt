package com.tartalabs.emotiondetection.sdk

enum class EmotionSdkStatus {
    OK,
    INVALID_ARGUMENT,
    NOT_INITIALIZED,
    MODEL_NOT_FOUND,
    MANIFEST_INVALID,
    CRYPTO_FAILED,
    LICENSE_INVALID,
    RUNTIME_FAILED,
    BUFFER_TOO_SMALL,
    UNSUPPORTED,
    INTERNAL
}

class EmotionSdkException(val status: EmotionSdkStatus) : RuntimeException(status.name)

data class EmotionSdkConfig(
    val cacheDir: String? = null,
    val enableDebugLogging: Boolean = false
)

data class EmotionModelConfig(
    val modelId: String,
    val manifestPath: String,
    val encryptedModelPath: String
)

data class EmotionImage(
    val width: Int,
    val height: Int,
    val rgbBytes: ByteArray
) {
    init {
        require(width > 0 && height > 0) { "image dimensions must be positive" }
        require(rgbBytes.size == width * height * 3) { "rgbBytes must be width * height * 3" }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is EmotionImage) return false
        return width == other.width &&
            height == other.height &&
            rgbBytes.contentEquals(other.rgbBytes)
    }

    override fun hashCode(): Int {
        var result = width
        result = 31 * result + height
        result = 31 * result + rgbBytes.contentHashCode()
        return result
    }
}

data class EmotionClassScore(
    val labelIndex: Int,
    val probability: Float
)

data class EmotionPrediction(
    val topLabelIndex: Int,
    val topProbability: Float,
    val scores: List<EmotionClassScore>
)

interface EmotionNativeCore {
    fun initialize(config: EmotionSdkConfig): EmotionSdkStatus
    fun registerModel(config: EmotionModelConfig): EmotionSdkStatus
    fun warmUp(modelId: String): EmotionSdkStatus
    fun predict(modelId: String, image: EmotionImage): Result<EmotionPrediction>
    fun unload(modelId: String): EmotionSdkStatus
    fun shutdown(): EmotionSdkStatus
}

class EmotionNativeSdk(private val core: EmotionNativeCore) {
    private var initialized = false
    private val registeredModelIds = linkedSetOf<String>()

    fun initialize(config: EmotionSdkConfig = EmotionSdkConfig()) {
        core.initialize(config).throwIfNeeded()
        initialized = true
    }

    fun registerModel(config: EmotionModelConfig) {
        requireInitialized()
        if (config.modelId.isBlank() ||
            config.manifestPath.isBlank() ||
            config.encryptedModelPath.isBlank()
        ) {
            throw EmotionSdkException(EmotionSdkStatus.INVALID_ARGUMENT)
        }
        core.registerModel(config).throwIfNeeded()
        registeredModelIds += config.modelId
    }

    fun warmUp(modelId: String) {
        requireRegistered(modelId)
        core.warmUp(modelId).throwIfNeeded()
    }

    fun predict(modelId: String, image: EmotionImage): EmotionPrediction {
        requireRegistered(modelId)
        return core.predict(modelId, image).getOrThrow()
    }

    fun unload(modelId: String) {
        requireRegistered(modelId)
        core.unload(modelId).throwIfNeeded()
        registeredModelIds -= modelId
    }

    fun shutdown() {
        core.shutdown().throwIfNeeded()
        registeredModelIds.clear()
        initialized = false
    }

    private fun requireInitialized() {
        if (!initialized) {
            throw EmotionSdkException(EmotionSdkStatus.NOT_INITIALIZED)
        }
    }

    private fun requireRegistered(modelId: String) {
        requireInitialized()
        if (modelId !in registeredModelIds) {
            throw EmotionSdkException(EmotionSdkStatus.MODEL_NOT_FOUND)
        }
    }

    private fun EmotionSdkStatus.throwIfNeeded() {
        if (this != EmotionSdkStatus.OK) {
            throw EmotionSdkException(this)
        }
    }
}
