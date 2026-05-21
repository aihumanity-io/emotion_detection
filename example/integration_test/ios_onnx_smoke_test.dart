import 'package:emotion_detection/emotion_detection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String _defaultModelKey =
    'aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx';
const MethodChannel _channel = MethodChannel('face_emotion_detection');

const String _sdkKeyIdFromDefine =
    String.fromEnvironment('SDK_KEY_ID', defaultValue: '');
const String _sdkKeySecretFromDefine =
    String.fromEnvironment('SDK_KEY_SECRET', defaultValue: '');
const String _exampleUserNameFromDefine =
    String.fromEnvironment('EXAMPLE_USER_NAME', defaultValue: '');
const String _exampleServerBaseUrlFromDefine =
    String.fromEnvironment('EXAMPLE_SERVER_BASE_URL', defaultValue: '');
const String _exampleModelKeyFromDefine =
    String.fromEnvironment('EXAMPLE_MODEL_KEY', defaultValue: '');
const String _exampleModelAadFromDefine =
    String.fromEnvironment('EXAMPLE_MODEL_AAD', defaultValue: '');
const String _exampleModelAadIosFromDefine =
    String.fromEnvironment('EXAMPLE_MODEL_AAD_IOS', defaultValue: '');
const String _exampleModelAadMacosFromDefine =
    String.fromEnvironment('EXAMPLE_MODEL_AAD_MACOS', defaultValue: '');
const String _exampleModelAadAndroidFromDefine =
    String.fromEnvironment('EXAMPLE_MODEL_AAD_ANDROID', defaultValue: '');

Map<String, String> _safeDotenvEnv() {
  try {
    return dotenv.env;
  } catch (_) {
    return <String, String>{};
  }
}

String _pickValue(
    String fromDefine, Map<String, String> dotenvEnv, String key) {
  final defineValue = fromDefine.trim();
  if (defineValue.isNotEmpty) return defineValue;
  return (dotenvEnv[key] ?? '').trim();
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
      await dotenv.load(fileName: 'env');
    } catch (_) {}
    final env = _safeDotenvEnv();

    final preferredModelKey = _exampleModelKeyFromDefine.trim().isNotEmpty
        ? _exampleModelKeyFromDefine.trim()
        : _defaultModelKey;
    final provisioner = EmotionDetectionProvisioner(
      sdkKeyId: _pickValue(_sdkKeyIdFromDefine, env, 'SDK_KEY_ID'),
      sdkKeySecret: _pickValue(_sdkKeySecretFromDefine, env, 'SDK_KEY_SECRET'),
      serverBaseUrl: _pickValue(
        _exampleServerBaseUrlFromDefine,
        env,
        'EXAMPLE_SERVER_BASE_URL',
      ),
      userName:
          _pickValue(_exampleUserNameFromDefine, env, 'EXAMPLE_USER_NAME'),
      modelKey: preferredModelKey,
      modelKeys: <String>[preferredModelKey],
      aad: _pickValue(_exampleModelAadFromDefine, env, 'EXAMPLE_MODEL_AAD'),
      iosAad: _pickValue(
          _exampleModelAadIosFromDefine, env, 'EXAMPLE_MODEL_AAD_IOS'),
      macosAad: _pickValue(
        _exampleModelAadMacosFromDefine,
        env,
        'EXAMPLE_MODEL_AAD_MACOS',
      ),
      androidAad: _pickValue(
        _exampleModelAadAndroidFromDefine,
        env,
        'EXAMPLE_MODEL_AAD_ANDROID',
      ),
    );

    if (!provisioner.hasRequiredConfig) {
      debugPrint('Skipping iOS smoke test: missing SDK_KEY_ID/SDK_KEY_SECRET.');
      return;
    }

    final result = await provisioner.provision(
      targetPlatform: defaultTargetPlatform,
      aadOverride: provisioner.aadForPlatform(defaultTargetPlatform),
      modelKeys: <String>[preferredModelKey],
      clearExistingSecrets: true,
      warmUp: false,
    );
    expect(result.isReady, true, reason: result.status);

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
