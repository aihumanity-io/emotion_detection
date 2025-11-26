import 'package:flutter/services.dart';

class UserCodeChannel {
  const UserCodeChannel._();

  static const MethodChannel _channel = MethodChannel('face_emotion_detection');

  static Future<void> saveUserCode({
    required String userName,
    required String userCodeB64,
    bool requireBiometrics = false,
    String? modelId,
  }) async {
    await _channel.invokeMethod<void>('setUserCode', <String, dynamic>{
      'userName': userName,
      'userCodeB64': userCodeB64,
      'requireBiometrics': requireBiometrics,
      if (modelId != null) 'modelId': modelId,
    });
  }

  static Future<void> clearUserCode(String userName, {String? modelId}) async {
    await _channel.invokeMethod<void>('clearUserCode', <String, dynamic>{
      'userName': userName,
      if (modelId != null) 'modelId': modelId,
    });
  }
}
