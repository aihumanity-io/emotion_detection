import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const modelAssetRoots = [
    'ios/Assets',
    'example/android/app/src/main/assets',
    'example/web',
  ];

  test('production model asset roots do not contain plaintext model binaries',
      () {
    const blockedExtensions = {'.onnx', '.pb', '.tflite', '.tfl'};

    final blockedFiles = <String>[];
    for (final rootPath in modelAssetRoots) {
      final root = Directory(rootPath);
      if (!root.existsSync()) {
        continue;
      }
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        final path = entity.path.toLowerCase();
        if (blockedExtensions.any(path.endsWith)) {
          blockedFiles.add(entity.path);
        }
      }
    }

    expect(blockedFiles, isEmpty);
  });

  test('encrypted model payloads stay within accepted release size', () {
    const maxEncryptedPayloadBytes = 40 * 1024 * 1024;

    for (final path in [
      'ios/Assets/aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx.enc',
      'example/android/app/src/main/assets/'
          'aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx.enc',
    ]) {
      final file = File(path);

      expect(file.existsSync(), isTrue, reason: path);
      expect(file.lengthSync(), lessThanOrEqualTo(maxEncryptedPayloadBytes),
          reason: path);
    }
  });

  test('encrypted model manifests match packaged payload lengths', () {
    for (final root in ['ios/Assets', 'example/android/app/src/main/assets']) {
      final manifest = File(
        '$root/aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx.manifest.json',
      );
      final payload = File(
        '$root/aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx.enc',
      );

      final manifestJson =
          jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;

      expect(manifestJson['algo'], 'AES-256-GCM');
      expect(manifestJson['ciphertextLen'], payload.lengthSync());
      expect(manifestJson['wrap'], isA<Map<String, Object?>>());
    }
  });

  test('encrypted model payloads and native fixtures are checked out binary',
      () {
    final attributes = File('.gitattributes').readAsStringSync();

    expect(attributes, contains('*.enc binary'));
    expect(attributes, contains('*.onnx binary'));
    expect(attributes, contains('*.pb binary'));
    expect(attributes, contains('*.ppm binary'));
  });
}
