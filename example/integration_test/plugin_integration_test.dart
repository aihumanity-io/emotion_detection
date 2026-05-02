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

import 'package:emotion_detection/emotion_detection.dart';

const String _modelKeyFromDefine = String.fromEnvironment(
  'EXAMPLE_MODEL_KEY',
  defaultValue: '',
);

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

    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}
    final env = dotenv.env;
    final preferredModelKey = _modelKeyFromDefine.trim().isNotEmpty
        ? _modelKeyFromDefine.trim()
        : (env['EXAMPLE_MODEL_KEY'] ?? '').trim();
    final provisioner = EmotionDetectionProvisioner(
      sdkKeyId: env['SDK_KEY_ID'] ?? '',
      sdkKeySecret: env['SDK_KEY_SECRET'] ?? '',
      serverBaseUrl: env['EXAMPLE_SERVER_BASE_URL'],
      userName: env['EXAMPLE_USER_NAME'] ?? '',
      modelKey: preferredModelKey.isEmpty
          ? env['EXAMPLE_MODEL_KEY']
          : preferredModelKey,
      modelKeys: preferredModelKey.isEmpty ? null : <String>[preferredModelKey],
      aad: env['EXAMPLE_MODEL_AAD'],
      iosAad: env['EXAMPLE_MODEL_AAD_IOS'],
      macosAad: env['EXAMPLE_MODEL_AAD_MACOS'],
      androidAad: env['EXAMPLE_MODEL_AAD_ANDROID'],
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
