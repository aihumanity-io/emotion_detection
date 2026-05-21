import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web hosted inference contract defines request and response shape', () {
    final doc =
        File('doc/web-hosted-inference-contract.md').readAsStringSync();

    for (final requiredText in const [
      'POST',
      '/sdk/web/infer',
      'HTTPS only',
      'publishable SDK key',
      'never the\n  SDK secret',
      '`requestId`',
      '`modelId`',
      '`image.dataB64`',
      '`image.width`',
      '`image.height`',
      '`client.origin`',
      '`scores`',
      '`topLabel`',
      '`timingMs.total`',
      '`roundTripMs`',
    ]) {
      expect(doc, contains(requiredText));
    }
  });

  test('web hosted inference contract forbids secrets and model material', () {
    final doc =
        File('doc/web-hosted-inference-contract.md').readAsStringSync();

    for (final forbiddenText in const [
      'SDK secret',
      'User code',
      'CEK',
      'shard',
      'plaintext model bytes',
      '.enc',
      '.onnx',
      '.tflite',
      '.wasm',
    ]) {
      expect(doc, contains(forbiddenText));
    }
  });

  test('web hosted inference contract pins score validation rules', () {
    final doc =
        File('doc/web-hosted-inference-contract.md').readAsStringSync();

    expect(doc, contains('finite numbers between `0.0` and `1.0`'));
    expect(doc, contains('within `0.01` of `1.0`'));
    expect(doc, contains('`topLabel` must exist in `scores`'));
    expect(doc, contains('structured error code and message'));
  });
}
