import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple podspecs bundle exp15 encrypted Core ML assets', () {
    final iosPodspec = File('ios/emotion_detection.podspec').readAsStringSync();
    final macosPodspec =
        File('macos/emotion_detection.podspec').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    for (final source in [iosPodspec, macosPodspec, pubspec]) {
      expect(source, contains('aih_exp15_float16.enc'));
      expect(source, contains('aih_exp15_float16.manifest.json'));
    }
    for (final source in [pubspec]) {
      expect(source, contains('ios/Assets/aih_exp15_float16.enc'));
      expect(source, contains('ios/Assets/aih_exp15_float16.manifest.json'));
    }
  });

  test('exp15 Core ML preprocessing uses pixel_values ImageNet NCHW input', () {
    final source = File(
      'macos/Classes/CoreMLImageNetEmotionModel.swift',
    ).readAsStringSync();

    expect(source, contains('pixel_values'));
    expect(
        source,
        contains('shape: [1, 3, NSNumber(value: targetHeight), '
            'NSNumber(value: targetWidth)]'));
    expect(source, contains('(0.485, 0.456, 0.406)'));
    expect(source, contains('(0.229, 0.224, 0.225)'));
    expect(source, contains('ptr[channelSize + base] = g'));
    expect(source, contains('inferenceMs=%.2f'));
  });

  test('macOS loader can find local exp15 assets during Xcode debug runs', () {
    final source =
        File('macos/Classes/EmotionDetectionPlugin.swift').readAsStringSync();

    expect(source, contains('developmentAssetURL'));
    expect(
        source, contains('appendingPathComponent("ios", isDirectory: true)'));
    expect(source,
        contains('appendingPathComponent("Assets", isDirectory: true)'));
  });

  test('macOS camera events are emitted on the Flutter platform thread', () {
    final source =
        File('macos/Classes/EmotionDetectionPlugin.swift').readAsStringSync();

    expect(source, contains('private func emitCameraEvent(_ event: Any)'));
    expect(source, contains('if Thread.isMainThread'));
    expect(source, contains('DispatchQueue.main.async { [weak self] in'));
    expect(RegExp(r'cameraEventSink\?\(').allMatches(source), hasLength(2));
  });
}
