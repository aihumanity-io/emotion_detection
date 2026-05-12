import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web model protection decision keeps production web gated', () {
    final doc =
        File('docs/web-model-protection-decision.md').readAsStringSync();

    expect(doc, contains('Status: no-go'));
    expect(doc, contains('client-side production model distribution'));
    expect(doc, contains('Hosted inference'));
    expect(doc, contains('business explicitly accepts client-side extraction'));
    expect(doc, contains('Accuracy comparison against native ONNX baseline'));
    expect(doc, contains('Browser smoke test'));
    expect(doc, contains('Bundle size and load-time report'));
    expect(doc, contains('production encrypted models are not bundled'));
  });

  test('web sample does not bundle production model assets', () {
    final webDir = Directory('example/web');
    final files = webDir
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .where(
            (path) => !path.split(Platform.pathSeparator).last.startsWith('._'))
        .toList()
      ..sort();

    final bundledModels = files.where(_isModelAsset).toList();

    expect(bundledModels, isEmpty);
  });
}

bool _isModelAsset(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.enc') ||
      lower.endsWith('.onnx') ||
      lower.endsWith('.tflite') ||
      lower.endsWith('.pt') ||
      lower.endsWith('.pth') ||
      lower.endsWith('.mlmodel') ||
      lower.endsWith('.mlmodelc') ||
      lower.endsWith('.wasm');
}
