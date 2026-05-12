---
read_when:
  - Moving Flutter plugin behavior into native SDK wrappers.
  - Deciding whether code belongs in shared runtime or platform adapters.
  - Planning Phase 1 or later native SDK migration work.
---

# Native SDK Inventory

## Current Surfaces

- Flutter API: `lib/emotion_detection.dart`, `lib/emotion_detector_view.dart`.
- Flutter native channels: `lib/native/model_runtime.dart`,
  `lib/native/user_code_channel.dart`.
- Apple plugin/runtime: `ios/Classes/` and `macos/Classes/`.
- Apple encrypted model flow: `ios/Classes/Encryption/`.
- Android plugin/runtime: `android/src/main/kotlin/com/tartalabs/emotiondetection/`.
- Android crypto/storage: `android/src/main/kotlin/com/tartalabs/crypto/`.
- Windows plugin scaffold: `windows/`.
- Web stub: `lib/emotion_detection_web.dart`.

## Target Ownership

- Shared C ABI: `native/include/emotion_sdk.h`.
- Shared runtime core: manifest parsing, model registry, crypto verification,
  decrypt/load/warmup/predict/unload lifecycle.
- Platform adapters: secure storage, camera frames, face detection, permission
  handling, packaging, and logs.
- Flutter wrapper: Dart API and widgets calling platform SDKs.

## Migration Notes

- Keep Flutter public API stable until wrapper parity exists.
- Move crypto behavior behind shared tests before deleting Swift or Kotlin
  implementations.
- Prefer model label indices in the C ABI; wrappers can map labels into native
  strings from the manifest.
- Add tests in the same phase that introduces each contract, parser, runtime, or
  platform wrapper.
