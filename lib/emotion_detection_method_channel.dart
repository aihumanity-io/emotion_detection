import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'emotion_detection_platform_interface.dart';

/// An implementation of [EmotionDetectionPlatform] that uses method channels.
class MethodChannelEmotionDetection extends EmotionDetectionPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('face_emotion_detection');

  @visibleForTesting
  final cameraEventChannel =
      const EventChannel('face_emotion_detection/camera');

  @visibleForTesting
  MethodChannel modelRuntimeMethodChannel =
      const MethodChannel('face_emotion_detection');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Stream<Map<String, double>> macCameraStream({
    String? modelId,
    bool debugFaceCrop = false,
  }) {
    return cameraEventChannel.receiveBroadcastStream(<String, dynamic>{
      if (modelId != null) 'modelId': modelId,
      if (debugFaceCrop) 'debugFaceCrop': true,
    }).map((event) => Map<String, double>.from(event as Map));
  }

  @override
  Future<void> macShowCameraPreview({
    String? modelId,
    bool debugFaceCrop = false,
  }) {
    return methodChannel.invokeMethod<void>('showMacCameraPreview', {
      if (modelId != null) 'modelId': modelId,
      if (debugFaceCrop) 'debugFaceCrop': true,
    });
  }

  @override
  Future<void> macHideCameraPreview() {
    return methodChannel.invokeMethod<void>('hideMacCameraPreview');
  }

  @override
  Future<void> saveUserCode({
    required String userName,
    required String userCodeB64,
    bool requireBiometrics = false,
    String? modelId,
  }) {
    return methodChannel.invokeMethod<void>('setUserCode', <String, dynamic>{
      'userName': userName,
      'userCodeB64': userCodeB64,
      'requireBiometrics': requireBiometrics,
      if (modelId != null) 'modelId': modelId,
    });
  }

  @override
  Future<void> clearUserCode(String userName, {String? modelId}) {
    return methodChannel.invokeMethod<void>('clearUserCode', <String, dynamic>{
      'userName': userName,
      if (modelId != null) 'modelId': modelId,
    });
  }

  @override
  void configureModelRuntimeChannel(String methodChannelName) {
    modelRuntimeMethodChannel = MethodChannel(methodChannelName);
  }

  @override
  Future<void> registerModel({
    required String modelId,
    required String resourceBase,
    String encExt = 'onnx.enc',
    String hkdfInfo = 'model_runtime',
    String? masterKeyB64,
  }) {
    return modelRuntimeMethodChannel.invokeMethod<void>('registerModel', {
      'modelId': modelId,
      'resourceBase': resourceBase,
      'encExt': encExt,
      'hkdfInfo': hkdfInfo,
      'masterKeyB64': masterKeyB64,
    });
  }

  @override
  Future<void> setKeyShard({
    required String modelId,
    required String keyShardB64,
    int? expiresAtMs,
    String? userName,
  }) {
    return modelRuntimeMethodChannel.invokeMethod<void>('setKeyShard', {
      'modelId': modelId,
      'keyShardB64': keyShardB64,
      if (expiresAtMs != null) 'expiresAtMs': expiresAtMs,
      if (userName != null) 'userName': userName,
    });
  }

  @override
  Future<void> clearKeyShard(String modelId) {
    return modelRuntimeMethodChannel.invokeMethod<void>(
      'clearKeyShard',
      {'modelId': modelId},
    );
  }

  @override
  Future<void> setModelLicense({
    required String modelId,
    required Map<String, dynamic> license,
  }) {
    return modelRuntimeMethodChannel.invokeMethod<void>('setModelLicense', {
      'modelId': modelId,
      'license': license,
    });
  }

  @override
  Future<void> clearModelLicense(String modelId) {
    return modelRuntimeMethodChannel.invokeMethod<void>(
      'clearModelLicense',
      {'modelId': modelId},
    );
  }

  @override
  Future<bool> warmUp(String modelId) async {
    return await modelRuntimeMethodChannel.invokeMethod<bool>(
          'warmUp',
          {'modelId': modelId},
        ) ==
        true;
  }

  @override
  Future<Map<String, dynamic>> predict(
    String modelId,
    Map<String, dynamic> inputs,
  ) async {
    final out = await modelRuntimeMethodChannel.invokeMethod<Map>(
      'predict',
      {'modelId': modelId, 'inputs': inputs},
    );
    return Map<String, dynamic>.from(out ?? const {});
  }

  @override
  Future<void> unload(String modelId) {
    return modelRuntimeMethodChannel.invokeMethod<void>(
      'unload',
      {'modelId': modelId},
    );
  }

  @override
  Future<Map?> faceEmotion(Map<String, dynamic> inputs) {
    return methodChannel.invokeMethod<Map>('faceEmotion', inputs);
  }
}
