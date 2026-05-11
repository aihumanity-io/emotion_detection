package com.tartalabs.emotiondetection.emotion_detection

import android.content.Context
import android.util.Log
import androidx.annotation.NonNull
import com.tartalabs.crypto.KeystorePrefsStore
import com.tartalabs.crypto.LicenseKeys

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.FileInputStream
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import com.tartalabs.crypto.LicenseManager
import com.tartalabs.emotiondetection.sdk.EmotionFlutterBridgeException
import com.tartalabs.emotiondetection.sdk.EmotionPredictPayload
import com.tartalabs.emotiondetection.sdk.EmotionRegisterModelPayload
import com.tartalabs.emotiondetection.sdk.EmotionUserCodePayload
import android.util.Base64
import org.json.JSONObject

val modelId = "mobilenetv1_fer2024-11-06-08-48-50"
/** EmotionDetectionPlugin */
class EmotionDetectionPlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private var _emotionPredictor: EmotionMoblenet? = null
  lateinit private var _appContext: Context
  var TAG: String = "EmotionDetectionPlugin"
  lateinit var store: KeystorePrefsStore

  lateinit var keys: LicenseKeys

  lateinit var licMgr: LicenseManager

  data class ModelSpec(val modelId: String, val resourceBase: String, val encExt: String = "onnx.enc")
  private val models: MutableMap<String, MappedByteBuffer> = mutableMapOf()
  private val specs: MutableMap<String, ModelSpec> = mutableMapOf()


  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    _appContext = flutterPluginBinding.applicationContext
    store = KeystorePrefsStore(_appContext,
      alias = "emotion_detection_example.lic.aes",               // optional: customize keystore alias
      prefsName = "emotion_detection_example.lic.prefs"          // optional: customize prefs name
    )

    keys = LicenseKeys(
      userCode         = "emotion.lic.userCode.v1",
      shard            = "emotion.lic.shard.v1",
      deviceWrappedCek = "emotion.lic.cek.devicewrap.v1", // IV||ct+tag cache
      deviceSeed       = "emotion.device.seed.v1"
    )
    /*keys = LicenseKeys(
      userCode         = userCode32,
      shard            = "",
      deviceWrappedCek = wrappedCek,
      deviceSeed       = "emotion_detection_example.device.seed.v1"
    )*/

    licMgr = LicenseManager(
      appContext = _appContext,
      store = store,
      keys = keys
    )

    /*val parsed = Base64.decode(userCode32.trim(), Base64.NO_WRAP)
    ensureUserCode(licMgr, store, keys, parsed)*/
    provisionUserCodeIfNeeded(licMgr)

    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "face_emotion_detection")
    channel.setMethodCallHandler(this)
    Log.i("EmotionDetectionPlugin", "plugin attached; models will load on demand")
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "getPlatformVersion") {
      result.success("Android ${android.os.Build.VERSION.RELEASE}")
    } else if(call.method == "faceEmotion") {
      try {
        ensureModel(modelId)
      } catch (e: Exception) {
        Log.e(TAG, "model_load_error: ${e.message}", e)
        result.error("model_load_error", e.message, e.localizedMessage)
        return
      }
      //Log.e("EmotionDetectionPlugin", " model length: "+modelFileLength)

      //val emotionResult = _predictor.handlePrediction(call, result)
      val emotionResult = _emotionPredictor?.handlePrediction(call, result) ?: emptyMap<String, Double>()

      //result.error("UNAVAILABLE", "Eye gaze not available.", null)

      if (emotionResult.size != 0) {
        result.success(emotionResult)
      } else {
        result.error("UNAVAILABLE", "emotion not available.", null)
      }

    } else if(call.method == "setUserCode") {
      val payload = try {
        EmotionUserCodePayload.from(call.arguments)
      } catch (e: EmotionFlutterBridgeException) {
        result.error("invalid_args", e.message, null)
        return
      }
      try {
        val decoded = Base64.decode(payload.userCodeBase64.trim(), Base64.NO_WRAP)
        if (decoded.size != 32) {
          result.error("invalid_length", "userCode must be 32 bytes", null)
          return
        }
        licMgr.saveUserCode(decoded, payload.modelId)
        result.success(null)
      } catch (e: IllegalArgumentException) {
        result.error("invalid_base64", "Failed to decode userCodeB64", e.localizedMessage)
      }
    } else if(call.method == "clearUserCode") {
      val modelIdArg = call.argument<String>("modelId")
      licMgr.clearUserCode(modelIdArg)
      result.success(null)
    } else if(call.method == "setKeyShard") {
      val shardB64 = call.argument<String>("keyShardB64")
      val modelIdArg = call.argument<String>("modelId")
      if (shardB64.isNullOrBlank()) {
        result.error("invalid_args", "keyShardB64 is required", null)
        return
      }
      try {
        var decoded: ByteArray? = null
        val trimmed: String = shardB64.trim()
        try {
          decoded = Base64.decode(trimmed, Base64.NO_WRAP)
        } catch (_: IllegalArgumentException) {
          decoded = null
        }
        if (decoded == null) {
          // Try URL-safe variant
          decoded = try {
            Base64.decode(trimmed, Base64.URL_SAFE or Base64.NO_WRAP)
          } catch (_: IllegalArgumentException) {
            null
          }
        }
        if (decoded == null) {
          result.error("invalid_base64", "Failed to decode keyShardB64", null)
          return
        }
        if (decoded.isEmpty()) {
          result.error("invalid_length", "shard must be non-empty", null)
          return
        }
        licMgr.saveShard(decoded, modelIdArg)
        result.success(null)
      } catch (e: IllegalArgumentException) {
        result.error("invalid_base64", "Failed to decode keyShardB64", e.localizedMessage)
      }
    } else if(call.method == "clearKeyShard") {
      val modelIdArg = call.argument<String>("modelId")
      licMgr.clearShard(modelIdArg)
      result.success(null)
    } else if (call.method == "setModelLicense") {
      val modelIdArg = call.argument<String>("modelId")
      if (modelIdArg.isNullOrBlank()) {
        result.error("invalid_args", "modelId is required", null)
        return
      }
      val licenseJson = call.argument<String>("licenseJson")
      @Suppress("UNCHECKED_CAST")
      val licenseMap = call.argument<HashMap<String, Any?>>("license")
      val payload: String = when {
        !licenseJson.isNullOrBlank() -> licenseJson
        licenseMap != null -> JSONObject(licenseMap as Map<*, *>).toString()
        else -> ""
      }
      if (payload.isBlank()) {
        result.error("invalid_args", "license or licenseJson is required", null)
        return
      }
      try {
        licMgr.saveModelLicense(modelIdArg, payload)
        result.success(null)
      } catch (e: Exception) {
        result.error("license_error", e.message, e.localizedMessage)
      }
    } else if (call.method == "clearModelLicense") {
      val modelIdArg = call.argument<String>("modelId")
      if (modelIdArg.isNullOrBlank()) {
        result.error("invalid_args", "modelId is required", null)
        return
      }
      licMgr.clearModelLicense(modelIdArg)
      result.success(null)
    } else if (call.method == "registerModel") {
      val payload = try {
        EmotionRegisterModelPayload.from(call.arguments)
      } catch (e: EmotionFlutterBridgeException) {
        result.error("invalid_args", e.message, null)
        return
      }
      specs[payload.modelId] = ModelSpec(
        modelId = payload.modelId,
        resourceBase = payload.resourceBase,
        encExt = payload.encryptedExtension
      )
      result.success(null)
    } else if (call.method == "warmUp") {
      val modelId = call.argument<String>("modelId") ?: run {
        result.error("invalid_args", "modelId is required", null); return
      }
      try {
        loadModelIfNeeded(modelId)
        result.success(true)
      } catch (e: Exception) {
        Log.e(TAG, "warmUp failed: ${e.message}", e)
        result.error("model_load_error", e.message, e.localizedMessage)
      }
    } else if (call.method == "predict") {
      val payload = try {
        EmotionPredictPayload.from(call.arguments)
      } catch (e: EmotionFlutterBridgeException) {
        result.error("invalid_args", e.message, null)
        return
      }
      try {
        val predictor = ensureModel(payload.modelId)
        val emotionResult = predictor.handlePrediction(call, result)
        if (emotionResult.isNotEmpty()) {
          result.success(emotionResult)
        } else {
          result.error("UNAVAILABLE", "emotion not available.", null)
        }
      } catch (e: Exception) {
        Log.e(TAG, "predict failed: ${e.message}", e)
        result.error("model_inference_error", e.message, e.localizedMessage)
      }
    } else if (call.method == "unload") {
      val modelId = call.argument<String>("modelId") ?: run {
        result.error("invalid_args", "modelId is required", null); return
      }
      models.remove(modelId)
      result.success(null)
    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  private fun provisionUserCodeIfNeeded(
    licMgr: LicenseManager
  ) {
    try {
      val b64 = _appContext.getString(
        com.tartalabs.emotiondetection.emotion_detection.R.string.emotion_bundled_code_b64
      ).trim()
      if (b64.isNotEmpty()) {
        val bytes = Base64.decode(b64, Base64.NO_WRAP)
        licMgr.saveUserCode(bytes)
      }
    } catch (_: Exception) {
      // Optional bundled code not present; ignore.
    }
  }

  private fun loadModelIfNeeded(modelId: String) {
    if (models.containsKey(modelId)) return
    val spec = specs[modelId] ?: ModelSpec(modelId = modelId, resourceBase = modelId, encExt = "onnx.enc")
    val modelBase = spec.resourceBase
    val manifestName = "$modelBase.manifest.json"
    Log.i(TAG, "loading manifest: $manifestName for modelId=$modelId")
    try {
      val manifestJson = _appContext.assets.open(manifestName).bufferedReader().use { it.readText() }
      val dec = licMgr.openModel(manifestJson = manifestJson, modelBase = modelBase, verify = true)
      FileInputStream(dec).channel.use { ch ->
        val mapped = ch.map(FileChannel.MapMode.READ_ONLY, 0, ch.size())
        models[modelId] = mapped
        _emotionPredictor = EmotionMoblenet(_appContext, mapped)
        Log.i(TAG, "model loaded and mapped: $modelId size=${ch.size()}")
      }
    } catch (e: Exception) {
      Log.e(TAG, "loadModelIfNeeded failed for $modelId: ${e.message}", e)
      throw e
    }
  }

  private fun ensureModel(modelId: String): EmotionMoblenet {
    loadModelIfNeeded(modelId)
    return requireNotNull(_emotionPredictor) { "Model $modelId not loaded" }
  }
}
