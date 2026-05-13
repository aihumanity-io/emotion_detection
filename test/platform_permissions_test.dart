import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android example declares camera permission and feature', () {
    final manifest = File('example/android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(manifest, contains('android.permission.CAMERA'));
    expect(manifest, contains('android.hardware.camera.any'));
  });

  test('Apple examples declare camera usage and macOS camera entitlement', () {
    final iosInfo = File('example/ios/Runner/Info.plist').readAsStringSync();
    final macosInfo =
        File('example/macos/Runner/Info.plist').readAsStringSync();
    final debugEntitlements =
        File('example/macos/Runner/DebugProfile.entitlements')
            .readAsStringSync();
    final releaseEntitlements =
        File('example/macos/Runner/Release.entitlements').readAsStringSync();

    expect(iosInfo, contains('NSCameraUsageDescription'));
    expect(macosInfo, contains('NSCameraUsageDescription'));
    expect(debugEntitlements, contains('com.apple.security.device.camera'));
    expect(releaseEntitlements, contains('com.apple.security.device.camera'));
  });

  test('permission setup is documented for supported Flutter platforms', () {
    final readme = File('README.md').readAsStringSync();
    final apiDocs = File('APIDocumentation.md').readAsStringSync();

    for (final doc in [readme, apiDocs]) {
      expect(doc, contains('android.permission.CAMERA'));
      expect(doc, contains('NSCameraUsageDescription'));
      expect(doc, contains('com.apple.security.device.camera'));
    }
  });
}
