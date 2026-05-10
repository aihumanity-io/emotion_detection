---
read_when:
  - Planning native SDK work beyond Flutter.
  - Changing model packaging, encryption, runtime ABI, or platform wrappers.
  - Adding iOS, macOS, Android, Windows, Linux, Raspberry Pi, or Web SDKs.
---

# Native SDK Plan

## Goal

Make Flutter one SDK consumer instead of the only SDK surface. Build a shared
runtime that can ship through native SDKs for Apple, Android, Windows, Linux,
Raspberry Pi, and eventually Web.

## Current State

- Flutter exposes the public Dart API and camera widget.
- iOS and macOS use Swift plugin/runtime code.
- Android uses Kotlin/Java plugin/runtime code.
- Windows has C/C++ plugin scaffolding.
- Linux is not implemented.
- Web is a lightweight platform stub.
- Apple already uses encrypted ONNX assets and manifest-driven decryption.
- Android has license/key storage primitives, but the runtime is separate from
  the Apple implementation.

## Target Architecture

```text
apps / samples
  |
platform SDKs
  |-- Swift SDK: iOS, macOS
  |-- Kotlin/Java SDK: Android
  |-- C/C++ SDK: Windows, Linux, Raspberry Pi
  |-- Dart wrapper: Flutter
  |-- JS/WASM SDK: Web, last phase
  |
shared runtime contract
  |-- C ABI: stable boundary for non-web platforms
  |-- manifest parser
  |-- model registry
  |-- key/shard/license state
  |-- decrypt/load/warmup/predict/unload
  |
platform adapters
  |-- secure storage
  |-- camera/frame sources
  |-- face detection
  |-- accelerator/provider selection
  |
model runtimes
  |-- ONNX Runtime: native platforms
  |-- TFLite/Web runtime: web, evaluated last
```

## SDK Interface

Keep the core ABI small and C-compatible. Platform wrappers can expose idiomatic
types, but they should map to the same primitives.

```c
emotion_status_t emotion_init(const emotion_config_t *config);
emotion_status_t emotion_register_model(const emotion_model_config_t *config);
emotion_status_t emotion_set_user_code(
    const char *user_name,
    const char *model_id,
    const uint8_t *code32);
emotion_status_t emotion_set_key_shard(
    const char *model_id,
    const uint8_t *shard,
    size_t shard_len,
    int64_t expires_at_ms);
emotion_status_t emotion_set_license(
    const char *model_id,
    const char *license_json);
emotion_status_t emotion_warmup(const char *model_id);
emotion_status_t emotion_predict_image(
    const char *model_id,
    const emotion_image_t *image,
    const emotion_face_box_t *face_box,
    emotion_result_t *result);
emotion_status_t emotion_unload(const char *model_id);
emotion_status_t emotion_shutdown(void);
```

Required data contracts:

- `emotion_image_t`: pixel format, width, height, stride, orientation, mirror.
- `emotion_face_box_t`: optional crop rectangle from platform face detection.
- `emotion_result_t`: labels, probabilities, top label, timing, error metadata.
- `emotion_config_t`: log callback, cache dir, secure-store adapter hooks.
- `emotion_model_config_t`: model id, manifest path, encrypted model path,
  runtime preference, accelerator preference.

## Encryption And Model Protection

Encryption is a release blocker for every native SDK. Do not treat it as a
platform afterthought.

### Packaging

Use one model package format across native platforms:

```text
model-name/
  model.enc
  model.manifest.json
  model.signature
```

Manifest fields:

- `model_id`
- `model_version`
- `model_format`: `onnx` initially, `tflite` only where approved
- `input_shape`
- `labels`
- `aad`
- `kdf_info`
- `shard_required`
- `expiry_epoch_ms`
- `encrypted_sha256`
- `plaintext_sha256`
- `runtime_min_version`
- `sdk_min_version`
- `signature_algorithm`

### Runtime Decryption

- AES-256-GCM encrypted model payload.
- CEK derived or unwrapped from user code plus server shard.
- User code is device-local and persisted only through secure storage.
- Server shard is memory-only and expires.
- Manifest hash and signature must verify before decrypt.
- Plaintext model hash must verify after decrypt.
- Decrypted model should live in memory or private temp/cache storage with best
  effort cleanup after runtime load.
- Debug logs must include failure stage and model id, never key material.

### Secure Storage Adapters

- iOS/macOS: Keychain first; Secure Enclave optional for future device-bound
  CEK wrapping.
- Android: Android Keystore plus encrypted preferences/file store.
- Windows: DPAPI or CNG-backed storage.
- Linux/Raspberry Pi: pluggable adapter; default to libsecret/keyring where
  available, otherwise documented file-store fallback for development only.
- Web: no strong client-side secrecy. Web phase must assume model extraction is
  possible. Use TFLite only after evaluating business risk, obfuscation limits,
  short-lived leases, watermarking, and hosted inference fallback.

## Platform Plan

### Apple SDK

- Keep Swift as the public Apple API.
- Move shared runtime decisions behind the C ABI where possible.
- Swift wrapper owns camera integration, Vision face detection, Keychain calls,
  and Apple-specific permissions.
- Package as XCFramework with Swift Package Manager and CocoaPods support.
- Flutter iOS/macOS plugin calls Swift SDK, not independent plugin logic.

### Android SDK

- Keep Kotlin/Java as public Android API.
- Use JNI to call the shared native runtime where practical.
- Kotlin wrapper owns CameraX integration, ML Kit face detection, Android
  Keystore, permissions, and lifecycle.
- Package as AAR with Maven publishing metadata.
- Flutter Android plugin calls the Kotlin SDK.

### Windows SDK

- Use the C/C++ SDK directly.
- Provide CMake package, headers, dynamic/static library, and sample app.
- Add secure-store adapter for Windows.

### Linux SDK

- Use the C/C++ SDK directly.
- Provide CMake package, headers, `.so` and optional static build.
- Camera/face detection is optional at first; image and video-frame inference
  must work before live camera.

### Raspberry Pi SDK

- Treat as Linux ARM64 first.
- Provide cross-compile and native build scripts.
- Prioritize quantized model support and XNNPACK CPU execution.
- Add CLI benchmark target for FPS, latency, memory, and model load time.

### Web SDK

- Last phase.
- Prefer TFLite/Web only if accuracy, size, browser support, and protection
  tradeoffs are acceptable.
- Provide npm package and camera sample only after native SDKs stabilize.
- Document that browser model protection is weak.

## Samples

Each sample should show provisioning, model registration, warmup, prediction,
error handling, and debug logging.

- `samples/ios-swift`: live camera, Vision face crop, prediction overlay.
- `samples/macos-swift`: webcam stream and still-image prediction.
- `samples/android-kotlin`: CameraX, ML Kit face crop, prediction overlay.
- `samples/windows-cpp`: still image and webcam frame loop.
- `samples/linux-cpp`: still image and optional webcam frame loop.
- `samples/raspberry-pi-cpp`: image CLI and camera benchmark.
- `samples/web`: deferred until Web phase.
- `example`: Flutter sample remains and should reuse native SDK wrappers.

## Testing Strategy

### Core Tests

- Manifest parser accepts valid manifests and rejects malformed/unsupported
  versions.
- AES-GCM decrypt succeeds for known vectors and fails on wrong AAD, wrong
  shard, tampered ciphertext, tampered tag, and expired shard.
- Signature and hash checks fail closed.
- User-code and shard state is isolated by user and model id.
- Preprocessing matches golden tensors for sample images.
- Postprocessing matches golden probability outputs.
- Runtime load/warmup/unload has deterministic resource cleanup.

### Platform Tests

- Apple: XCTest for Swift API, Keychain adapter, decryption failures, still-image
  inference, and camera permission handling.
- Android: JVM tests for wrapper logic, instrumented tests for Keystore, JNI
  load, still-image inference, and lifecycle cleanup.
- Windows/Linux/Raspberry Pi: CTest for ABI, crypto, model loading, image
  inference, and benchmark smoke tests.
- Flutter: existing widget/API tests plus integration smoke tests against the
  platform SDK wrappers.
- Web: unit tests and browser smoke tests only in the final phase.

### CI Gates

- Format/lint per language.
- Build all SDK packages.
- Run unit tests with encrypted fixture model.
- Run ABI compatibility check for `emotion_sdk.h`.
- Run golden inference test on at least one fixture image per runtime.
- Run packaging verification: manifest, signature, encrypted hash, plaintext
  hash, and sample app asset inclusion.

## Phases

### Phase 0: Inventory And Contracts

Deliverables:

- Finalize `emotion_sdk.h` C ABI draft.
- Document model package manifest schema.
- Map existing Swift, Kotlin/Java, and C++ code to target modules.
- Choose runtime strategy per platform.

Tests/gates:

- Header compiles as C and C++.
- Manifest schema has fixture validation tests.
- No platform behavior changes yet.
- Every later phase must land tests in the same change set as the behavior it
  introduces.

### Phase 1: Encryption Core

Deliverables:

- Shared manifest parser.
- Shared AES-GCM, HKDF, hash, and signature verification flow.
- Secure-store adapter interface.
- Encrypted fixture model package.
- Debug logging stages for provisioning/decrypt/load.

Tests/gates:

- Crypto known-vector tests.
- Tamper/expiry/wrong-key negative tests.
- Secure-store mock tests.
- Encrypted fixture decrypt/load dry run.

### Phase 2: Native Runtime Core

Deliverables:

- Model registry.
- ONNX Runtime adapter.
- Image preprocessing and result postprocessing.
- Warmup, predict, unload lifecycle.
- C/C++ sample for still-image prediction.

Tests/gates:

- Golden preprocessing tensor tests.
- Golden inference output tests.
- Memory cleanup smoke test.
- Linux/macOS local CTest pass.

### Phase 3: Apple SDK

Deliverables:

- Swift SDK wrapping the core ABI.
- iOS/macOS camera and Vision face detection adapters.
- Keychain adapter integration.
- XCFramework/SPM/CocoaPods packaging.
- Flutter Apple plugin migrated to Swift SDK.

Tests/gates:

- XCTest pass.
- Still-image inference test.
- Camera smoke test.
- Flutter iOS/macOS smoke test where available.

### Phase 4: Android SDK

Deliverables:

- Kotlin/Java SDK wrapping JNI/core runtime.
- CameraX and ML Kit adapters.
- Android Keystore adapter integration.
- AAR/Maven packaging.
- Flutter Android plugin migrated to Kotlin SDK.

Tests/gates:

- JVM tests.
- Instrumented JNI/decryption/inference smoke tests.
- Flutter Android integration smoke test.

### Phase 5: Windows, Linux, Raspberry Pi

Deliverables:

- C/C++ SDK package.
- Windows secure-store adapter.
- Linux secure-store adapter and documented dev fallback.
- Raspberry Pi ARM64 build path.
- CLI and benchmark samples.

Tests/gates:

- CTest on desktop.
- Cross-compile or native ARM64 build.
- Image inference golden test.
- RPi benchmark report: load time, latency, FPS, memory.

### Phase 6: Flutter Cleanup

Deliverables:

- Flutter package becomes a wrapper around platform SDKs.
- Public Dart API preserved where possible.
- `EmotionDetectorView` uses platform SDKs consistently.
- Documentation updated for native and Flutter installs.

Tests/gates:

- `flutter analyze`.
- `flutter test`.
- Example app smoke tests on available platforms.
- API compatibility notes.

### Phase 7: Web Evaluation And SDK

Deliverables:

- Security decision record for Web model exposure.
- TFLite/Web prototype.
- Browser camera sample.
- npm package only if tradeoffs are accepted.

Tests/gates:

- Accuracy comparison against native ONNX baseline.
- Bundle size and load-time report.
- Browser smoke tests.
- Explicit go/no-go on client-side model distribution risk.

## Open Decisions

- Whether native platforms should all use ONNX Runtime or whether Android/RPi
  need TFLite variants for performance.
- Whether signatures are offline only or require server freshness checks.
- Whether Linux production builds require customer-provided secure storage.
- Whether model plaintext may ever touch disk after decrypt.
- Minimum supported versions for each native platform.
