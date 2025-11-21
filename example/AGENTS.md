# Repository Guidelines

## Project Structure & Module Organization
This Flutter sample centers on `lib/main.dart`, which wires the `emotion_detection` plugin into the demo UI. Group any new feature logic inside `lib/` using feature folders (e.g., `lib/emotion/recognizer.dart`) so widget code stays isolated from platform channels. Widget tests mirror sources under `test/` (current example: `test/widget_test.dart`). Device-driven scenarios belong in `integration_test/`, starting from `integration_test/plugin_integration_test.dart`. Platform-specific shims reside in `android/`, `ios/`, `macos/`, `windows/`, and `web/`; edit them only when tweaking native permissions or build flavors. Keep tooling configs (`pubspec.yaml`, `analysis_options.yaml`) and assets at the repository root for easy CI access.

## Build, Test & Development Commands
- `flutter pub get` — installs packages declared in `pubspec.yaml`.
- `flutter run -d <device-id>` — launches the app on an emulator, browser, or attached device.
- `flutter analyze` — runs static analysis with the lints defined in `analysis_options.yaml`.
- `flutter test` — executes the Dart unit/widget suite under `test/`.
- `flutter test integration_test --device-id <device-id>` — runs integration tests end-to-end on a target device or browser.
- `flutter build apk --release` (or `ipa`, `macos`, `windows`, `web`) — produces optimized artifacts for manual verification.

## Coding Style & Naming Conventions
Adhere to the rules from `package:flutter_lints`; prefer two-space indentation and keep lines ≤100 characters. Format changed files via `flutter format lib test integration_test`. Name classes and widgets with `UpperCamelCase`, methods and variables with `lowerCamelCase`, and files with `snake_case.dart`. Keep emotion-specific constants or channel names in dedicated files such as `lib/emotion/constants.dart` to avoid scattering literals.

## Testing Guidelines
Every new widget or helper should have a corresponding test under `test/feature_name/`, using descriptive `*_test.dart` names. Use `flutter test --coverage` locally when touching plugin bindings, and ensure key emotion paths reach assertions or golden checks. Integration flows should reset plugin state between cases and log device metadata in the test description. Failures reproduced manually must be encoded as regression tests before merging.

## Commit & Pull Request Guidelines
Follow Conventional Commits (e.g., `feat: wire emotion cards`, `fix: debounce detector stream`) written in the imperative present tense with subjects ≤72 characters. Reference related issue IDs in the body and summarize validation steps (`flutter analyze`, `flutter test`, device + OS). Pull requests should include a brief motivation, screenshots or logs of detector output when UI changes occur, and note any platform-specific setup updates so reviewers can reproduce results quickly.
