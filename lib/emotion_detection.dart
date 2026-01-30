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
}
