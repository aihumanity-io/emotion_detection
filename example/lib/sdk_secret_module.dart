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

/// Model-specific secret info extracted from the API payload.
class ModelSecret {
  ModelSecret({
    required this.modelKey,
    required this.shardB64,
    this.expiresAtMs,
    this.shardRequired,
    this.raw,
  });

  final String modelKey;
  final String shardB64;
  final int? expiresAtMs;
  final bool? shardRequired;
  final Map<String, dynamic>? raw;
}

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
    String? androidAad,
    String? overrideBaseUrl,
    String? userName,
  })  : _apiKeyId = apiKeyId ?? _exampleSdkKeyId,
        _apiKeySecret = apiKeySecret ?? _exampleSdkKeySecret,
        _aad = aad ?? _exampleAad,
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
    return _aad;
  }

  /// Returns the AAD to request based on platform; callers should surface 403
  /// errors to the user/operator so they can register the platform AAD if
  /// missing.

  String? extractUserCode(Map<String, dynamic> payload, {String? modelKey}) {
    // Prefer model-scoped secrets when modelKey is provided
    if (modelKey != null && modelKey.isNotEmpty) {
      final secrets = extractModelSecrets(payload);
      for (final secret in secrets) {
        if (secret.modelKey == modelKey) {
          final fromModel =
              secret.raw == null ? null : _extractUserCodeFrom(secret.raw!);
          if (fromModel != null) return fromModel;
        }
      }
    }
    return _extractUserCodeFrom(payload);
  }

  String? _extractUserCodeFrom(Map<String, dynamic> payload) {
    for (final key in const [
      'userCodeB64',
      'userSecretB64',
      'user32B64',
      'user32',
      'user_code_b64'
    ]) {
      final value = payload[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String? extractModelKey(Map<String, dynamic> payload) {
    final value =
        payload['modelKey'] ?? payload['model_id'] ?? payload['modelId'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// Extract the shard for a given model. If [modelKey] is provided, this
  /// first searches the `modelSecrets` array for a matching entry. Otherwise
  /// it falls back to top-level shard fields.
  String? extractShard(Map<String, dynamic> payload, {String? modelKey}) {
    if (modelKey != null && modelKey.isNotEmpty) {
      final secrets = extractModelSecrets(payload);
      for (final secret in secrets) {
        if (secret.modelKey == modelKey) {
          return secret.shardB64;
        }
      }
    }
    return _extractShardFrom(payload);
  }

  int? extractExpiresAtMs(Map<String, dynamic> payload, {String? modelKey}) {
    if (modelKey != null && modelKey.isNotEmpty) {
      final secrets = extractModelSecrets(payload);
      for (final secret in secrets) {
        if (secret.modelKey == modelKey) {
          return secret.expiresAtMs;
        }
      }
    }
    return _extractExpiresAt(payload);
  }

  /// Parse the `modelSecrets` array into typed entries.
  List<ModelSecret> extractModelSecrets(Map<String, dynamic> payload) {
    final list = payload['modelSecrets'];
    if (list is! List) {
      return const [];
    }

    final out = <ModelSecret>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final modelKey = _readModelKey(item);
      if (modelKey == null || modelKey.isEmpty) {
        continue;
      }
      final shard = _extractShardFrom(item);
      if (shard == null || shard.isEmpty) {
        continue;
      }
      final expiresAtMs = _extractExpiresAt(item);
      final shardRequired = _readShardRequired(item);
      out.add(ModelSecret(
        modelKey: modelKey,
        shardB64: shard,
        expiresAtMs: expiresAtMs,
        shardRequired: shardRequired,
        raw: item,
      ));
    }
    return out;
  }

  String? _extractShardFrom(Map<String, dynamic> map) {
    for (final key in const [
      'kekShardB64',
      'cekShardB64',
      'keyShardB64',
      'shardB64',
      'cekShard',
      'cek_shard_b64'
    ]) {
      final value = map[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String normalizeShard(String shardB64) => _normalizeBase64(shardB64);

  String _normalizeBase64(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final missing = (4 - normalized.length % 4) % 4;
    if (missing > 0) {
      normalized = normalized.padRight(normalized.length + missing, '=');
    }
    return normalized;
  }

  int? _extractExpiresAt(Map<String, dynamic> map) {
    for (final key in const [
      'expiresAt',
      'expires_at',
      'expiry_epoch_ms',
      'cekSecretExpiresAt'
    ]) {
      final value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return parsed.millisecondsSinceEpoch;
        }
      }
    }
    return null;
  }

  String? _readModelKey(Map<String, dynamic> map) {
    final value = map['modelKey'] ?? map['model_id'] ?? map['modelId'];
    return value is String ? value : null;
  }

  bool? _readShardRequired(Map<String, dynamic> map) {
    final value = map['shardRequired'] ?? map['shard_required'];
    return value is bool ? value : null;
  }
}
