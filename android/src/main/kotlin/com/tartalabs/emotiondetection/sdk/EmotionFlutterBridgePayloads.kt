package com.tartalabs.emotiondetection.sdk

class EmotionFlutterBridgeException(message: String) : IllegalArgumentException(message)

data class EmotionRegisterModelPayload(
    val modelId: String,
    val resourceBase: String,
    val encryptedExtension: String = "onnx.enc",
    val hkdfInfo: String = "model_runtime",
    val masterKeyBase64: String? = null
) {
    companion object {
        fun from(arguments: Any?): EmotionRegisterModelPayload {
            val map = arguments.asMap()
            val modelId = map.requiredString("modelId")
            return EmotionRegisterModelPayload(
                modelId = modelId,
                resourceBase = map.stringOrNull("resourceBase") ?: modelId,
                encryptedExtension = map.stringOrNull("encExt") ?: "onnx.enc",
                hkdfInfo = map.stringOrNull("hkdfInfo") ?: "model_runtime",
                masterKeyBase64 = map.stringOrNull("masterKeyB64")
            )
        }
    }
}

data class EmotionPredictPayload(
    val modelId: String,
    val inputs: Map<String, Any?>
) {
    companion object {
        fun from(arguments: Any?): EmotionPredictPayload {
            val map = arguments.asMap()
            return EmotionPredictPayload(
                modelId = map.requiredString("modelId"),
                inputs = map.requiredMap("inputs")
            )
        }
    }
}

data class EmotionUserCodePayload(
    val userName: String?,
    val userCodeBase64: String,
    val modelId: String?,
    val requireBiometrics: Boolean = false
) {
    companion object {
        fun from(arguments: Any?): EmotionUserCodePayload {
            val map = arguments.asMap()
            return EmotionUserCodePayload(
                userName = map.stringOrNull("userName"),
                userCodeBase64 = map.requiredString("userCodeB64"),
                modelId = map.stringOrNull("modelId"),
                requireBiometrics = map["requireBiometrics"] as? Boolean ?: false
            )
        }
    }
}

private fun Any?.asMap(): Map<String, Any?> {
    @Suppress("UNCHECKED_CAST")
    return this as? Map<String, Any?> ?: throw EmotionFlutterBridgeException("arguments must be a map")
}

private fun Map<String, Any?>.requiredString(key: String): String {
    val value = this[key] as? String
    if (value.isNullOrBlank()) {
        throw EmotionFlutterBridgeException("$key is required")
    }
    return value
}

private fun Map<String, Any?>.stringOrNull(key: String): String? =
    (this[key] as? String)?.takeIf { it.isNotBlank() }

private fun Map<String, Any?>.requiredMap(key: String): Map<String, Any?> {
    @Suppress("UNCHECKED_CAST")
    return this[key] as? Map<String, Any?>
        ?: throw EmotionFlutterBridgeException("$key is required")
}
