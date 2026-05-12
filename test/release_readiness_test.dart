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
    expect(doc, contains('Local iOS Build Smoke'));
    expect(doc, contains('flutter build ios --debug --no-codesign'));
    expect(doc, contains('Local Android Build Smoke'));
    expect(doc, contains('flutter build apk --debug'));
    expect(doc, contains('./gradlew :emotion_detection:testDebugUnitTest'));
    expect(doc, contains('Web | Evaluation only'));
    expect(doc, contains('distribution is no-go'));
  });

  test('example app declares an iOS build version', () {
    final pubspec = File('example/pubspec.yaml').readAsStringSync();

    expect(pubspec,
        contains(RegExp(r'^version: \d+\.\d+\.\d+\+\d+$', multiLine: true)));
  });
}
