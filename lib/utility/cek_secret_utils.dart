import 'dart:convert';

/// Model-specific secret info extracted from an API payload.
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

/// Utility helpers for working with CEK-secret style payloads.
class CekSecretUtils {
  const CekSecretUtils._();

  /// Extract the user code from a payload. If [modelKey] is supplied, prefers
  /// model-scoped entries under `modelSecrets` matching that key.
  static String? extractUserCode(Map<String, dynamic> payload,
      {String? modelKey}) {
    if (modelKey != null && modelKey.isNotEmpty) {
      final secrets = extractModelSecrets(payload);
      for (final secret in secrets) {
        if (secret.modelKey == modelKey && secret.raw != null) {
          final fromModel = _extractUserCodeFrom(secret.raw!);
          if (fromModel != null) return fromModel;
        }
      }
    }
    return _extractUserCodeFrom(payload);
  }

  /// Extracts the preferred model key string from a payload.
  static String? extractModelKey(Map<String, dynamic> payload) {
    final value =
        payload['modelKey'] ?? payload['model_id'] ?? payload['modelId'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// Extracts the base64-encoded shard for a model. If [modelKey] is supplied,
  /// prefers model-scoped entries under `modelSecrets`.
  static String? extractShard(Map<String, dynamic> payload,
      {String? modelKey}) {
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

  /// Extracts a best-effort expiry timestamp (ms since epoch). If [modelKey]
  /// is supplied, prefers model-scoped entries under `modelSecrets`.
  static int? extractExpiresAtMs(Map<String, dynamic> payload,
      {String? modelKey}) {
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

  /// Extracts per-model license payload.
  /// Accepts object forms (`license`, `licenseDoc`) or JSON string forms
  /// (`licenseJson`, `license_json`).
  static Map<String, dynamic>? extractLicense(Map<String, dynamic> payload,
      {String? modelKey}) {
    if (modelKey != null && modelKey.isNotEmpty) {
      final list = payload['modelSecrets'];
      if (list is List) {
        for (final item in list) {
          if (item is! Map) continue;
          final asMap = Map<String, dynamic>.from(item);
          final mk = _readModelKey(asMap);
          if (mk == modelKey) {
            final fromModel = _extractLicenseFrom(asMap);
            if (fromModel != null) return fromModel;
          }
        }
      }
    }
    return _extractLicenseFrom(payload);
  }

  /// Parses the `modelSecrets` array into typed entries.
  static List<ModelSecret> extractModelSecrets(Map<String, dynamic> payload) {
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

  /// Normalizes base64 to RFC-4648 by converting URL-safe characters and
  /// padding to a multiple of 4.
  static String normalizeBase64(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final missing = (4 - normalized.length % 4) % 4;
    if (missing > 0) {
      normalized = normalized.padRight(normalized.length + missing, '=');
    }
    return normalized;
  }

  // Internal helpers --------------------------------------------------------

  static String? _extractUserCodeFrom(Map<String, dynamic> payload) {
    for (final key in const [
      'userCodeB64',
      'userSecretB64',
      'user32B64',
      'user32',
      'user_code_b64',
    ]) {
      final value = payload[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static String? _extractShardFrom(Map<String, dynamic> map) {
    for (final key in const [
      'kekShardB64',
      'cekShardB64',
      'keyShardB64',
      'shardB64',
      'cekShard',
      'cek_shard_b64',
    ]) {
      final value = map[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static int? _extractExpiresAt(Map<String, dynamic> map) {
    for (final key in const [
      'expiresAt',
      'expires_at',
      'expiry_epoch_ms',
      'cekSecretExpiresAt',
    ]) {
      final value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String && value.isNotEmpty) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return parsed.millisecondsSinceEpoch;
        }
      }
    }
    return null;
  }

  static String? _readModelKey(Map<String, dynamic> map) {
    final value = map['modelKey'] ?? map['model_id'] ?? map['modelId'];
    return value is String ? value : null;
  }

  static bool? _readShardRequired(Map<String, dynamic> map) {
    final value = map['shardRequired'] ?? map['shard_required'];
    return value is bool ? value : null;
  }

  static Map<String, dynamic>? _extractLicenseFrom(Map<String, dynamic> map) {
    for (final key in const ['license', 'licenseDoc', 'license_doc']) {
      final value = map[key];
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
    }
    for (final key in const ['licenseJson', 'license_json']) {
      final value = map[key];
      if (value is String && value.isNotEmpty) {
        final decoded = _decodeJsonMap(value);
        if (decoded != null) return decoded;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _decodeJsonMap(String raw) {
    try {
      final obj = jsonDecode(raw);
      if (obj is Map<String, dynamic>) {
        return obj;
      }
      if (obj is Map) {
        return Map<String, dynamic>.from(obj);
      }
    } catch (_) {
      // no-op
    }
    return null;
  }
}
