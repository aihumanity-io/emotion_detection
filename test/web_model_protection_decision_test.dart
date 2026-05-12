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
}
