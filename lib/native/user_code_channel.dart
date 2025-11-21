import 'package:flutter/services.dart';

class UserCodeChannel {
  const UserCodeChannel._();

  static const MethodChannel _channel = MethodChannel('face_emotion_detection');

  static Future<void> saveUserCode({
    required String userName,
    required String userCodeB64,
    bool requireBiometrics = false,
  }) async {
    await _channel.invokeMethod<void>('setUserCode', <String, dynamic>{
      'userName': userName,
      'userCodeB64': userCodeB64,
      'requireBiometrics': requireBiometrics,
    });
  }

  static Future<void> clearUserCode(String userName) async {
    await _channel.invokeMethod<void>('clearUserCode', <String, dynamic>{
      'userName': userName,
    });
  }
}
