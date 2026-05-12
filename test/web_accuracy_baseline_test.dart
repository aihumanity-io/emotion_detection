import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web accuracy baseline documents native comparison contract', () {
    final doc = File('doc/web-accuracy-baseline.md').readAsStringSync();

    expect(doc, contains('native/tests/resources/sample_rgb.ppm'));
    expect(doc, contains('ONNX runtime output from the shared native SDK'));
    expect(doc, contains('model manifest input shape'));
    expect(doc, contains('Top label must match'));
    expect(doc, contains('0.05'));
    expect(doc, contains('0.03'));
    expect(doc, contains('scoreSum'));
    expect(doc, contains('maxPerLabelDrift'));
    expect(doc, contains('topLabelScoreDrift'));
  });

  test('web accuracy baseline includes the full emotion label set', () {
    final doc = File('doc/web-accuracy-baseline.md').readAsStringSync();

    for (final label in const [
      'Anger',
      'Disgust',
      'Fear',
      'Happiness',
      'Neutral',
      'Sadness',
      'Surprise',
    ]) {
      expect(doc, contains('- `$label`'));
    }
  });

  test('web accuracy baseline fixture exists', () {
    expect(File('native/tests/resources/sample_rgb.ppm').existsSync(), isTrue);
  });
}
