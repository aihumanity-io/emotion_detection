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
  defaultValue: 'mobilenetv1_fer2024-11-06-08-48-50'
  //defaultValue: '=aih_fer2025',
);
const String _exampleAad = String.fromEnvironment(
  'EXAMPLE_MODEL_AAD',
  defaultValue: 'com.creataai.emotionsdk/ios',
);
const String _exampleOverrideBase = String.fromEnvironment(
  'EXAMPLE_SERVER_BASE_URL',
  defaultValue: 'https://tartalabapi.onrender.com',
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
  })  : _apiKeyId = apiKeyId ?? _exampleSdkKeyId,
        _apiKeySecret = apiKeySecret ?? _exampleSdkKeySecret,
        _modelKey = modelKey ?? _exampleModelKey,
        _aad = aad ?? _exampleAad,
        _overrideBaseUrl = overrideBaseUrl ?? _exampleOverrideBase;

  final String _apiKeyId;
  final String _apiKeySecret;
  final String _modelKey;
  final String _aad;
  final String _overrideBaseUrl;

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
}
