import 'package:emotion_detection/emotion_detection.dart';
import 'package:emotion_detection/emotion_detection_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeEmotionDetectionPlatform
    with MockPlatformInterfaceMixin
    implements EmotionDetectionPlatform {
  @override
  Future<String?> getPlatformVersion() async => '42';
}

void main() {
  test('getPlatformVersion delegates to platform implementation', () async {
    EmotionDetectionPlatform.instance = _FakeEmotionDetectionPlatform();

    await expectLater(
      EmotionDetection().getPlatformVersion(),
      completion('42'),
    );
  });
}
