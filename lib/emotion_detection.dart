import 'emotion_detection_platform_interface.dart';
export 'emotion_detector_view.dart';
export 'native/user_code_channel.dart';
export 'utility/sdk_secret_client.dart';

class EmotionDetection {
  Future<String?> getPlatformVersion() {
    return EmotionDetectionPlatform.instance.getPlatformVersion();
  }
}
