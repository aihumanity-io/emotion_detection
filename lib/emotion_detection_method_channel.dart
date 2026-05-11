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

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Stream<Map<String, double>> macCameraStream({String? modelId}) {
    return cameraEventChannel.receiveBroadcastStream(<String, dynamic>{
      if (modelId != null) 'modelId': modelId,
    }).map((event) => Map<String, double>.from(event as Map));
  }

  @override
  Future<void> macShowCameraPreview({String? modelId}) {
    return methodChannel.invokeMethod<void>('showMacCameraPreview', {
      if (modelId != null) 'modelId': modelId,
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
}
