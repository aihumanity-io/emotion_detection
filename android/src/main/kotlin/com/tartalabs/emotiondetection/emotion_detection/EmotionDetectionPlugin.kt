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
import android.util.Base64

val modelId = "mobilenetv1_2024-11-03-19-24-14"
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
      val userCodeB64 = call.argument<String>("userCodeB64")
      if (userCodeB64.isNullOrBlank()) {
        result.error("invalid_args", "userCodeB64 is required", null)
        return
      }
      try {
        val decoded = Base64.decode(userCodeB64.trim(), Base64.NO_WRAP)
        if (decoded.size != 32) {
          result.error("invalid_length", "userCode must be 32 bytes", null)
          return
        }
        licMgr.saveUserCode(decoded)
        result.success(null)
      } catch (e: IllegalArgumentException) {
        result.error("invalid_base64", "Failed to decode userCodeB64", e.localizedMessage)
      }
    } else if(call.method == "clearUserCode") {
      licMgr.clearSecrets()
      result.success(null)
    } else if(call.method == "setKeyShard") {
      val shardB64 = call.argument<String>("keyShardB64")
      if (shardB64.isNullOrBlank()) {
        result.error("invalid_args", "keyShardB64 is required", null)
        return
      }
      try {
        var decoded: ByteArray? = null
        val trimmed = shardB64.trim()
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
        licMgr.saveShard(decoded)
        result.success(null)
      } catch (e: IllegalArgumentException) {
        result.error("invalid_base64", "Failed to decode keyShardB64", e.localizedMessage)
      }
    } else if(call.method == "clearKeyShard") {
      store.remove(keys.shard)
      store.remove(keys.deviceWrappedCek)
      result.success(null)
    } else if (call.method == "registerModel") {
      val modelId = call.argument<String>("modelId") ?: run {
        result.error("invalid_args", "modelId is required", null); return
      }
      val resourceBase = call.argument<String>("resourceBase") ?: modelId
      val encExt = call.argument<String>("encExt") ?: "onnx.enc"
      specs[modelId] = ModelSpec(modelId = modelId, resourceBase = resourceBase, encExt = encExt)
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
      val modelId = call.argument<String>("modelId") ?: run {
        result.error("invalid_args", "modelId is required", null); return
      }
      val inputs = call.argument<Map<String, Any>>("inputs") ?: emptyMap()
      try {
        val predictor = ensureModel(modelId)
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
    val manifestJson = _appContext.assets.open(manifestName).bufferedReader().use { it.readText() }
    val dec = licMgr.openModel(manifestJson = manifestJson, verify = true)
    FileInputStream(dec).channel.use { ch ->
      val mapped = ch.map(FileChannel.MapMode.READ_ONLY, 0, ch.size())
      models[modelId] = mapped
      _emotionPredictor = EmotionMoblenet(_appContext, mapped)
    }
  }

  private fun ensureModel(modelId: String): EmotionMoblenet {
    loadModelIfNeeded(modelId)
    return requireNotNull(_emotionPredictor) { "Model $modelId not loaded" }
  }
}
