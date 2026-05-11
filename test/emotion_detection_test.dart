import 'package:emotion_detection/emotion_detection.dart';
import 'package:emotion_detection/emotion_detection_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeEmotionDetectionPlatform
    with MockPlatformInterfaceMixin
    implements EmotionDetectionPlatform {
  String? streamModelId;
  String? previewModelId;
  var hidePreviewCallCount = 0;

  @override
  Future<String?> getPlatformVersion() async => '42';

  @override
  Stream<Map<String, double>> macCameraStream({String? modelId}) {
    streamModelId = modelId;
    return Stream<Map<String, double>>.value({'happy': 0.75});
  }

  @override
  Future<void> macShowCameraPreview({String? modelId}) async {
    previewModelId = modelId;
  }

  @override
  Future<void> macHideCameraPreview() async {
    hidePreviewCallCount += 1;
  }
}

void main() {
  test('getPlatformVersion delegates to platform implementation', () async {
    EmotionDetectionPlatform.instance = _FakeEmotionDetectionPlatform();

    await expectLater(
      EmotionDetection().getPlatformVersion(),
      completion('42'),
    );
  });

  test('mac camera stream delegates to platform implementation', () async {
    final platform = _FakeEmotionDetectionPlatform();
    EmotionDetectionPlatform.instance = platform;

    await expectLater(
      EmotionDetection().macCameraStream(modelId: 'model-a'),
      emits({'happy': 0.75}),
    );
    expect(platform.streamModelId, 'model-a');
  });

  test('mac camera preview controls delegate to platform implementation',
      () async {
    final platform = _FakeEmotionDetectionPlatform();
    EmotionDetectionPlatform.instance = platform;

    await EmotionDetection().macShowCameraPreview(modelId: 'model-b');
    await EmotionDetection().macHideCameraPreview();

    expect(platform.previewModelId, 'model-b');
    expect(platform.hidePreviewCallCount, 1);
  });
}
