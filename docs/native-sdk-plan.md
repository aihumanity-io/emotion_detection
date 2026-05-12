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

- Shared manifest parser. Started in `native/src/model_manifest.cpp` with
  fixture-backed native tests.
- Shared AES-GCM, HKDF, hash, and signature verification flow. SHA-256 hash
  verification started in `native/src/crypto_sha256.cpp` with known-vector
  tests. HMAC-SHA256 and HKDF-SHA256 added with RFC test vectors. AES-256-GCM
  encryption/decryption added via mbedTLS with NIST-vector and wrong-tag tests.
- Secure-store adapter interface. C ABI adapter wrapper started in
  `native/src/secure_store.cpp` with mock-backed tests.
- User-code plus shard CEK derivation and shard expiry checks started in
  `native/src/key_material.cpp`. In-memory key state now has user/model
  isolation tests.
- License state validation started in `native/src/license_state.cpp` with
  missing, mismatch, not-active, and expired tests.
- Encrypted fixture model package.
- Encrypted payload hash and package expiry verification started in
  `native/src/model_package.cpp`.
- Decrypt pipeline started in `native/src/decrypt_pipeline.cpp`, combining CEK
  derivation, encrypted hash check, AES-GCM auth, and plaintext hash check.
- Debug logging stages for provisioning/decrypt/load. `native/src/logging.cpp`
  emits stage/model-scoped logs and redacts sensitive key material.

Tests/gates:

- Crypto known-vector tests.
- Tamper/expiry/wrong-key negative tests.
- Secure-store mock tests.
- Encrypted fixture decrypt/load dry run.

### Phase 2: Native Runtime Core

Deliverables:

- Model registry. Started in `native/src/model_registry.cpp` with registration,
  duplicate, lookup, warm, unload, and clear tests.
- Image preprocessing and result postprocessing. Started with RGB/RGBA/BGRA
  preprocessing, NHWC/NCHW tensors, softmax postprocessing, and C result copy
  tests.
- Warmup, predict, unload lifecycle. Started with `RuntimeSession` and a fake
  runtime test double. C ABI entrypoints now wire init/register/provisioning,
  warmup, predict, unload, and shutdown through native state.
- ONNX Runtime adapter. Boundary added with a fail-closed unsupported adapter
  until ONNX Runtime is linked. Optional C API wiring is available with
  `EMOTION_ENABLE_ONNX_RUNTIME=ON` and `ONNXRUNTIME_ROOT`.
- C/C++ sample for still-image prediction. `native/samples/still_image_predict.cpp`
  reads a P3 PPM still image and exercises the public C ABI lifecycle.

Tests/gates:

- Golden preprocessing tensor tests.
- Golden inference output tests.
- Sample smoke test through CTest.
- Memory cleanup smoke test. C ABI lifecycle now loops warm/predict/unload/shutdown
  in `emotion_sdk_c_api_test`.
- Linux/macOS local CTest pass.

### Phase 3: Apple SDK

Deliverables:

- Swift SDK wrapping the core ABI. Started as a standalone SwiftPM package under
  `apple/EmotionNativeSDK` with lifecycle/status/image/prediction types and a
  test fake for the native core boundary.
- iOS/macOS camera and Vision face detection adapters. Added camera frame/source
  protocols, `EmotionCameraPredictionSession`, and a `VisionFaceDetector`.
- Keychain adapter integration. Added a Swift `EmotionSecureStore` boundary and
  `KeychainSecureStore` implementation with injectable Security client.
- XCFramework/SPM/CocoaPods packaging. SwiftPM package is in place; local
  CocoaPods metadata added at `apple/EmotionNativeSDK/EmotionNativeSDK.podspec`.
- Flutter Apple plugin migrated to Swift SDK. iOS/macOS podspecs now compile
  shared Apple SDK Swift sources, and Flutter method-channel payload parsing has
  shared SwiftPM-tested types.

Tests/gates:

- XCTest pass. SwiftPM tests cover lifecycle call ordering and failure-state
  handling for the Apple SDK wrapper.
- Keychain fake-client tests cover set/get/update/delete, namespace isolation,
  and invalid input failures.
- Still-image inference test. SwiftPM fixture loads a P3 PPM image and drives
  the Apple SDK wrapper through fake-core prediction.
- Camera smoke test. SwiftPM fake-frame tests cover no-face skip, face-detected
  prediction, and frame source start/stop behavior.
- Flutter channel payload tests cover register, predict, and user-code argument
  parsing before plugin handlers migrate call sites.
- Flutter iOS/macOS smoke test where available.

### Phase 4: Android SDK

Deliverables:

- Kotlin/Java SDK wrapping JNI/core runtime. Started a JVM-testable
  `EmotionNativeSdk` wrapper with core lifecycle, model registration, image, and
  prediction types before JNI binding.
- CameraX and ML Kit adapters. Added JVM-testable camera frame/source,
  face-detector, and camera prediction session boundaries before binding to
  CameraX and ML Kit runtime types.
- Android Keystore adapter integration. Added a JVM-testable
  `EmotionSecureStore` boundary and `AndroidKeystoreSecureStore` adapter over
  the existing encrypted `SecretStore`.
- AAR/Maven packaging. Android Gradle publishing metadata now emits a release
  AAR plus sources jar under artifact `emotion-native-sdk-android`.
- Flutter Android plugin migrated to Kotlin SDK. Added shared Kotlin payload
  parsers for register, predict, and user-code method-channel arguments and
  wired the plugin handlers through them.

Tests/gates:

- JVM tests. Added fake-core Kotlin lifecycle tests for call ordering,
  unregistered prediction failures, failed register rollback, and RGB image
  validation.
- Android secure-store JVM tests cover set/get/update/delete, namespace
  isolation, and invalid input failures.
- Android camera JVM smoke tests cover no-face skip, face-detected prediction,
  and frame source start/stop behavior.
- Android Flutter bridge JVM tests cover register, predict, and user-code
  argument parsing before deeper runtime migration.
- Instrumented JNI/decryption/inference smoke tests.
- Flutter Android integration smoke test.

### Phase 5: Windows, Linux, Raspberry Pi

Deliverables:

- C/C++ SDK package. Started with an installable CMake package target,
  exported `EmotionNativeSDK::emotion_sdk`, installed public headers, and a
  package-consumer smoke test.
- Windows secure-store adapter. Started with a DPAPI-backed
  `WindowsSecureStore` adapter that persists user-scoped protected blobs
  without requiring Windows Hello or biometrics.
- Linux secure-store adapter and documented dev fallback. Started with an
  optional `LinuxSecretStore` libsecret adapter for production Linux desktops
  plus explicit file-backed `FileSecureStore` support for development and test
  environments where libsecret/keyring is not available.
- Raspberry Pi ARM64 build path. Started with a CMake preset, ARM64 Linux
  toolchain file, and `native/scripts/build-rpi-aarch64.sh` helper for
  `aarch64-linux-gnu` cross builds.
- CLI and benchmark samples. Started with `emotion_benchmark_image`, a native
  still-image benchmark CLI that reports load, warmup, and average prediction
  timing fields.

Tests/gates:

- CTest on desktop, including install-and-consume package smoke coverage.
- Linux secure-store tests cover fail-closed behavior without libsecret and a
  best-effort real Secret Service round trip when built with
  `EMOTION_ENABLE_LIBSECRET=ON`.
- Cross-compile or native ARM64 build. Added preset/toolchain smoke coverage
  that validates the Raspberry Pi ARM64 build path without requiring the cross
  compiler on host-only CI.
- Image inference golden test.
- RPi benchmark report: load time, latency, FPS, memory. Added CTest smoke
  coverage for the host benchmark output schema before RPi-specific runs.

### Phase 6: Flutter Cleanup

Deliverables:

- Flutter package becomes a wrapper around platform SDKs. Started by moving
  macOS camera stream and preview controls behind `EmotionDetectionPlatform`
  instead of direct public API method-channel calls. User-code storage now also
  delegates through the platform interface, and `ModelRuntime` provisioning and
  prediction lifecycle calls are routed through the same platform boundary.
  Legacy `faceEmotion` inference used by `EmotionDetectorView` now also routes
  through the platform interface instead of calling method channels directly.
- Public Dart API preserved where possible.
- `EmotionDetectorView` uses platform SDKs consistently.
- Documentation updated for native and Flutter installs.

Tests/gates:

- `flutter analyze`.
- `flutter test`.
- Method-channel payload tests for the concrete platform wrapper.
- Face-emotion platform delegation and payload tests.
- Platform interface default-method tests cover clear unsupported-platform
  failures instead of recursive delegation.
- Public wrapper tests cover the same unsupported-platform failures through
  `EmotionDetection`, `UserCodeChannel`, and `ModelRuntime`.
- Public API export tests cover the `emotion_detection.dart` barrel during the
  native SDK migration, and API docs now note the compatibility surface.
- Example app smoke tests on available platforms. Added a widget smoke that
  boots the example through the public plugin API with a fake platform wrapper.
- API compatibility notes.

### Phase 7: Web Evaluation And SDK

Deliverables:

- Security decision record for Web model exposure. Started in
  `docs/web-model-protection-decision.md` with a no-go default for production
  browser model distribution until extraction risk is explicitly accepted or a
  hosted-inference path is chosen.
- TFLite/Web prototype.
- Browser camera sample.
- npm package only if tradeoffs are accepted.

Tests/gates:

- Accuracy comparison against native ONNX baseline.
- Bundle size and load-time report. Started in
  `docs/web-performance-baseline.md` with a checked-in Web source shell budget
  and prototype reporting requirements before generated release bundle reports
  are available.
- Browser smoke tests. Started in `docs/web-browser-smoke-harness.md` with
  required first-paint, camera-permission, first-frame, and inference-stub
  validation gates.
- Explicit go/no-go on client-side model distribution risk. Added a doc-backed
  regression test that keeps the production Web gates and required evidence
  visible. Added an asset audit test that fails if model binaries or encrypted
  model payloads are bundled into `example/web` while the decision remains
  no-go.

## Open Decisions

- Whether native platforms should all use ONNX Runtime or whether Android/RPi
  need TFLite variants for performance.
- Whether signatures are offline only or require server freshness checks.
- Whether Linux production builds require customer-provided secure storage.
- Whether model plaintext may ever touch disk after decrypt.
- Minimum supported versions for each native platform.
