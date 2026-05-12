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

  test('Android example strips AppleDouble files before resource parsing', () {
    final gradle = File('example/android/app/build.gradle').readAsStringSync();

    expect(gradle, contains(r'strip${variantName}AppleDoubleResources'));
    expect(
        gradle, contains(r'strip${variantName}AppleDoubleAssetsBeforeClean'));
    expect(gradle, contains(r'strip${variantName}AppleDoubleAssetsAfterMerge'));
    expect(gradle, contains('parse'));
    expect(gradle, contains('LocalResources'));
    expect(gradle, contains(r'cleanMerge${variantName}Assets'));
    expect(gradle, contains(r'compress${variantName}Assets'));
    expect(gradle, contains(r'package${variantName}Resources'));
    expect(gradle, contains('eachFileRecurse'));
    expect(gradle, contains('startsWith("._")'));
  });

  test('Android plugin strips AppleDouble files before resource parsing', () {
    final gradle = File('android/build.gradle').readAsStringSync();

    expect(gradle, contains(r'strip${variantName}AppleDoubleResources'));
    expect(gradle, contains(r'parse${variantName}LocalResources'));
    expect(gradle, contains(r'package${variantName}Resources'));
    expect(gradle, contains('packaged_res'));
    expect(gradle, contains('eachFileRecurse'));
    expect(gradle, contains('startsWith("._")'));
  });

  test('Android example configures AppleDouble cleanup for all subprojects',
      () {
    final gradle = File('example/android/build.gradle').readAsStringSync();

    expect(gradle, contains('configureAppleDoubleCleanup'));
    expect(gradle,
        contains('subproject.plugins.hasPlugin("com.android.application")'));
    expect(gradle,
        contains('subproject.plugins.hasPlugin("com.android.library")'));
    expect(gradle, contains(r'parse${variantName}LocalResources'));
    expect(gradle, contains(r'cleanMerge${variantName}Assets'));
    expect(gradle, contains(r'compress${variantName}Assets'));
    expect(
        gradle,
        contains(
            r'strip${variantName}AppleDoubleProcessedResourcesBeforeProcess'));
    expect(gradle, contains(r'process${variantName}Resources'));
    expect(gradle, contains('linked_resources_binary_format'));
    expect(gradle, contains(r'bundleLibCompileToJar${variantName}'));
    expect(gradle, contains(r'bundleLibRuntimeToJar${variantName}'));
    expect(gradle, contains(r'bundleLibRuntimeToDir${variantName}'));
    expect(
        gradle, contains(r'strip${variantName}AppleDoubleDexInputsBeforeDex'));
    expect(gradle,
        contains(r'strip${variantName}AppleDoubleDexArchivesBeforeMerge'));
    expect(gradle, contains(r'dexBuilder${variantName}'));
    expect(gradle, contains(r'mergeProjectDex${variantName}'));
    expect(gradle, contains(r'mergeLibDex${variantName}'));
    expect(gradle, contains(r'mergeExtDex${variantName}'));
    expect(
        gradle, contains(r'stripAppleDoubleFiles("${rootProject.buildDir}")'));
    expect(gradle,
        contains(r'stripAppleDoubleFiles("${androidProject.buildDir}")'));
    expect(gradle, contains('eachFileRecurse'));
    expect(gradle, contains('startsWith("._")'));
  });
}
