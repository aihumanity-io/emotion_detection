// lib/model_runtime.dart
import 'package:flutter/services.dart';

class ModelRuntime {
  static late MethodChannel _ch; // = MethodChannel('face_emotion_detection');
  //MethodChannel _ch;
  ModelRuntime(String methodChStr) {
    _ch = MethodChannel(methodChStr);
  }

  static Future<void> registerModel({
    required String modelId,
    required String resourceBase, // file stem, e.g. "face_v1"
    String encExt = 'onnx.enc', // use same on all platforms
    String hkdfInfo = 'model_runtime',
    String? masterKeyB64, // optional; prefer server shard
  }) =>
      _ch.invokeMethod('registerModel', {
        'modelId': modelId,
        'resourceBase': resourceBase,
        'encExt': encExt,
        'hkdfInfo': hkdfInfo,
        'masterKeyB64': masterKeyB64,
      });

  static Future<void> setKeyShard(
          {required String modelId,
          required String keyShardB64,
          int? expiresAtMs,
          String? userName}) =>
      _ch.invokeMethod('setKeyShard', {
        'modelId': modelId,
        'keyShardB64': keyShardB64,
        if (expiresAtMs != null) 'expiresAtMs': expiresAtMs,
        if (userName != null) 'userName': userName,
      });

  static Future<void> clearKeyShard(String modelId) =>
      _ch.invokeMethod('clearKeyShard', {'modelId': modelId});

  static Future<void> setModelLicense({
    required String modelId,
    required Map<String, dynamic> license,
  }) =>
      _ch.invokeMethod('setModelLicense', {
        'modelId': modelId,
        'license': license,
      });

  static Future<void> clearModelLicense(String modelId) =>
      _ch.invokeMethod('clearModelLicense', {'modelId': modelId});

  static Future<bool> warmUp(String modelId) async =>
      (await _ch.invokeMethod('warmUp', {'modelId': modelId})) == true;

  /// Inputs: numbers, Float32List (as {'f32': list, 'shape':[...]}), or BGRA image bytes {'bgra': bytes,'width':W,'height':H}
  static Future<Map<String, dynamic>> predict(
      String modelId, Map<String, dynamic> inputs) async {
    final out = await _ch
        .invokeMethod<Map>('predict', {'modelId': modelId, 'inputs': inputs});
    return Map<String, dynamic>.from(out ?? const {});
  }

  static Future<void> unload(String modelId) =>
      _ch.invokeMethod('unload', {'modelId': modelId});
}
