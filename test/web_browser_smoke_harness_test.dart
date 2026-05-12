import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web browser smoke harness documents required browser gates', () {
    final doc = File('docs/web-browser-smoke-harness.md').readAsStringSync();

    expect(doc, contains('`localhost` or HTTPS'));
    expect(doc, contains('hosted inference stub'));
    expect(doc, contains('camera permission'));
    expect(doc, contains('first video frame'));
    expect(doc, contains('label-to-score map'));
    expect(doc, contains('camera permission-to-first-frame time'));
    expect(doc, contains('inference call latency'));
    expect(doc, contains('assetAuditPassed'));
    expect(
      doc,
      contains('without bundled\nproduction model assets'),
    );
  });

  test('web browser smoke harness keeps production model assets forbidden', () {
    final doc = File('docs/web-browser-smoke-harness.md').readAsStringSync();

    for (final extension in const [
      '.enc',
      '.onnx',
      '.tflite',
      '.wasm',
    ]) {
      expect(doc, contains(extension));
    }
    expect(doc, contains('Keep production'));
    expect(
      doc,
      contains('Core ML assets out\n  of `example/web`'),
    );
  });
}
