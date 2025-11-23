import 'package:emotion_detection/emotion_detection.dart';

const String _exampleSdkKeyId = String.fromEnvironment(
  'EXAMPLE_SDK_KEY_ID',
  defaultValue: '',
);
const String _exampleSdkKeySecret = String.fromEnvironment(
  'EXAMPLE_SDK_KEY_SECRET',
  defaultValue: '',
);
const String _exampleModelKey = String.fromEnvironment(
  'EXAMPLE_MODEL_KEY',
  defaultValue: 'mobilenetv1_fer2024-11-06-08-48-50',
);
const String _exampleAad = String.fromEnvironment(
  'EXAMPLE_MODEL_AAD',
  defaultValue: 'com.creataai.emotionsdk/ios',
);
const String _exampleOverrideBase = String.fromEnvironment(
  'EXAMPLE_SERVER_BASE_URL',
  defaultValue: 'https://tartalabapi.onrender.com',
);
const String _exampleUserName = String.fromEnvironment(
  'EXAMPLE_USER_NAME',
  defaultValue: 'dev@tartalabs.io',
);

/// Simple wrapper used by the example app to demonstrate
/// how to call [CekSecretClient.fetchCekSecret].
class ExampleSdkSecretModule {
  ExampleSdkSecretModule({
    String? apiKeyId,
    String? apiKeySecret,
    String? modelKey,
    String? aad,
    String? overrideBaseUrl,
    String? userName,
  })  : _apiKeyId = apiKeyId ?? _exampleSdkKeyId,
        _apiKeySecret = apiKeySecret ?? _exampleSdkKeySecret,
        _modelKey = modelKey ?? _exampleModelKey,
        _aad = aad ?? _exampleAad,
        _overrideBaseUrl = overrideBaseUrl ?? _exampleOverrideBase,
        _userName = userName ?? _exampleUserName;

  final String _apiKeyId;
  final String _apiKeySecret;
  final String _modelKey;
  final String _aad;
  final String _overrideBaseUrl;
  final String _userName;

  Future<Map<String, dynamic>?> fetchCekSecret() {
    return CekSecretClient.fetchCekSecret(
      apiKeyId: _apiKeyId,
      apiKeySecret: _apiKeySecret,
      modelKey: _modelKey,
      aad: _aad.isEmpty ? null : _aad,
      overrideBaseUrl: _overrideBaseUrl.isEmpty ? null : _overrideBaseUrl,
    );
  }

  bool get hasRequiredConfig =>
      _apiKeyId.isNotEmpty && _apiKeySecret.isNotEmpty && _modelKey.isNotEmpty;

  String get userName => _userName;

  bool get hasUserName => userName.isNotEmpty;

  String get modelKey => _modelKey;

  String? extractUserCode(Map<String, dynamic> payload) {
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

  String? extractShard(Map<String, dynamic> payload) {
    for (final key in const [
      'cekShardB64',
      'keyShardB64',
      'shardB64',
      'cekShard',
      'cek_shard_b64'
    ]) {
      final value = payload[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  int? extractExpiresAtMs(Map<String, dynamic> payload) {
    for (final key in const ['expiresAt', 'expires_at', 'expiry_epoch_ms']) {
      final value = payload[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
    }
    return null;
  }
}
