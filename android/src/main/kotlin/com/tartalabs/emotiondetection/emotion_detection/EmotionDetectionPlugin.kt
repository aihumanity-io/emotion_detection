package com.tartalabs.emotiondetection.emotion_detection

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.content.res.AssetManager
import android.util.Log
import androidx.annotation.NonNull
import com.tartalabs.crypto.DeviceKek
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
import com.tartalabs.crypto.SecretStore
import com.tartalabs.crypto.ensureUserCode
import com.tartalabs.crypto.loadModelFile

val modelId = "mobilenetv1_2024-11-03-19-24-14"
/** EmotionDetectionPlugin */
class EmotionDetectionPlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  lateinit var _emotionPredictor: EmotionMoblenet
  lateinit var _emotionModel: MappedByteBuffer
  lateinit private var _appContext: Context
  var modelFileLength: Long = 0
  var TAG: String = "EmotionDetectionPlugin"
  lateinit var store: KeystorePrefsStore

  lateinit var keys: LicenseKeys

  lateinit var licMgr: LicenseManager


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

    //
    // later:
    val assets = _appContext.getAssets()

    // one way to decrypt
    // the current way
    Log.i("EmotionDetectionPlugin", "loading & decrypting model: " + modelId)
    _emotionModel = loadModelFile(_appContext, modelId, licMgr)
    modelFileLength = _emotionModel.capacity().toLong()
    Log.i("EmotionDetectionPlugin", "model: " + modelId + " loaded size: " + _emotionModel.capacity())
    _emotionPredictor = EmotionMoblenet(_appContext, _emotionModel)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "getPlatformVersion") {
      result.success("Android ${android.os.Build.VERSION.RELEASE}")
    } else if(call.method == "faceEmotion") {
      //Log.e("EmotionDetectionPlugin", " model length: "+modelFileLength)

      //val emotionResult = _predictor.handlePrediction(call, result)
      val emotionResult = _emotionPredictor.handlePrediction(call, result)

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
        val decoded = Base64.decode(shardB64.trim(), Base64.NO_WRAP)
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
    val b64 = _appContext.getString(
      com.tartalabs.emotiondetection.emotion_detection.R.string.emotion_bundled_code_b64
    ).trim()
    if (b64.isNotEmpty()) {
      val bytes = Base64.decode(b64, Base64.NO_WRAP)
      licMgr.saveUserCode(bytes)
    }
  }

  // This can be used to load regular models
  private fun loadPlainModelFile(filename: String): MappedByteBuffer {
    /*AssetManager assetManager = registar.context().getAssets();

    String key = registrar.lookupKeyForAsset("models/mobilenetv2636.tflite");

    AssetFileDescriptor assetFileDescriptor = assetManager.openFd(key);

     */

    /*AssetManager assetManager = registar.context().getAssets();

    String key = registrar.lookupKeyForAsset("models/mobilenetv2636.tflite");

    AssetFileDescriptor assetFileDescriptor = assetManager.openFd(key);

     */
    val MODEL_ASSETS_PATH = filename //"models/mobilenetv2636.tflite"
    val assetManager: AssetManager = _appContext.getAssets()
    if (assetManager == null) {
      Log.e(TAG, "Asset manager is null")
    }
    val assetFileDescriptor: AssetFileDescriptor = _appContext.getAssets().openFd(MODEL_ASSETS_PATH)
    val fileInputStream = FileInputStream(assetFileDescriptor.getFileDescriptor())
    val fileChannel: FileChannel = fileInputStream.getChannel()
    val startoffset: Long = assetFileDescriptor.getStartOffset()
    val declaredLength: Long = assetFileDescriptor.getDeclaredLength()
    Log.e(TAG, "file length: $declaredLength offset: $startoffset")
    modelFileLength = declaredLength
    return fileChannel.map(FileChannel.MapMode.READ_ONLY, startoffset, declaredLength)
  }
}
