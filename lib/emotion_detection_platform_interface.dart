import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'emotion_detection_method_channel.dart';

abstract class EmotionDetectionPlatform extends PlatformInterface {
  /// Constructs a EmotionDetectionPlatform.
  EmotionDetectionPlatform() : super(token: _token);

  static final Object _token = Object();

  static EmotionDetectionPlatform _instance = MethodChannelEmotionDetection();

  /// The default instance of [EmotionDetectionPlatform] to use.
  ///
  /// Defaults to [MethodChannelEmotionDetection].
  static EmotionDetectionPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [EmotionDetectionPlatform] when
  /// they register themselves.
  static set instance(EmotionDetectionPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    return instance.getPlatformVersion();
    //throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
