import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'emotion_detection_method_channel.dart';

abstract class EmotionDetectionPlatform extends PlatformInterface {
  /// Constructs a EmotionDetectionPlatform.
  EmotionDetectionPlatform() : super(token: _token);

  static final Object _token = Object();

  static EmotionDetectionPlatform _instance = MethodChannelEmotionDetection();

  /// The default instance of [EmotionDetectionPlatform] to use.
  ///
  /// Defaults to [MethodChannelEmotionDetection].
  static EmotionDetectionPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [EmotionDetectionPlatform] when
  /// they register themselves.
  static set instance(EmotionDetectionPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    return instance.getPlatformVersion();
    //throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Stream<Map<String, double>> macCameraStream({String? modelId}) {
    return instance.macCameraStream(modelId: modelId);
  }

  Future<void> macShowCameraPreview({String? modelId}) {
    return instance.macShowCameraPreview(modelId: modelId);
  }

  Future<void> macHideCameraPreview() {
    return instance.macHideCameraPreview();
  }

  Future<void> saveUserCode({
    required String userName,
    required String userCodeB64,
    bool requireBiometrics = false,
    String? modelId,
  }) {
    return instance.saveUserCode(
      userName: userName,
      userCodeB64: userCodeB64,
      requireBiometrics: requireBiometrics,
      modelId: modelId,
    );
  }

  Future<void> clearUserCode(String userName, {String? modelId}) {
    return instance.clearUserCode(userName, modelId: modelId);
  }

  void configureModelRuntimeChannel(String methodChannelName) {
    return instance.configureModelRuntimeChannel(methodChannelName);
  }

  Future<void> registerModel({
    required String modelId,
    required String resourceBase,
    String encExt = 'onnx.enc',
    String hkdfInfo = 'model_runtime',
    String? masterKeyB64,
  }) {
    return instance.registerModel(
      modelId: modelId,
      resourceBase: resourceBase,
      encExt: encExt,
      hkdfInfo: hkdfInfo,
      masterKeyB64: masterKeyB64,
    );
  }

  Future<void> setKeyShard({
    required String modelId,
    required String keyShardB64,
    int? expiresAtMs,
    String? userName,
  }) {
    return instance.setKeyShard(
      modelId: modelId,
      keyShardB64: keyShardB64,
      expiresAtMs: expiresAtMs,
      userName: userName,
    );
  }

  Future<void> clearKeyShard(String modelId) {
    return instance.clearKeyShard(modelId);
  }

  Future<void> setModelLicense({
    required String modelId,
    required Map<String, dynamic> license,
  }) {
    return instance.setModelLicense(modelId: modelId, license: license);
  }

  Future<void> clearModelLicense(String modelId) {
    return instance.clearModelLicense(modelId);
  }

  Future<bool> warmUp(String modelId) {
    return instance.warmUp(modelId);
  }

  Future<Map<String, dynamic>> predict(
    String modelId,
    Map<String, dynamic> inputs,
  ) {
    return instance.predict(modelId, inputs);
  }

  Future<void> unload(String modelId) {
    return instance.unload(modelId);
  }
}
