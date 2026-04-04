// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:emotion_detection/native/model_runtime.dart';
import 'package:emotion_detection/native/user_code_channel.dart';

import 'package:emotion_detection/emotion_detection.dart';
import 'package:emotion_detection_example/sdk_secret_module.dart';

const Map<String, String> _modelAccountIds = <String, String>{
  'aih_fer': 'aih_fer_v2025-01-15-shard',
  'aih_fer20250115': 'aih_fer_v2025-01-15-shard',
  'mobilenetv1_fer': 'mobilenetv1_fer_v2024-11-06-08-48-50-shard',
  'mobilenetv1_fer2024-11-06-08-48-50':
      'mobilenetv1_fer_v2024-11-06-08-48-50-shard',
};

String? _deriveModelShardAlias(String modelKey) {
  final isoMatch = RegExp(r'^(.+?)(\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2})$')
      .firstMatch(modelKey);
  if (isoMatch != null) {
    final prefix = isoMatch.group(1);
    final ts = isoMatch.group(2);
    if (prefix != null && ts != null) {
      return '${prefix}_v$ts-shard';
    }
  }

  final compactDateMatch = RegExp(r'^(.+?)(\d{8})$').firstMatch(modelKey);
  if (compactDateMatch != null) {
    final prefix = compactDateMatch.group(1);
    final yyyymmdd = compactDateMatch.group(2);
    if (prefix != null && yyyymmdd != null) {
      final yyyy = yyyymmdd.substring(0, 4);
      final mm = yyyymmdd.substring(4, 6);
      final dd = yyyymmdd.substring(6, 8);
      return '${prefix}_v$yyyy-$mm-$dd-shard';
    }
  }

  return null;
}

Iterable<String> _allModelIds(String modelKey) sync* {
  yield modelKey;
  final mapped = _modelAccountIds[modelKey];
  if (mapped != null && mapped.isNotEmpty && mapped != modelKey) {
    yield mapped;
  }
  final derived = _deriveModelShardAlias(modelKey);
  if (derived != null && derived.isNotEmpty && derived != modelKey) {
    yield derived;
  }
}

String _runtimeModelIdForKey(String modelKey) {
  final mapped = _modelAccountIds[modelKey];
  if (mapped != null && mapped.isNotEmpty) {
    return mapped;
  }
  final derived = _deriveModelShardAlias(modelKey);
  if (derived != null && derived.isNotEmpty) {
    return derived;
  }
  return modelKey;
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

    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}
    final env = dotenv.env;
    final module = ExampleSdkSecretModule(
      apiKeyId: env['SDK_KEY_ID'],
      apiKeySecret: env['SDK_KEY_SECRET'],
      overrideBaseUrl: env['EXAMPLE_SERVER_BASE_URL'],
      userName: env['EXAMPLE_USER_NAME'],
      modelKey: env['EXAMPLE_MODEL_KEY'],
      aad: env['EXAMPLE_MODEL_AAD'],
      iosAad: env['EXAMPLE_MODEL_AAD_IOS'],
      macosAad: env['EXAMPLE_MODEL_AAD_MACOS'],
      androidAad: env['EXAMPLE_MODEL_AAD_ANDROID'],
    );
    expect(
      module.hasRequiredConfig,
      true,
      reason: 'Missing SDK_KEY_ID/SDK_KEY_SECRET in .env or --dart-define.',
    );

    final keys = module.modelKeysForPlatform(defaultTargetPlatform);
    expect(keys.isNotEmpty, true);
    final modelKey = keys.firstWhere(
      (k) => k.contains('mobilenetv1_fer'),
      orElse: () => keys.first,
    );

    final aad = module.aadForPlatform(defaultTargetPlatform);
    final results = await module.fetchAllCekSecrets(
      aadOverride: aad,
      modelKeys: <String>[modelKey],
      targetPlatform: defaultTargetPlatform,
    );
    expect(results.isNotEmpty, true, reason: 'No CEK secret response.');

    final payload = results.first.payload;
    final userCodeB64 = module.extractUserCode(payload, modelKey: modelKey);
    expect(userCodeB64 != null && userCodeB64.isNotEmpty, true);

    final runtimeModelId = _runtimeModelIdForKey(modelKey);
    final modelAliases = <String>{..._allModelIds(modelKey), runtimeModelId};
    final payloadModelId =
        (payload['modelId'] ?? payload['model_id']) as String?;
    if (payloadModelId != null && payloadModelId.trim().isNotEmpty) {
      modelAliases.add(payloadModelId.trim());
    }

    final license = module.extractLicense(payload, modelKey: modelKey);
    if (license != null && license.isNotEmpty) {
      final licenseModelId = license['modelId'] as String?;
      if (licenseModelId != null && licenseModelId.trim().isNotEmpty) {
        modelAliases.add(licenseModelId.trim());
      }
    }

    final userName = module.userName;
    expect(userName.isNotEmpty, true);
    ModelRuntime('face_emotion_detection');

    for (final alias in modelAliases) {
      try {
        await UserCodeChannel.clearUserCode(userName, modelId: alias);
      } catch (_) {}
      try {
        await ModelRuntime.clearKeyShard(alias);
      } catch (_) {}
      try {
        await ModelRuntime.clearModelLicense(alias);
      } catch (_) {}
    }

    for (final alias in modelAliases) {
      await UserCodeChannel.saveUserCode(
        userName: userName,
        userCodeB64: userCodeB64!,
        modelId: alias,
      );
    }

    final shardB64 = module.extractShard(payload, modelKey: modelKey);
    final expiresAtMs = module.extractExpiresAtMs(payload, modelKey: modelKey);
    if (shardB64 != null && shardB64.isNotEmpty) {
      for (final alias in modelAliases) {
        await ModelRuntime.setKeyShard(
          modelId: alias,
          keyShardB64: shardB64,
          expiresAtMs: expiresAtMs,
          userName: userName,
        );
      }
    }

    if (license != null && license.isNotEmpty) {
      for (final alias in modelAliases) {
        await ModelRuntime.setModelLicense(modelId: alias, license: license);
      }
    }

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
