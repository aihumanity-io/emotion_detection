import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release tag checklist documents version, local, CI, and smoke gates',
      () {
    final doc = File('doc/release-tag-checklist.md').readAsStringSync();

    expect(doc, contains('pubspec.yaml'));
    expect(doc, contains('CHANGELOG.md'));
    expect(doc, contains('doc/release-readiness.md'));
    expect(doc, contains('flutter test'));
    expect(doc, contains('flutter analyze'));
    expect(doc, contains('flutter pub publish --dry-run'));
    expect(doc, contains('cmake --preset host-release'));
    expect(doc, contains('ctest --preset host-release'));
    expect(doc, contains('gh run list --workflow Flutter'));
    expect(doc, contains('Native Windows job is green'));
    expect(doc, contains('emotion_windows_secure_store_test'));
    expect(doc, contains('DPAPI secure-store behavior'));
    expect(doc, contains('Platform Smoke Gate'));
    expect(doc, contains('git tag v<version>'));
    expect(doc, contains('git push origin v<version>'));
  });
}
