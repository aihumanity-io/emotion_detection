import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../native/model_runtime.dart';
import '../native/user_code_channel.dart';
import 'cek_secret_utils.dart';
import 'sdk_secret_client.dart';

const String defaultEmotionModelKey =
    'aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx';

const List<String> defaultEmotionModelKeys = <String>[
  'aih_fer20250115',
  'mobilenetv1_fer2024-11-06-08-48-50',
  defaultEmotionModelKey,
];

const List<String> defaultAndroidEmotionModelKeys = <String>[
  defaultEmotionModelKey,
];

class EmotionProvisioningException implements Exception {
  EmotionProvisioningException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'EmotionProvisioningException($code): $message';
}

class EmotionModelProvisioningResult {
  EmotionModelProvisioningResult({
    required this.modelKey,
    required this.modelIds,
    required this.storedUserCodes,
    required this.storedShards,
    required this.storedLicenses,
    required this.warmedModels,
  });

  final String modelKey;
  final Set<String> modelIds;
  final int storedUserCodes;
  final int storedShards;
  final int storedLicenses;
  final int warmedModels;
}

class EmotionProvisioningResult {
  EmotionProvisioningResult({
    required this.models,
    required this.status,
  });

  final List<EmotionModelProvisioningResult> models;
  final String status;

  int get storedUserCodes =>
      models.fold(0, (total, model) => total + model.storedUserCodes);
  int get storedShards =>
      models.fold(0, (total, model) => total + model.storedShards);
  int get storedLicenses =>
      models.fold(0, (total, model) => total + model.storedLicenses);
  int get warmedModels =>
      models.fold(0, (total, model) => total + model.warmedModels);
  bool get isReady => storedUserCodes > 0;
  Set<String> get modelIds =>
      Set<String>.unmodifiable(models.expand((model) => model.modelIds));
}

class EmotionDetectionProvisioner {
  EmotionDetectionProvisioner({
    required String sdkKeyId,
    required String sdkKeySecret,
    required String userName,
    List<String>? modelKeys,
    String? modelKey,
    String? iosAad,
    String? aad,
    String? macosAad,
    String? androidAad,
    String? serverBaseUrl,
    http.Client? client,
  })  : _sdkKeyId = sdkKeyId.trim(),
        _sdkKeySecret = sdkKeySecret.trim(),
        _userName = userName.trim(),
        _modelKeys = (modelKeys != null && modelKeys.isNotEmpty)
            ? modelKeys
            : defaultEmotionModelKeys,
        _modelKey = (modelKey == null || modelKey.trim().isEmpty)
            ? ((modelKeys != null && modelKeys.isNotEmpty)
                ? modelKeys.first
                : defaultEmotionModelKey)
            : modelKey.trim(),
        _iosAad = (iosAad ?? aad ?? 'com.creataai.emotionsdk/ios').trim(),
        _aad = (aad ?? 'com.creataai.emotionsdk/ios').trim(),
        _macosAad = (macosAad ?? 'com.creataai.emotionsdk/ios').trim(),
        _androidAad = (androidAad ?? 'com.creataai.emotionsdk/android').trim(),
        _serverBaseUrl = serverBaseUrl?.trim(),
        _client = client;

  final String _sdkKeyId;
  final String _sdkKeySecret;
  final String _userName;
  final String _modelKey;
  final List<String> _modelKeys;
  final String _iosAad;
  final String _aad;
  final String _macosAad;
  final String _androidAad;
  final String? _serverBaseUrl;
  final http.Client? _client;

  String get userName => _userName;
  String get modelKey => _modelKey;
  List<String> get modelKeys => _modelKeys;

  bool get hasRequiredConfig =>
      _sdkKeyId.isNotEmpty &&
      _sdkKeySecret.isNotEmpty &&
      _userName.isNotEmpty &&
      _modelKeys.isNotEmpty;

  List<String> modelKeysForPlatform(TargetPlatform platform) {
    if (platform == TargetPlatform.android) {
      return defaultAndroidEmotionModelKeys;
    }
    return _modelKeys;
  }

  String aadForPlatform(TargetPlatform platform) {
    if (platform == TargetPlatform.android) return _androidAad;
    if (platform == TargetPlatform.macOS) return _macosAad;
    if (platform == TargetPlatform.iOS) return _iosAad;
    return _aad;
  }

  String runtimeModelIdForKey(String modelKey) {
    final mapped = _modelAccountIds[modelKey];
    if (mapped != null && mapped.isNotEmpty) return mapped;
    final derived = _deriveModelShardAlias(modelKey);
    if (derived != null && derived.isNotEmpty) return derived;
    return modelKey;
  }

  Iterable<String> allModelIds(String modelKey) sync* {
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

  String activeModelId({TargetPlatform? targetPlatform}) {
    final preferred = _modelKey.trim();
    if (preferred.isNotEmpty) return runtimeModelIdForKey(preferred);
    final keys = modelKeysForPlatform(targetPlatform ?? defaultTargetPlatform);
    if (keys.contains(defaultEmotionModelKey)) {
      return runtimeModelIdForKey(defaultEmotionModelKey);
    }
    if (keys.isNotEmpty) {
      return runtimeModelIdForKey(keys.first);
    }
    return runtimeModelIdForKey('mobilenetv1_fer');
  }

  Future<EmotionProvisioningResult> provision({
    TargetPlatform? targetPlatform,
    List<String>? modelKeys,
    String? aadOverride,
    bool clearExistingSecrets = false,
    bool warmUp = true,
  }) async {
    if (!hasRequiredConfig) {
      throw EmotionProvisioningException(
        'missing_config',
        'sdkKeyId, sdkKeySecret, userName, and at least one model key are required.',
      );
    }

    final platform = targetPlatform ?? defaultTargetPlatform;
    final keys = modelKeys ?? modelKeysForPlatform(platform);
    if (keys.isEmpty) {
      throw EmotionProvisioningException(
        'missing_models',
        'At least one model key is required.',
      );
    }

    if (clearExistingSecrets) {
      await clearSecrets(modelKeys: keys);
    }

    final aad = aadOverride ?? aadForPlatform(platform);
    final results = <EmotionModelProvisioningResult>[];
    for (final key in keys) {
      if (_isUnsupportedPlatformModel(key, platform)) continue;
      final payload = await _fetchCompletePayload(
        modelKey: key,
        aad: aad.isEmpty ? null : aad,
        platform: _platformName(platform),
      );
      if (payload == null) continue;
      results.add(
        await _provisionModel(
          modelKey: key,
          payload: payload,
          platform: platform,
          warmUp: warmUp,
        ),
      );
    }

    if (results.isEmpty) {
      throw EmotionProvisioningException(
        'provisioning_empty',
        'No model secrets were returned by the backend.',
      );
    }

    final out = EmotionProvisioningResult(
      models: results,
      status: _statusFor(results),
    );
    if (!out.isReady) {
      throw EmotionProvisioningException(
        'missing_user_code',
        'Backend responses did not include userCodeB64/userSecretB64.',
      );
    }
    return out;
  }

  Future<void> clearSecrets({List<String>? modelKeys}) async {
    final keys = modelKeys ?? _modelKeys;
    for (final modelKey in keys) {
      for (final id in allModelIds(modelKey)) {
        await UserCodeChannel.clearUserCode(_userName, modelId: id);
        await ModelRuntime.clearKeyShard(id);
        await ModelRuntime.clearModelLicense(id);
      }
    }
    await UserCodeChannel.clearUserCode(_userName);
  }

  Future<Map<String, dynamic>?> _fetchCompletePayload({
    required String modelKey,
    required String platform,
    String? aad,
  }) async {
    final response = await CekSecretClient.fetchCekSecret(
      apiKeyId: _sdkKeyId,
      apiKeySecret: _sdkKeySecret,
      modelKey: modelKey,
      aad: aad,
      overrideBaseUrl: (_serverBaseUrl == null || _serverBaseUrl.isEmpty)
          ? null
          : _serverBaseUrl,
      client: _client,
    );
    if (response == null) return null;

    final payload = Map<String, dynamic>.from(response);
    final existingLicense =
        CekSecretUtils.extractLicense(payload, modelKey: modelKey);
    if (existingLicense != null && existingLicense.isNotEmpty) {
      return payload;
    }

    final modelIdForLicense =
        CekSecretUtils.extractModelKey(payload) ?? modelKey;
    final fetchedLicense = await CekSecretClient.fetchModelLicense(
      apiKeyId: _sdkKeyId,
      apiKeySecret: _sdkKeySecret,
      modelId: modelIdForLicense,
      platform: platform,
      overrideBaseUrl: (_serverBaseUrl == null || _serverBaseUrl.isEmpty)
          ? null
          : _serverBaseUrl,
      client: _client,
    );
    if (fetchedLicense != null && fetchedLicense.isNotEmpty) {
      payload['license'] = fetchedLicense;
    }
    return payload;
  }

  Future<EmotionModelProvisioningResult> _provisionModel({
    required String modelKey,
    required Map<String, dynamic> payload,
    required TargetPlatform platform,
    required bool warmUp,
  }) async {
    final modelIds = _modelIdsForPayload(modelKey, payload);
    final userCodeB64 = CekSecretUtils.extractUserCode(
      payload,
      modelKey: modelKey,
    );
    var storedUserCodes = 0;
    if (userCodeB64 != null && userCodeB64.isNotEmpty) {
      for (final modelId in modelIds) {
        await UserCodeChannel.saveUserCode(
          userName: _userName,
          userCodeB64: userCodeB64,
          modelId: modelId,
        );
        storedUserCodes++;
      }
    }

    final shardB64 = CekSecretUtils.extractShard(payload, modelKey: modelKey);
    final expiresAtMs =
        CekSecretUtils.extractExpiresAtMs(payload, modelKey: modelKey);
    var storedShards = 0;
    if (shardB64 != null && shardB64.isNotEmpty) {
      for (final modelId in modelIds) {
        await ModelRuntime.setKeyShard(
          modelId: modelId,
          keyShardB64: shardB64,
          expiresAtMs: expiresAtMs,
          userName: _userName,
        );
        storedShards++;
      }
    }

    final license = CekSecretUtils.extractLicense(payload, modelKey: modelKey);
    var storedLicenses = 0;
    if (license != null && license.isNotEmpty) {
      for (final modelId in modelIds) {
        await ModelRuntime.setModelLicense(modelId: modelId, license: license);
        storedLicenses++;
      }
    }

    var warmedModels = 0;
    if (warmUp && platform == TargetPlatform.android) {
      for (final modelId in modelIds) {
        if (await ModelRuntime.warmUp(modelId)) {
          warmedModels++;
        }
      }
    }

    return EmotionModelProvisioningResult(
      modelKey: modelKey,
      modelIds: modelIds,
      storedUserCodes: storedUserCodes,
      storedShards: storedShards,
      storedLicenses: storedLicenses,
      warmedModels: warmedModels,
    );
  }

  Set<String> _modelIdsForPayload(
    String modelKey,
    Map<String, dynamic> payload,
  ) {
    final ids = <String>{...allModelIds(modelKey)};
    final payloadModelId = payload['modelId'] ?? payload['model_id'];
    if (payloadModelId is String && payloadModelId.trim().isNotEmpty) {
      ids.add(payloadModelId.trim());
    }
    final license = CekSecretUtils.extractLicense(payload, modelKey: modelKey);
    final licenseModelId = license?['modelId'];
    if (licenseModelId is String && licenseModelId.trim().isNotEmpty) {
      ids.add(licenseModelId.trim());
    }
    return ids;
  }

  bool _isUnsupportedPlatformModel(String modelKey, TargetPlatform platform) {
    return platform == TargetPlatform.android &&
        (modelKey == 'aih_fer20250115' || modelKey == 'aih_fer');
  }

  String _platformName(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      default:
        return 'ios';
    }
  }

  String _statusFor(List<EmotionModelProvisioningResult> models) {
    final result = EmotionProvisioningResult(models: models, status: '');
    final shardText = result.storedShards > 0
        ? 'shards stored (${result.storedShards})'
        : 'no shards in responses';
    return 'User codes stored (${result.storedUserCodes}); $shardText; '
        'licenses stored (${result.storedLicenses})';
  }

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
}

const Map<String, String> _modelAccountIds = <String, String>{
  'aih_fer': 'aih_fer_v2025-01-15-shard',
  'aih_fer20250115': 'aih_fer_v2025-01-15-shard',
  defaultEmotionModelKey: defaultEmotionModelKey,
  'mobilenetv1_fer': 'mobilenetv1_fer_v2024-11-06-08-48-50-shard',
  'mobilenetv1_fer2024-11-06-08-48-50':
      'mobilenetv1_fer_v2024-11-06-08-48-50-shard',
};
