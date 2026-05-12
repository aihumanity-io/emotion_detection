import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final path in <String>[
    'example/ios/Podfile',
    'example/macos/Podfile',
  ]) {
    test('$path strips AppleDouble files before CocoaPods signing', () {
      final podfile = File(path).readAsStringSync();

      expect(podfile, contains('Strip AppleDouble files'));
      expect(podfile, contains('onnxruntime-objc'));
      expect(podfile, contains('COPYFILE_DISABLE=1'));
      expect(podfile, contains('dot_clean -m'));
      expect(podfile, contains("/usr/bin/find \"\$path\" -name '._*'"));
      expect(podfile, contains('add_appledouble_cleanup_phase(target)'));
    });
  }

  test('macOS runner strips AppleDouble files before Flutter embed signing',
      () {
    final project = File(
      'example/macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(project, contains('dot_clean -m'));
    expect(project, contains('COPYFILE_DISABLE=1'));
    expect(project, contains('CODE_SIGNING_REQUIRED=NO'));
    expect(project, contains('/usr/bin/codesign --force'));
    expect(project, contains("/usr/bin/find"));
    expect(project, contains("-name '._*'"));
    expect(project, contains('Strip App AppleDouble files'));
    expect(project, contains(r'TARGET_BUILD_DIR/$WRAPPER_NAME'));
    expect(project, contains('CODE_SIGNING_ALLOWED = NO;'));
    expect(project, contains('BUILT_PRODUCTS_DIR'));
    expect(project, contains('TARGET_BUILD_DIR'));
    expect(project, contains('macos_assemble.sh embed'));
  });
}
