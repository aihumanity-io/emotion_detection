import 'package:flutter/services.dart';
import 'emotion_detection_platform_interface.dart';
export 'emotion_detector_view.dart';
export 'native/user_code_channel.dart';
export 'native/model_runtime.dart';
export 'utility/sdk_secret_client.dart';
export 'utility/cek_secret_utils.dart';

class EmotionDetection {
  Future<String?> getPlatformVersion() {
    return EmotionDetectionPlatform.instance.getPlatformVersion();
  }

  // macOS camera prediction stream
  // Usage: EmotionDetection().macCameraStream(modelId: 'mobilenetv1_fer2024-11-06-08-48-50')
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
