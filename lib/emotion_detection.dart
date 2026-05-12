import 'emotion_detection_platform_interface.dart';
import 'utility/emotion_provisioner.dart';
export 'emotion_detector_view.dart';
export 'native/user_code_channel.dart';
export 'native/model_runtime.dart';
export 'utility/sdk_secret_client.dart';
export 'utility/cek_secret_utils.dart';
export 'utility/emotion_provisioner.dart';
export 'utility/web_hosted_inference_client.dart';

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

  Stream<Map<String, double>> macCameraStream({String? modelId}) {
    return EmotionDetectionPlatform.instance.macCameraStream(modelId: modelId);
  }

  Future<void> macShowCameraPreview({String? modelId}) {
    return EmotionDetectionPlatform.instance
        .macShowCameraPreview(modelId: modelId);
  }

  Future<void> macHideCameraPreview() {
    return EmotionDetectionPlatform.instance.macHideCameraPreview();
  }
}
