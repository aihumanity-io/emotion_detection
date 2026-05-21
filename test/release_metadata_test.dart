import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec version has a matching changelog entry', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final changelog = File('CHANGELOG.md').readAsStringSync();

    final versionMatch =
        RegExp(r'^version:\s*(\d+\.\d+\.\d+)\s*$', multiLine: true)
            .firstMatch(pubspec);

    expect(versionMatch, isNotNull);
    final version = versionMatch!.group(1)!;

    expect(changelog, contains('## $version'));
  });

  test('example build version tracks package release version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final examplePubspec = File('example/pubspec.yaml').readAsStringSync();

    final packageVersion =
        RegExp(r'^version:\s*(\d+\.\d+\.\d+)\s*$', multiLine: true)
            .firstMatch(pubspec)!
            .group(1)!;

    expect(
        examplePubspec,
        contains(
            RegExp('^version: $packageVersion\\+\\d+\$', multiLine: true)));
  });
}
