import 'package:emotion_detection/emotion_detection_platform_interface.dart';
import 'package:emotion_detection_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeEmotionDetectionPlatform
    with MockPlatformInterfaceMixin
    implements EmotionDetectionPlatform {
  @override
  Future<String?> getPlatformVersion() async => 'test-platform';

  @override
  Stream<Map<String, double>> macCameraStream({String? modelId}) {
    return const Stream<Map<String, double>>.empty();
  }

  @override
  Future<void> macShowCameraPreview({String? modelId}) async {}

  @override
  Future<void> macHideCameraPreview() async {}

  @override
  Future<void> saveUserCode({
    required String userName,
    required String userCodeB64,
    bool requireBiometrics = false,
    String? modelId,
  }) async {}

  @override
  Future<void> clearUserCode(String userName, {String? modelId}) async {}

  @override
  void configureModelRuntimeChannel(String methodChannelName) {}

  @override
  Future<void> registerModel({
    required String modelId,
    required String resourceBase,
    String encExt = 'onnx.enc',
    String hkdfInfo = 'model_runtime',
    String? masterKeyB64,
  }) async {}

  @override
  Future<void> setKeyShard({
    required String modelId,
    required String keyShardB64,
    int? expiresAtMs,
    String? userName,
  }) async {}

  @override
  Future<void> clearKeyShard(String modelId) async {}

  @override
  Future<void> setModelLicense({
    required String modelId,
    required Map<String, dynamic> license,
  }) async {}

  @override
  Future<void> clearModelLicense(String modelId) async {}

  @override
  Future<bool> warmUp(String modelId) async => true;

  @override
  Future<Map<String, dynamic>> predict(
    String modelId,
    Map<String, dynamic> inputs,
  ) async {
    return <String, dynamic>{};
  }

  @override
  Future<void> unload(String modelId) async {}
}

void main() {
  testWidgets('example app starts through public plugin API', (tester) async {
    EmotionDetectionPlatform.instance = _FakeEmotionDetectionPlatform();
    dotenv.testLoad();

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Emotion SDK Example (test-platform)'), findsOneWidget);
    expect(find.text('Select image'), findsOneWidget);
    expect(find.text('Start camera'), findsOneWidget);
    expect(find.text('Stop camera'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
