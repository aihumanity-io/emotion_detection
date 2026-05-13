import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter CI workflow runs release gate commands', () {
    final workflow = File('.github/workflows/flutter.yml').readAsStringSync();

    expect(workflow, contains('actions/checkout@v4'));
    expect(workflow, contains('subosito/flutter-action@v2'));
    expect(workflow, contains('flutter pub get'));
    expect(workflow, contains('flutter test'));
    expect(workflow, contains('flutter analyze'));
    expect(workflow, contains('flutter pub publish --dry-run'));
    expect(workflow, contains('native:'));
    expect(workflow, contains('working-directory: native'));
    expect(workflow, contains('cmake --preset host-release'));
    expect(
        workflow, contains('cmake --build --preset host-release --parallel'));
    expect(workflow, contains('ctest --preset host-release'));
    expect(workflow, contains('native-windows:'));
    expect(workflow, contains('windows-latest'));
    expect(workflow, contains('Visual Studio 17 2022'));
    expect(workflow, contains('build/native-windows'));
    expect(workflow, contains('-DEMOTION_SDK_BUILD_TESTS=ON'));
    expect(workflow, contains('-DEMOTION_SDK_BUILD_INSTALLABLE=ON'));
    expect(workflow, contains('-DEMOTION_ENABLE_ONNX_RUNTIME=OFF'));
    expect(
        workflow, contains('ctest --test-dir build/native-windows -C Release'));
    expect(workflow, contains('"codex/**"'));
  });
}
