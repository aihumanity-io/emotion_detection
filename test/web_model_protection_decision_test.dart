import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web model protection decision keeps production web gated', () {
    final doc =
        File('doc/web-model-protection-decision.md').readAsStringSync();

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
    final files = _webSampleFiles();

    final bundledModels = files.where(_isModelAsset).toList();

    expect(bundledModels, isEmpty);
  });

  test('web sample source shell stays within baseline budget', () {
    final doc = File('doc/web-performance-baseline.md').readAsStringSync();
    final budget = _readBudget(doc);
    final sourceShellBytes = _webSampleFiles()
        .map((path) => File(path).lengthSync())
        .fold<int>(0, (total, bytes) => total + bytes);

    expect(doc, contains('Current source-shell bytes:'));
    expect(doc, contains('flutter build web --release'));
    expect(doc, contains('Camera permission-to-first-frame time'));
    expect(sourceShellBytes, lessThanOrEqualTo(budget));
  });
}

List<String> _webSampleFiles() {
  final webDir = Directory('example/web');
  return webDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path)
      .where(
          (path) => !path.split(Platform.pathSeparator).last.startsWith('._'))
      .toList()
    ..sort();
}

int _readBudget(String doc) {
  final match = RegExp(r'Source shell budget: (\d+) bytes\.').firstMatch(doc);
  if (match == null) {
    throw StateError('Missing source shell budget in web baseline doc.');
  }
  return int.parse(match.group(1)!);
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
