import 'package:emotion_detection/emotion_detection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('package barrel exports the native migration public API', () {
    final controller = EmotionDetectorViewController();
    final widget = EmotionDetectorView(controller: controller);

    OnEmotion? onEmotion;
    OnFaceImage? onFaceImage;
    OnImage? onImage;

    expect(EmotionDetection, isA<Type>());
    expect(EmotionProvisioningResult, isA<Type>());
    expect(EmotionModelProvisioningResult, isA<Type>());
    expect(EmotionProvisioningException, isA<Type>());
    expect(EmotionDetectorViewController, isA<Type>());
    expect(UserCodeChannel, isA<Type>());
    expect(ModelRuntime, isA<Type>());
    expect(CekSecretClient, isA<Type>());
    expect(CekSecretUtils, isA<Type>());
    expect(ModelSecret, isA<Type>());
    expect(WebHostedInferenceClient, isA<Type>());
    expect(WebHostedInferenceRequest, isA<Type>());
    expect(WebHostedInferenceResult, isA<Type>());
    expect(WebHostedInferenceException, isA<Type>());
    expect(WebSmokeReport, isA<Type>());
    expect(WebSmokeReportException, isA<Type>());
    expect(defaultEmotionModelKey, isNotEmpty);
    expect(defaultEmotionModelKeys, isNotEmpty);
    expect(defaultAndroidEmotionModelKeys, isNotEmpty);
    expect(widget.controller, same(controller));
    expect(onEmotion, isNull);
    expect(onFaceImage, isNull);
    expect(onImage, isNull);
  });
}
