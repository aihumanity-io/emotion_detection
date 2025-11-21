import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'emotion_detection_platform_interface.dart';

/// An implementation of [EmotionDetectionPlatform] that uses method channels.
class MethodChannelEmotionDetection extends EmotionDetectionPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('face_emotion_detection');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
