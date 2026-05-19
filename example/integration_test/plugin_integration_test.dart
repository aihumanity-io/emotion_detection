// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io' show Platform;

import 'package:emotion_detection/emotion_detection.dart';

const String _modelKeyFromDefine = String.fromEnvironment(
  'EXAMPLE_MODEL_KEY',
  defaultValue: '',
);

const String _sdkKeyIdFromDefine =
    String.fromEnvironment('SDK_KEY_ID', defaultValue: '');
const String _sdkKeySecretFromDefine =
    String.fromEnvironment('SDK_KEY_SECRET', defaultValue: '');
const String _exampleUserNameFromDefine =
    String.fromEnvironment('EXAMPLE_USER_NAME', defaultValue: '');
const String _exampleServerBaseUrlFromDefine =
    String.fromEnvironment('EXAMPLE_SERVER_BASE_URL', defaultValue: '');
const String _exampleModelAadFromDefine =
    String.fromEnvironment('EXAMPLE_MODEL_AAD', defaultValue: '');
const String _exampleModelAadMacosFromDefine =
    String.fromEnvironment('EXAMPLE_MODEL_AAD_MACOS', defaultValue: '');
const String _exampleModelAadIosFromDefine =
    String.fromEnvironment('EXAMPLE_MODEL_AAD_IOS', defaultValue: '');
const String _exampleModelAadAndroidFromDefine =
    String.fromEnvironment('EXAMPLE_MODEL_AAD_ANDROID', defaultValue: '');

String _pickValue(
  String fromDefine,
  Map<String, String> dotenvEnv,
  String key,
) {
  final defineValue = fromDefine.trim();
  if (defineValue.isNotEmpty) return defineValue;

  final dotenvValue = (dotenvEnv[key] ?? '').trim();
  if (dotenvValue.isNotEmpty) return dotenvValue;

  return (Platform.environment[key] ?? '').trim();
}

final List<int> _tinyPngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0xF0,
  0x1F,
  0x00,
  0x05,
  0x00,
  0x01,
  0xFF,
  0x89,
  0x99,
  0x3D,
  0x1D,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getPlatformVersion test', (WidgetTester tester) async {
    final EmotionDetection plugin = EmotionDetection();
    final String? version = await plugin.getPlatformVersion();
    // The version string depends on the host platform running the test, so
    // just assert that some non-empty string is returned.
    expect(version?.isNotEmpty, true);
  });

  testWidgets('runtime decrypt + load + predict test (macOS)', (
    WidgetTester tester,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }

    Map<String, String> dotenvEnv = <String, String>{};
    try {
      await dotenv.load(fileName: '.env');
      dotenvEnv = dotenv.env;
    } catch (_) {
      dotenvEnv = <String, String>{};
    }

    final preferredModelKey =
        _pickValue(_modelKeyFromDefine, dotenvEnv, 'EXAMPLE_MODEL_KEY');

    final provisioner = EmotionDetectionProvisioner(
      sdkKeyId: _pickValue(_sdkKeyIdFromDefine, dotenvEnv, 'SDK_KEY_ID'),
      sdkKeySecret:
          _pickValue(_sdkKeySecretFromDefine, dotenvEnv, 'SDK_KEY_SECRET'),
      serverBaseUrl: _pickValue(
        _exampleServerBaseUrlFromDefine,
        dotenvEnv,
        'EXAMPLE_SERVER_BASE_URL',
      ),
      userName: _pickValue(
          _exampleUserNameFromDefine, dotenvEnv, 'EXAMPLE_USER_NAME'),
      modelKey: preferredModelKey.isEmpty
          ? dotenvEnv['EXAMPLE_MODEL_KEY']
          : preferredModelKey,
      modelKeys: preferredModelKey.isEmpty ? null : <String>[preferredModelKey],
      aad: _pickValue(
          _exampleModelAadFromDefine, dotenvEnv, 'EXAMPLE_MODEL_AAD'),
      iosAad: _pickValue(
          _exampleModelAadIosFromDefine, dotenvEnv, 'EXAMPLE_MODEL_AAD_IOS'),
      macosAad: _pickValue(
        _exampleModelAadMacosFromDefine,
        dotenvEnv,
        'EXAMPLE_MODEL_AAD_MACOS',
      ),
      androidAad: _pickValue(
        _exampleModelAadAndroidFromDefine,
        dotenvEnv,
        'EXAMPLE_MODEL_AAD_ANDROID',
      ),
    );
    expect(
      provisioner.hasRequiredConfig,
      true,
      reason: 'Missing SDK_KEY_ID/SDK_KEY_SECRET in .env or --dart-define.',
    );

    final keys = provisioner.modelKeysForPlatform(defaultTargetPlatform);
    expect(keys.isNotEmpty, true);
    final modelKey = keys.firstWhere(
      (k) => preferredModelKey.isNotEmpty && k == preferredModelKey,
      orElse: () => keys.first,
    );

    final result = await provisioner.provision(
      targetPlatform: defaultTargetPlatform,
      aadOverride: provisioner.aadForPlatform(defaultTargetPlatform),
      modelKeys: <String>[modelKey],
      clearExistingSecrets: true,
      warmUp: false,
    );
    expect(result.isReady, true, reason: result.status);

    final runtimeModelId = provisioner.runtimeModelIdForKey(modelKey);
    final output = await ModelRuntime.predict(runtimeModelId, <String, dynamic>{
      'imageBytes': Uint8List.fromList(_tinyPngBytes),
    });
    expect(output.isNotEmpty, true, reason: 'Predict output is empty.');
    expect(
      output.values.any((value) => value is num),
      true,
      reason: 'Predict output missing numeric scores.',
    );
  });
}
