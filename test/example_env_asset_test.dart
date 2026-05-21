import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('example env handling', () {
    test('does not bundle local env secrets as Flutter assets', () {
      final pubspec = File('example/pubspec.yaml').readAsStringSync();

      expect(pubspec,
          isNot(contains(RegExp(r'^\s*-\s+\.env\s*$', multiLine: true))));
      expect(pubspec,
          isNot(contains(RegExp(r'^\s*-\s+env\s*$', multiLine: true))));
    });

    test('keeps optional dotenv load guarded in the example app', () {
      final main = File('example/lib/main.dart').readAsStringSync();

      expect(main, contains("_loadLocalEnvFileIfPresent()"));
      expect(main, contains("_loadNativeProcessEnvironmentIfPresent()"));
      expect(main, contains("'getProcessEnvironment'"));
      expect(main, contains("'example/env'"));
    });
  });
}
