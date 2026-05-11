import '../emotion_detection_platform_interface.dart';

class UserCodeChannel {
  const UserCodeChannel._();

  static Future<void> saveUserCode({
    required String userName,
    required String userCodeB64,
    bool requireBiometrics = false,
    String? modelId,
  }) async {
    await EmotionDetectionPlatform.instance.saveUserCode(
      userName: userName,
      userCodeB64: userCodeB64,
      requireBiometrics: requireBiometrics,
      modelId: modelId,
    );
  }

  static Future<void> clearUserCode(String userName, {String? modelId}) async {
    await EmotionDetectionPlatform.instance.clearUserCode(
      userName,
      modelId: modelId,
    );
  }
}
