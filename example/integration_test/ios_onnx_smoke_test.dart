import 'package:emotion_detection/emotion_detection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String _defaultModelKey =
    'aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx';
const MethodChannel _channel = MethodChannel('face_emotion_detection');

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
    final provisioner = EmotionDetectionProvisioner(
      sdkKeyId: env['SDK_KEY_ID'] ?? '',
      sdkKeySecret: env['SDK_KEY_SECRET'] ?? '',
      serverBaseUrl: env['EXAMPLE_SERVER_BASE_URL'],
      userName: env['EXAMPLE_USER_NAME'] ?? '',
      modelKey: preferredModelKey,
      modelKeys: <String>[preferredModelKey],
      aad: env['EXAMPLE_MODEL_AAD'],
      iosAad: env['EXAMPLE_MODEL_AAD_IOS'],
      macosAad: env['EXAMPLE_MODEL_AAD_MACOS'],
      androidAad: env['EXAMPLE_MODEL_AAD_ANDROID'],
    );

    expect(
      provisioner.hasRequiredConfig,
      true,
      reason: 'Missing SDK_KEY_ID/SDK_KEY_SECRET.',
    );

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
