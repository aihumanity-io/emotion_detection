import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release readiness documents current SDK release scope', () {
    final doc = File('doc/release-readiness.md').readAsStringSync();

    expect(doc, contains('Status: not ready for a stable public SDK release.'));
    expect(doc, contains('native alpha / release candidate'));
    expect(doc, contains('flutter pub publish --dry-run'));
    expect(doc, contains('Example app smoke on every advertised platform.'));
    expect(doc, contains('Local macOS Build Smoke'));
    expect(doc, contains('CODE_SIGNING_ALLOWED=NO'));
    expect(doc, contains('AppleDouble'));
    expect(doc, contains('Web | Evaluation only'));
    expect(doc, contains('distribution is no-go'));
  });
}
