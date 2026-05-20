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
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  Stream<Map<String, double>> macCameraStream({
    String? modelId,
    bool debugFaceCrop = false,
  }) {
    throw UnimplementedError('macCameraStream() has not been implemented.');
  }

  Future<void> macShowCameraPreview({
    String? modelId,
    bool debugFaceCrop = false,
  }) {
    throw UnimplementedError(
      'macShowCameraPreview() has not been implemented.',
    );
  }

  Future<void> macHideCameraPreview() {
    throw UnimplementedError(
      'macHideCameraPreview() has not been implemented.',
    );
  }

  Future<void> saveUserCode({
    required String userName,
    required String userCodeB64,
    bool requireBiometrics = false,
    String? modelId,
  }) {
    throw UnimplementedError(
      'saveUserCode() has not been implemented.',
    );
  }

  Future<void> clearUserCode(String userName, {String? modelId}) {
    throw UnimplementedError(
      'clearUserCode() has not been implemented.',
    );
  }

  void configureModelRuntimeChannel(String methodChannelName) {
    throw UnimplementedError(
      'configureModelRuntimeChannel() has not been implemented.',
    );
  }

  Future<void> registerModel({
    required String modelId,
    required String resourceBase,
    String encExt = 'onnx.enc',
    String hkdfInfo = 'model_runtime',
    String? masterKeyB64,
  }) {
    throw UnimplementedError(
      'registerModel() has not been implemented.',
    );
  }

  Future<void> setKeyShard({
    required String modelId,
    required String keyShardB64,
    int? expiresAtMs,
    String? userName,
  }) {
    throw UnimplementedError(
      'setKeyShard() has not been implemented.',
    );
  }

  Future<void> clearKeyShard(String modelId) {
    throw UnimplementedError(
      'clearKeyShard() has not been implemented.',
    );
  }

  Future<void> setModelLicense({
    required String modelId,
    required Map<String, dynamic> license,
  }) {
    throw UnimplementedError(
      'setModelLicense() has not been implemented.',
    );
  }

  Future<void> clearModelLicense(String modelId) {
    throw UnimplementedError(
      'clearModelLicense() has not been implemented.',
    );
  }

  Future<bool> warmUp(String modelId) {
    throw UnimplementedError('warmUp() has not been implemented.');
  }

  Future<Map<String, dynamic>> predict(
    String modelId,
    Map<String, dynamic> inputs,
  ) {
    throw UnimplementedError('predict() has not been implemented.');
  }

  Future<void> unload(String modelId) {
    throw UnimplementedError('unload() has not been implemented.');
  }

  Future<Map?> faceEmotion(Map<String, dynamic> inputs) {
    throw UnimplementedError('faceEmotion() has not been implemented.');
  }
}
