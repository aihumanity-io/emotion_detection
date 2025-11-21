# Repository Guidelines

## Project Structure & Module Organization
The Flutter plugin source lives in `lib/`, with `emotion_detection.dart` exposing the public API and platform channels. Maintain platform shims under `android/`, `ios/`, `macos/`, and `windows/`, mirroring existing directory names to avoid conditional imports. Use `example/lib/main.dart` as the manual playground whenever functionality changes, and log any new API steps in `APIDocumentation.md`. Tests belong in `test/` and should reflect the structure of `lib/` so files remain easy to locate.

## Build, Test, and Development Commands
Run `flutter pub get` after editing `pubspec.yaml` to refresh dependencies. Use `flutter analyze` to enforce lint rules in `analysis_options.yaml`. Execute `flutter test` (or `flutter test --coverage` for reports) before every PR. Validate manual flows via `cd example && flutter run` on at least one target device. When updating native code, rebuild with `flutter build apk`, `flutter build ios`, or the relevant desktop target.

## Coding Style & Naming Conventions
Follow Dart two-space indentation and keep lines under 100 characters. Public classes use UpperCamelCase and members use lowerCamelCase; private members are prefixed with `_`. Prefer `final` for local variables, use explicit types, and favor guard clauses instead of deep nesting. Run `dart format lib test example` before submitting patches, and address any analyzer warnings immediately.

## Testing Guidelines
Write deterministic tests with `flutter_test` or `package:test` for every feature or regression fix. Name files `<feature>_test.dart`, group scenarios with `group()` descriptions that mirror the API, and assert behavior rather than UI snapshots. Store reusable fixtures in `test/resources/`. Keep coverage trending upward (≥80% for new code) and mention any gaps in the PR description.

## Commit & Pull Request Guidelines
Use Conventional Commits (e.g., `feat: add arousal scores`) limited to ~72 characters. PRs must summarize changes, link related issues, list commands run (`flutter analyze`, `flutter test`, etc.), and attach screenshots or recordings for UI or example updates. Note platform-specific adjustments in `README.md`, especially when native manifests or entitlements change. Keep each PR focused; split large Dart/native work into dedicated submissions when necessary.

## Security & Configuration Tips
Never commit API keys or proprietary model weights; use platform keychains or runtime configuration files ignored by VCS. Confirm camera permissions in `Info.plist`, `AndroidManifest.xml`, and desktop entitlements before distributing builds. Communicate credential rotation steps in the PR when touching remote services, and prefer HTTPS endpoints for any external frame streaming.
