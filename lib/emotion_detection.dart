import 'package:flutter/services.dart';
import 'emotion_detection_platform_interface.dart';
import 'utility/emotion_provisioner.dart';
export 'emotion_detector_view.dart';
export 'native/user_code_channel.dart';
export 'native/model_runtime.dart';
export 'utility/sdk_secret_client.dart';
export 'utility/cek_secret_utils.dart';
export 'utility/emotion_provisioner.dart';

class EmotionDetection {
  Future<String?> getPlatformVersion() {
    return EmotionDetectionPlatform.instance.getPlatformVersion();
  }

  static Future<EmotionProvisioningResult> initializeWithDeveloperCredentials({
    required String sdkKeyId,
    required String sdkKeySecret,
    required String userName,
    List<String>? modelKeys,
    String? modelKey,
    String? iosAad,
    String? aad,
    String? macosAad,
    String? androidAad,
    String? serverBaseUrl,
    bool clearExistingSecrets = false,
    bool warmUp = true,
  }) {
    return EmotionDetectionProvisioner(
      sdkKeyId: sdkKeyId,
      sdkKeySecret: sdkKeySecret,
      userName: userName,
      modelKeys: modelKeys,
      modelKey: modelKey,
      iosAad: iosAad,
      aad: aad,
      macosAad: macosAad,
      androidAad: androidAad,
      serverBaseUrl: serverBaseUrl,
    ).provision(
      clearExistingSecrets: clearExistingSecrets,
      warmUp: warmUp,
    );
  }

  // macOS camera prediction stream
  // Usage: EmotionDetection().macCameraStream(modelId: 'aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx')
  static const _cameraStream = EventChannel('face_emotion_detection/camera');
  static const _runtimeCh = MethodChannel('face_emotion_detection');

  Stream<Map<String, double>> macCameraStream({String? modelId}) {
    final args = <String, dynamic>{};
    if (modelId != null) args['modelId'] = modelId;
    return _cameraStream
        .receiveBroadcastStream(args)
        .map((event) => Map<String, double>.from(event as Map));
  }

  Future<void> macShowCameraPreview({String? modelId}) {
    return _runtimeCh.invokeMethod('showMacCameraPreview', {
      if (modelId != null) 'modelId': modelId,
    });
  }

  Future<void> macHideCameraPreview() {
    return _runtimeCh.invokeMethod('hideMacCameraPreview');
  }
}
