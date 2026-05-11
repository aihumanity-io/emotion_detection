import '../emotion_detection_platform_interface.dart';

class ModelRuntime {
  ModelRuntime(String methodChStr) {
    EmotionDetectionPlatform.instance.configureModelRuntimeChannel(methodChStr);
  }

  static Future<void> registerModel({
    required String modelId,
    required String resourceBase, // file stem, e.g. "face_v1"
    String encExt = 'onnx.enc', // use same on all platforms
    String hkdfInfo = 'model_runtime',
    String? masterKeyB64, // optional; prefer server shard
  }) =>
      EmotionDetectionPlatform.instance.registerModel(
        modelId: modelId,
        resourceBase: resourceBase,
        encExt: encExt,
        hkdfInfo: hkdfInfo,
        masterKeyB64: masterKeyB64,
      );

  static Future<void> setKeyShard({
    required String modelId,
    required String keyShardB64,
    int? expiresAtMs,
    String? userName,
  }) =>
      EmotionDetectionPlatform.instance.setKeyShard(
        modelId: modelId,
        keyShardB64: keyShardB64,
        expiresAtMs: expiresAtMs,
        userName: userName,
      );

  static Future<void> clearKeyShard(String modelId) =>
      EmotionDetectionPlatform.instance.clearKeyShard(modelId);

  static Future<void> setModelLicense({
    required String modelId,
    required Map<String, dynamic> license,
  }) =>
      EmotionDetectionPlatform.instance.setModelLicense(
        modelId: modelId,
        license: license,
      );

  static Future<void> clearModelLicense(String modelId) =>
      EmotionDetectionPlatform.instance.clearModelLicense(modelId);

  static Future<bool> warmUp(String modelId) async =>
      EmotionDetectionPlatform.instance.warmUp(modelId);

  /// Inputs: numbers, Float32List (as {'f32': list, 'shape':[...]}), or BGRA image bytes {'bgra': bytes,'width':W,'height':H}
  static Future<Map<String, dynamic>> predict(
          String modelId, Map<String, dynamic> inputs) =>
      EmotionDetectionPlatform.instance.predict(modelId, inputs);

  static Future<void> unload(String modelId) =>
      EmotionDetectionPlatform.instance.unload(modelId);
}
