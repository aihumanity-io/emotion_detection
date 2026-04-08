import 'dart:typed_data';

import 'package:emotion_detection/native/model_runtime.dart';
import 'package:emotion_detection/native/user_code_channel.dart';
import 'package:emotion_detection_example/sdk_secret_module.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String _defaultModelKey =
    'aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx';
const MethodChannel _channel = MethodChannel('face_emotion_detection');

const Map<String, String> _modelAccountIds = <String, String>{
  'aih_fer': 'aih_fer_v2025-01-15-shard',
  'aih_fer20250115': 'aih_fer_v2025-01-15-shard',
  'aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx':
      'aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx',
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

Uint8List _solidBgraFrame(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i + 0] = 127; // B
    bytes[i + 1] = 127; // G
    bytes[i + 2] = 127; // R
    bytes[i + 3] = 255; // A
  }
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS ONNX default model smoke test', (WidgetTester tester) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}
    final env = dotenv.env;

    const fromDefine =
        String.fromEnvironment('EXAMPLE_MODEL_KEY', defaultValue: '');
    final preferredModelKey =
        fromDefine.trim().isNotEmpty ? fromDefine.trim() : _defaultModelKey;
    final module = ExampleSdkSecretModule(
      apiKeyId: env['SDK_KEY_ID'],
      apiKeySecret: env['SDK_KEY_SECRET'],
      overrideBaseUrl: env['EXAMPLE_SERVER_BASE_URL'],
      userName: env['EXAMPLE_USER_NAME'],
      modelKey: preferredModelKey,
      modelKeys: <String>[preferredModelKey],
      aad: env['EXAMPLE_MODEL_AAD'],
      iosAad: env['EXAMPLE_MODEL_AAD_IOS'],
      macosAad: env['EXAMPLE_MODEL_AAD_MACOS'],
      androidAad: env['EXAMPLE_MODEL_AAD_ANDROID'],
    );

    expect(
      module.hasRequiredConfig,
      true,
      reason: 'Missing SDK_KEY_ID/SDK_KEY_SECRET.',
    );

    final aad = module.aadForPlatform(defaultTargetPlatform);
    final results = await module.fetchAllCekSecrets(
      aadOverride: aad,
      modelKeys: <String>[preferredModelKey],
      targetPlatform: defaultTargetPlatform,
    );
    expect(results.isNotEmpty, true, reason: 'No CEK secret response.');

    final payload = results.first.payload;
    final userCodeB64 =
        module.extractUserCode(payload, modelKey: preferredModelKey);
    expect(userCodeB64 != null && userCodeB64.isNotEmpty, true);

    final runtimeModelId = _runtimeModelIdForKey(preferredModelKey);
    final modelAliases = <String>{
      ..._allModelIds(preferredModelKey),
      runtimeModelId
    };
    final payloadModelId =
        (payload['modelId'] ?? payload['model_id']) as String?;
    if (payloadModelId != null && payloadModelId.trim().isNotEmpty) {
      modelAliases.add(payloadModelId.trim());
    }

    final license = module.extractLicense(payload, modelKey: preferredModelKey);
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

    final shardB64 = module.extractShard(payload, modelKey: preferredModelKey);
    final expiresAtMs =
        module.extractExpiresAtMs(payload, modelKey: preferredModelKey);
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

    final width = 224;
    final height = 224;
    final output =
        await _channel.invokeMethod<dynamic>('faceEmotion', <String, dynamic>{
      'image': _solidBgraFrame(width, height),
      'width': width,
      'height': height,
      'orientation': 'up',
      'left': 0,
      'top': 0,
      'boxwidth': width,
      'boxheight': height,
      'landmarks': <List<int>>[],
    });

    expect(output, isA<Map>(), reason: 'faceEmotion returned non-map: $output');
    final map = Map<String, dynamic>.from(output as Map);
    expect(map.isNotEmpty, true, reason: 'faceEmotion returned empty map.');
    expect(map.keys.length >= 7, true,
        reason: 'Unexpected output keys: ${map.keys}');
    expect(
      map.keys.any((key) => key == 'Happiness' || key == 'output_0'),
      true,
      reason: 'Output format unexpected: ${map.keys}',
    );
  });
}
