import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Gradle Kotlin plugin versions meet Flutter support floor', () {
    final pluginGradle = File('android/build.gradle').readAsStringSync();
    final exampleGradle =
        File('example/android/build.gradle').readAsStringSync();
    final exampleSettings =
        File('example/android/settings.gradle').readAsStringSync();

    expect(pluginGradle, contains('ext.kotlin_version = "2.1.0"'));
    expect(exampleGradle, contains("ext.kotlin_version = '2.1.0'"));
    expect(exampleSettings,
        contains('id "org.jetbrains.kotlin.android" version "2.1.0"'));
    expect(pluginGradle, isNot(contains('1.8.22')));
    expect(exampleGradle, isNot(contains('1.9.0')));
    expect(exampleSettings, isNot(contains('1.8.22')));
  });
}
