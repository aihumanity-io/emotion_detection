import 'package:emotion_detection/emotion_detection.dart';
import 'package:flutter/foundation.dart';

const String _exampleSdkKeyId = String.fromEnvironment(
  'SDK_KEY_ID',
  defaultValue: '',
);
const String _exampleSdkKeySecret = String.fromEnvironment(
  'SDK_KEY_SECRET',
  defaultValue: '',
);
const String _exampleModelKey = String.fromEnvironment(
  'EXAMPLE_MODEL_KEY',
  defaultValue: 'mobilenetv1_fer2024-11-06-08-48-50',
);
const List<String> _exampleModelKeys = <String>[
  'aih_fer20250115',
  'mobilenetv1_fer2024-11-06-08-48-50',
];
const List<String> _androidModelKeys = <String>[
  'mobilenetv1_fer2024-11-06-08-48-50',
];
const String _exampleAad = String.fromEnvironment(
  'EXAMPLE_MODEL_AAD',
  defaultValue: 'com.creataai.emotionsdk/ios',
);
const String _exampleMacOSAad = String.fromEnvironment(
  'EXAMPLE_MODEL_AAD_MACOS',
  defaultValue: 'com.creataai.emotionsdk/ios',
);
const String _exampleAndroidAad = String.fromEnvironment(
  'EXAMPLE_MODEL_AAD_ANDROID',
  defaultValue: 'com.creataai.emotionsdk/android',
);
const String _exampleOverrideBase = String.fromEnvironment(
  'EXAMPLE_SERVER_BASE_URL',
  defaultValue: 'https://tartalabapi.onrender.com',
);
const String _exampleUserName = String.fromEnvironment(
  'EXAMPLE_USER_NAME',
  defaultValue: 'dev@tartalabs.io',
);

/// Payload plus the modelKey it was requested with.
class CekSecretResult {
  CekSecretResult({required this.modelKey, required this.payload});
  final String modelKey;
  final Map<String, dynamic> payload;
}

/// Simple wrapper used by the example app to demonstrate
/// how to call [CekSecretClient.fetchCekSecret].
class ExampleSdkSecretModule {
  ExampleSdkSecretModule({
    String? apiKeyId,
    String? apiKeySecret,
    String? modelKey,
    List<String>? modelKeys,
    String? aad,
    String? macAad,
    String? androidAad,
    String? overrideBaseUrl,
    String? userName,
  })  : _apiKeyId = apiKeyId ?? _exampleSdkKeyId,
        _apiKeySecret = apiKeySecret ?? _exampleSdkKeySecret,
        _aad = aad ?? _exampleAad,
        _macAad = macAad ?? _exampleMacOSAad,
        _androidAad = androidAad ?? _exampleAndroidAad,
        _overrideBaseUrl = overrideBaseUrl ?? _exampleOverrideBase,
        _userName = userName ?? _exampleUserName,
        _modelKeys = (modelKeys != null && modelKeys.isNotEmpty)
            ? modelKeys
            : _exampleModelKeys,
        _modelKey = modelKey ??
            ((modelKeys != null && modelKeys.isNotEmpty)
                ? modelKeys.first
                : _exampleModelKey);

  final String _apiKeyId;
  final String _apiKeySecret;
  final String _modelKey;
  final List<String> _modelKeys;
  final String _aad;
  final String _macAad;
  final String _androidAad;
  final String _overrideBaseUrl;
  final String _userName;

  Future<Map<String, dynamic>?> fetchCekSecret({String? aadOverride}) {
    return CekSecretClient.fetchCekSecret(
      apiKeyId: _apiKeyId,
      apiKeySecret: _apiKeySecret,
      modelKey: _modelKey,
      aad: (aadOverride ?? _aad).isEmpty ? null : (aadOverride ?? _aad),
      overrideBaseUrl: _overrideBaseUrl.isEmpty ? null : _overrideBaseUrl,
    );
  }

  /// Fetch secrets for all configured model keys, returning the non-null
  /// payloads in order. Each call only includes the shard for the requested
  /// model key.
  Future<List<CekSecretResult>> fetchAllCekSecrets(
      {String? aadOverride, List<String>? modelKeys}) async {
    final results = <CekSecretResult>[];
    final keys = modelKeys ?? _modelKeys;
    for (final key in keys) {
      final res = await CekSecretClient.fetchCekSecret(
        apiKeyId: _apiKeyId,
        apiKeySecret: _apiKeySecret,
        modelKey: key,
        aad: (aadOverride ?? _aad).isEmpty ? null : (aadOverride ?? _aad),
        overrideBaseUrl: _overrideBaseUrl.isEmpty ? null : _overrideBaseUrl,
      );
      if (res != null) {
        results.add(CekSecretResult(modelKey: key, payload: res));
      }
    }
    return results;
  }

  bool get hasRequiredConfig =>
      _apiKeyId.isNotEmpty &&
      _apiKeySecret.isNotEmpty &&
      _modelKeys.isNotEmpty &&
      _modelKeys.first.isNotEmpty;

  String get userName => _userName;

  bool get hasUserName => userName.isNotEmpty;

  String get modelKey => _modelKey;

  List<String> get modelKeys => _modelKeys;

  List<String> modelKeysForPlatform(TargetPlatform platform) {
    if (platform == TargetPlatform.android) {
      return _androidModelKeys;
    }
    return _modelKeys;
  }

  String aadForPlatform(TargetPlatform platform) {
    if (platform == TargetPlatform.android) {
      return _androidAad;
    }
    if (platform == TargetPlatform.macOS) {
      return _macAad;
    }
    return _aad; // iOS and others
  }

  /// Returns the AAD to request based on platform; callers should surface 403
  /// errors to the user/operator so they can register the platform AAD if
  /// missing.

  String? extractUserCode(Map<String, dynamic> payload, {String? modelKey}) {
    return CekSecretUtils.extractUserCode(payload, modelKey: modelKey);
  }

  String? extractModelKey(Map<String, dynamic> payload) {
    return CekSecretUtils.extractModelKey(payload);
  }

  /// Extract the shard for a given model. If [modelKey] is provided, this
  /// first searches the `modelSecrets` array for a matching entry. Otherwise
  /// it falls back to top-level shard fields.
  String? extractShard(Map<String, dynamic> payload, {String? modelKey}) {
    return CekSecretUtils.extractShard(payload, modelKey: modelKey);
  }

  int? extractExpiresAtMs(Map<String, dynamic> payload, {String? modelKey}) {
    return CekSecretUtils.extractExpiresAtMs(payload, modelKey: modelKey);
  }

  /// Parse the `modelSecrets` array into typed entries.
  List<ModelSecret> extractModelSecrets(Map<String, dynamic> payload) {
    return CekSecretUtils.extractModelSecrets(payload);
  }

  String normalizeShard(String shardB64) => CekSecretUtils.normalizeBase64(shardB64);
}
