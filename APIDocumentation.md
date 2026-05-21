
# API- Readme

## emotion\_detection

Real-time emotion detection widget using the device camera, Google ML Kit face detection, and a native emotion classifier.

### Install

```yaml
dependencies:
  emotion_detection: ^0.1.0
```

```bash
flutter pub get
```

### Platform permissions

**Android** (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera.any" />
```

Min SDK 21+ recommended.

**iOS** (`ios/Runner/Info.plist`)

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for emotion detection.</string>
```

**macOS** (`*.entitlements`)

```xml
<key>com.apple.security.device.camera</key>
<true/>
```

Also add to `example/macos/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required for emotion detection.</string>
```

**Web**: Serve over HTTPS; user must grant camera permission.

### macOS camera stream (live predictions)

On macOS, the plugin exposes an EventChannel that streams per-frame predictions from the built-in camera using Vision + CoreML.

```dart
import 'dart:io' show Platform;
import 'dart:async';
import 'package:emotion_detection/emotion_detection.dart';

final ed = EmotionDetection();
StreamSubscription? _sub;

void startMacCamera() {
  if (!Platform.isMacOS) return;
  _sub = ed
      .macCameraStream(modelId: 'aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx')
      .listen((dist) {
    // dist is Map<String,double>
    // e.g., {'Happiness': 0.72, 'Neutral': 0.20, ...}
  });
}

void stopMacCamera() async { await _sub?.cancel(); _sub = null; }
```

Notes
- Requires `NSCameraUsageDescription` and camera entitlement in sandboxed builds.
- The stream begins on `listen` and stops when the subscription is canceled.
- Default iOS/macOS model is `aih_exp15_float16` unless overridden. Android
  continues to use `aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx`.

---

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:emotion_detection/emotion_detection.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as imagelib;
import 'dart:io' show Platform;
import 'dart:typed_data';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only warm up cameras on mobile where the camera plugin is available.
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await availableCameras();
    } catch (_) {}
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = EmotionDetectorViewController();

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Emotion Detection')),
        body: Center(
          child: EmotionDetectorView(
            controller: controller,
            onEmotion: (dist) => debugPrint('Emotion dist: $dist'),
            onFaceImage: (faces) {
              if (faces == null || faces.isEmpty) return const SizedBox();
              final png = Uint8List.fromList(imagelib.encodePng(faces.first));
              return Image.memory(png, width: 120);
            },
            onImage: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
```

---

## Public API

### Native SDK migration compatibility

The Flutter package remains the public entrypoint during the native SDK
migration. Importing `package:emotion_detection/emotion_detection.dart` still
exports:

* `EmotionDetectorView` and `EmotionDetectorViewController`
* `EmotionDetection`
* `UserCodeChannel`
* `ModelRuntime`
* `CekSecretClient` and `CekSecretUtils`
* provisioning result and exception types

Platform calls now route through `EmotionDetectionPlatform`, so incomplete
platform implementations fail with `UnimplementedError` instead of hanging or
recursing.

### `EmotionDetectorView`

A stateful widget that:

* streams camera frames,
* detects faces (ML Kit),
* runs native emotion inference,
* overlays face boxes and the top emotion string.

#### Constructors

```dart
EmotionDetectorView({
  Key? key,
  required EmotionDetectorViewController controller,
  OnFaceImage? onFaceImage,
  OnEmotion? onEmotion,
  OnImage? onImage,
})
```

`EmotionDetectorViewController` exposes snapshot and picture-capture controls
without changing the widget callback surface:

```dart
final controller = EmotionDetectorViewController();
controller.takeSnapShot();
final path = await controller.takePicture();
```

#### Typedefs

```dart
typedef OnFaceImage = Image Function(List<imagelib.Image>? images);
typedef OnEmotion   = void Function(Map<String, double> emotions);
typedef OnImage     = Image Function(imagelib.Image? image);
```

* `onFaceImage`: receives cropped face images (`image.Image`). Return a Flutter `Image` if you want to render something; otherwise ignore.
* `onEmotion`: receives the latest emotion probability map (e.g. `{angry:0.01, happy:0.72, ...}`).
* `onImage`: gives you the current full frame (`image.Image`). Return a Flutter `Image` to render or ignore.

#### Display behavior

* Uses `CameraLensDirection.front` by default.
* Draws bounding boxes via `FaceDetectorPainter`.
* Displays `_text` as the top prediction (e.g., “happy”, “neutral”…).

Usage notes
- Call `WidgetsFlutterBinding.ensureInitialized()` before mounting.
- On iOS/Android, warm up cameras with `await availableCameras()` before mounting.
- Desktop platforms currently do not initialize the camera widget; guard camera calls by platform.
- Provide an `EmotionDetectorViewController` to trigger snapshots (`takeSnapShot`) or delegate picture capture (`takePicture`).
- In callbacks, handle `null`/empty payloads; native inference returns a `Map<String, double>` for emotions.

### `EmotionDetection.initializeWithDeveloperCredentials`

Phase 1 SDK initializer for developer-credential provisioning. This keeps the
existing encrypted model format and native decryption flow, but moves the CEK
secret/license/shard/user-code orchestration into the SDK.

```dart
final result = await EmotionDetection.initializeWithDeveloperCredentials(
  sdkKeyId: '<sdk-key-id>',
  sdkKeySecret: '<sdk-key-secret>',
  userName: 'verified-developer@example.com',
  modelKeys: ['example_model'],
  serverBaseUrl: 'https://backend.aihumanity.io',
);
```

The initializer:

* signs backend requests with the SDK key pair,
* fetches CEK-secret payloads and license fallback data,
* extracts user code, shard, license, expiry, and model aliases,
* stores user code/shard/license through the native secure runtime,
* warms Android models when requested,
* returns `EmotionProvisioningResult` with counts and status.

Normal app code should call this initializer before mounting
`EmotionDetectorView` or running `ModelRuntime.predict`. The lower-level APIs
below remain available for debugging and custom flows.

For local example-app development, provide `SDK_KEY_ID`, `SDK_KEY_SECRET`, and
`EXAMPLE_USER_NAME` with `flutter run --dart-define-from-file=env`, explicit
`--dart-define` values, or iOS/macOS Xcode Runner scheme environment variables.
The example app bridges native `ProcessInfo.processInfo.environment` into Dart
so Xcode Run button launches can read scheme variables. Do not bundle `.env` as
a Flutter asset for SDK secrets.

> Security note: this phase still places `sdkKeySecret` in the client app. Use
> it for development or controlled deployments. A production hosted path should
> replace this with a publishable key plus server-side app attestation, or an
> enterprise path where the developer backend holds the SDK secret.

### `CekSecretClient.fetchCekSecret`

Utility for calling `GET /sdk/cek-secret` with your SDK key pair. Signs the
request using `Hmac(sha256)` and returns the decoded JSON payload when the
response is `200`. The service may return fields such as `userSecretB64` (user
code), `cekShardB64` (server-held shard), `expiresAt` (ms epoch), and unified
license fields (`license` or `licenseJson`) when using unified model
distribution.

```dart
final cek = await CekSecretClient.fetchCekSecret(
  apiKeyId: '<sdk-key-id>',
  apiKeySecret: '<sdk-key-secret>',
  modelKey: 'example_model',
  aad: 'com.example.app/ios',
  overrideBaseUrl: 'https://api.example.com',
  cacheShardOnIOS: true, // optionally cache a shard lease when present (iOS only)
  methodChannelName: 'face_emotion_detection', // optional override
  modelIdForShard: 'example_model', // optional override used when caching shard
);
```

This is an advanced API. Prefer
`EmotionDetection.initializeWithDeveloperCredentials` unless you are building a
custom provisioning flow.

* Configure the default host via `--dart-define=EMOTION_SERVER_URL=https://...`.
* Pass `overrideBaseUrl` per call to target alternate stacks.
* When the call fails or returns malformed JSON the method logs via
  `debugPrint` and resolves to `null`.

When `cacheShardOnIOS` is true on iOS and the payload contains shard fields
(e.g., `kekShardB64` or `cekShardB64`), the client will set the shard via
`ModelRuntime.setKeyShard` using the provided `modelKey` (or `modelIdForShard`)
and any expiry hints (`expiresAt` / `cekSecretExpiresAt`).

### `CekSecretUtils` helpers

Reusable helpers to interpret CEK-secret payloads and model-scoped entries:

```dart
import 'package:emotion_detection/emotion_detection.dart';

final userCode = CekSecretUtils.extractUserCode(payload, modelKey: 'model_a');
final shardB64 = CekSecretUtils.extractShard(payload, modelKey: 'model_a');
final expires  = CekSecretUtils.extractExpiresAtMs(payload, modelKey: 'model_a');
final license  = CekSecretUtils.extractLicense(payload, modelKey: 'model_a');
final entries  = CekSecretUtils.extractModelSecrets(payload);

// Optional: normalize URL-safe base64 to standard
final normalized = CekSecretUtils.normalizeBase64(shardB64 ?? '');
```

Returned `entries` contain `modelKey`, `shardB64`, optional `expiresAtMs`, and
`shardRequired`. These helpers are platform-agnostic and safe to use in apps.
`extractLicense` supports object payloads (`license`, `licenseDoc`) and JSON
string payloads (`licenseJson`, `license_json`).

### `UserCodeChannel.saveUserCode`

Bridges user code delivery from Dart into the platform keychain. Call it after
your backend returns a 32-byte base64 user code so iOS can satisfy
`obtainCEK_UserCodeGateSync` during model load.

```dart
await UserCodeChannel.saveUserCode(
  userName: 'user@example.com',
  userCodeB64: (cekPayload['userCodeB64'] ?? cekPayload['userSecretB64']) as String,
);
```

`clearUserCode(userName)` removes the cached entry if you need to reset state
between accounts. Both methods operate on the same MethodChannel as
`EmotionDetectionController` (`face_emotion_detection`).

### `ModelRuntime.setKeyShard`

Stores the server-provided shard lease so wrapped CEKs can only be unwrapped
with a fresh shard. On iOS shards are in-memory; on Android they are stored via
the secure store and invalidate the cached device-wrapped CEK. Expiry handling
is driven by the timestamp you pass and/or the manifest requirements.

```dart
await ModelRuntime.setKeyShard(
  modelId: 'example_model',
  keyShardB64: cekPayload['cekShardB64'] as String,
  expiresAtMs: cekPayload['expiresAt'] as int?,
);
```

If the manifest contains `"shard_required": true` and no valid shard is
present, the iOS loader refuses to unwrap the CEK until a fresh shard is set.

> iOS shard tip: Pass the shard base64 to `ModelRuntime.setKeyShard` exactly as
> received (do not normalize/trim/pad). The loader uses the original base64 in
> its AAD when deriving the KEK; altering it will trigger CryptoKit error 3
> during decryption.

### `ModelRuntime.setModelLicense`

Registers unified-license metadata at runtime for a model id (or alias). Use
this when the encrypted bundle is unified and CEK unwrap requires license data
from backend.

```dart
await ModelRuntime.setModelLicense(
  modelId: 'example_model',
  license: cekPayload['license'] as Map<String, dynamic>,
);
```

Call `ModelRuntime.clearModelLicense(modelId)` when rotating users/accounts.
The SDK sample now stores licenses for all model aliases returned by backend.

### Unified Encryption Backend Payload (Required)

For unified model distribution, backend response should include:

- `userCodeB64` (or `userSecretB64`): base64-encoded 32-byte user code.
- `license` object (or `licenseJson` string): unified license document
  containing at least `modelId`, `algo`, `plainSha256`, `wrappedCek`, `wrap`.
- Optional shard fields (`cekShardB64`, `expiresAt`) if wrap policy requires
  shard (`wrap.shardUsed` true or manifest shard-required).

Per-developer flow remains supported with current fields (`wrapped_cek_b64` +
`kdf_info` path and/or shard fields). A single backend endpoint can return
either shape; client auto-detects by manifest and available license data.

### `ModelRuntime` lifecycle (iOS implemented)

```dart
// initialize channel once
ModelRuntime('face_emotion_detection');

// register a bundled encrypted model
await ModelRuntime.registerModel(
  modelId: 'example_model',
  resourceBase: 'example_model',
  encExt: 'onnx.enc',
  hkdfInfo: 'model_runtime',
  masterKeyB64: null, // optional
);

// set shard (if required) then warm up
await ModelRuntime.setKeyShard(modelId: 'example_model', keyShardB64: shard);
await ModelRuntime.warmUp('example_model');

// run inference
final result = await ModelRuntime.predict('example_model', inputs);

// unload when done
await ModelRuntime.unload('example_model');
```

`registerModel`, `warmUp`, `predict`, and `unload` route over the platform
MethodChannel (`face_emotion_detection`). Parameter names and types match the
Dart signatures above; `predict` returns a `Map<String, dynamic>`.

---

## Notes & constraints

* Requires camera permission and a device/simulator that supports camera preview.
* Face detection and inference run sequentially; heavy workloads may reduce FPS.
* The widget internally guards with `_isBusy` to avoid overlapping inference calls.

## Errors and troubleshooting

- Native bridge error codes (returned as `FlutterError`):
  - `model_load_error`: model failed to load/compile/decrypt.
  - `user_code_error`: invalid or missing user code when setting/clearing.
  - `invalid_args` / `bad_args`: missing required fields in channel calls.
  - `shard_store_error`: shard base64 invalid or could not be cached (iOS).
- Manifest/shard validation (iOS): when `shard_required` is true and no valid
  shard or an expired shard is present, CEK unwrap fails until a fresh shard is set.
- iOS/Android: call `WidgetsFlutterBinding.ensureInitialized()` and then
  `await availableCameras()` before mounting the widget to avoid
  `MissingPluginException` or camera availability issues.
- Desktop: the sample guards camera warm-up; desktop camera preview is not yet
  supported. Do not call `availableCameras()` on desktop.

---

## Troubleshooting

* **MissingPluginException / camera not found**

    * Mobile: call `WidgetsFlutterBinding.ensureInitialized()` and
      `await availableCameras()` before `runApp`.
    * Desktop: guard camera calls by platform; desktop camera is not wired
      up yet. If you need it, add a macOS-capable camera plugin and confirm it
      appears in `example/macos/Flutter/GeneratedPluginRegistrant.swift`.
    * Fully restart after adding native plugins (hot reload won’t register them).

* **iOS “kUTTypeJPEG not found”**

    * Use `UniformTypeIdentifiers` (`UTType.jpeg`) instead of deprecated MobileCoreServices constants.

---

## Example app

See `example.dart` (provided) for a runnable sample that mounts `EmotionDetectorView` and prints emotion updates.

---

# Developer Documentation

## Overview

**Goal:** Glue camera → face detection → emotion inference with a simple Flutter widget.

```
camera (Flutter) → ML Kit face detection (Dart plugin)
                → crop faces (Dart/image)
                → EmotionDetectionController (Dart/native bridge)
                → native model inference (per-platform)
                → Map<String,double> + top label → UI
```

### Key files (from your code)

* `lib/.../emotion_detector_view.dart` — main widget (UI + pipeline controller)
* `lib/native/emotion_detection.dart` — **Dart API** to native emotion engine (via MethodChannel/Ffi) ← **not shown here but referenced**
* `lib/camera_views/detector_view.dart` — camera feed widget (invokes `_processImage`)
* `lib/camera_views/painters/face_detector_painter.dart` — overlay painter
* `lib/constants/emotion_enum.dart` — enum to string mapping (e.g., “NEUTRAL”)
* `example.dart` — runnable demo

`pubspec.yaml` plugin registration:

* Android: `EmotionDetectionPlugin`
* iOS: `EmotionDetectionPlugin`
* macOS: `EmotionDetectionPlugin`
* Windows: `EmotionDetectionPluginCApi`
* Web: `EmotionDetectionWeb`

> These classes are expected to register the method channel and back the `EmotionDetectionController` calls.

---

## Dart surface / contracts

### `EmotionDetectionController` (from `native/emotion_detection.dart`)

> **Contract inferred from usage** in `emotion_detector_view.dart`.

Required methods:

```dart
Future<Map?> processImage(InputImage inputImage, List<Face> faces);
String getEmotionString(Map? emotionMap);
```

**Expectations**

* `processImage` returns a probability map keyed by emotion labels. Example:

  ```dart
  {'angry': 0.02, 'disgust': 0.00, 'fear': 0.03, 'happy': 0.62, 'neutral': 0.29, 'sad': 0.02, 'surprise': 0.02}
  ```
* `getEmotionString` returns the top label (e.g., “happy”). It should match `EmotionEnum` values expected by the UI.

**Input frames**

* `InputImage` (`google_mlkit_face_detection`) is used for detection.
* For crops/inference you convert bytes from NV21:

  ```dart
  final nv21 = convertNV21(bytes, width, height); // -> image.Image
  ```
* Face crops use `imagelib.copyCrop` based on `Face.boundingBox`.

---

## Native/plugin architecture (expected)

### Method channel

* Channel name typically mirrors the package (e.g., `"emotion_detection"`). Make sure the Dart side and platform side match.
* Provide methods like:

    * `inferEmotion` (bytes + width/height and/or cropped face as RGBA/NV21)
    * Optionally `loadModel`, `warmUp`, `getVersion`

### Model loading

* Bundle model files per platform:

    * **iOS/macOS**: `.mlmodelc` (Core ML) or `.tflite` in app bundle.
    * **Android**: `.tflite` in `android/app/src/main/assets` or via AAR assets.
    * **Windows**: `.onnx` / `.tflite` placed next to executable or packaged in `data/` with a known relative path.
    * **Web**: WASM/TFLite Web/TFJS (if supported), or stubbed.

Expose a single Dart initializer (`initEmotionLib(String path)` or auto-load from bundled assets) to keep paths centralized.

### Performance tips

* **Throttle**: You already guard with `_isBusy`. Consider skipping frames while busy.
* **Crop selection**: Use the largest face (you have `findLargestBoundingBoxIndex`) to reduce multi-face cost.
* **Precision**: If the native model expects RGB/BGR, ensure channel order and normalization match (e.g., mean subtraction).
* **Threading**: On iOS/Android, run inference on a background thread/queue.

### iOS specifics

* Prefer `UniformTypeIdentifiers` (`UTType`) over MobileCoreServices. Replace `kUTTypeJPEG` with `UTType.jpeg`.
* If using Core ML:

    * Compile the model in Xcode (creates `.mlmodelc`).
    * Use `VNCoreMLRequest` or raw `MLModel` with pixel buffers.

### Android specifics

* If using TFLite:

    * Add the AAR or gradle dep; ensure `tflite` delegates if GPU/NNAPI wanted.
    * Use `Interpreter` or `InterpreterApi` with a single long-lived instance.

### Windows specifics

* If using ONNX Runtime:

    * Package DLLs (CPU/DirectML) and model file.
    * Keep an eye on ABI/zlib conflicts with other native deps.

### Web specifics

* If unsupported, keep a graceful no-op implementation returning `neutral` and document the limitation.
* If supported, gate features behind `kIsWeb`.

---

## UI integration details

* The overlay text `_text` updates to non-NEUTRAL emotions:

  ```dart
  if (emotion != EmotionEnum.NEUTRAL.value) {
    _text = emotion;
  }
  ```
* `DetectorView` feeds frames via `onImage: _processImage`.
* Snapshot path (`_onSnapShot`) pushes `EmotionDisplayScreen(image: snapShotFrame!)`.

**Heads-up**: `snapShotFrame` is produced only when `snapShotNow` is true; guard nullability to avoid runtime errors when triggering snapshots too early.

---

## Error handling (suggested)

Standardize the Dart exceptions thrown by the native layer:

* `EmotionModelNotLoadedException`
* `InvalidImageException`
* `InferenceFailedException`

Map platform/native codes to these in the method channel handlers, then surface meaningful messages in Dart.

---

## Testing

* **Unit**: mock `EmotionDetectionController` to return fixed maps; verify UI reacts (e.g., `_text` shows “happy”).
* **Golden tests**: render `EmotionDetectorView` with a fake `DetectorView` that feeds canned frames and face boxes.
* **Perf**: measure average `processFaceImage` latency; budget for 16–33ms/frame if aiming for 30–60FPS UI.

---

## Release checklist

* [ ] Update `pubspec.yaml` version and changelog.
* [ ] Validate Android/iOS entitlements and permissions are documented.
* [ ] Ensure models are present for all supported platforms or feature-gated per platform.
* [ ] Run example app on at least one device per platform.
* [ ] Tag and publish.
When `cacheShardOnIOS` is true and the payload contains shard fields (e.g.,
`kekShardB64` or `cekShardB64`), the client will set the shard via
`ModelRuntime.setKeyShard` using the provided `modelKey` and any expiry hints
(`expiresAt` / `cekSecretExpiresAt`).
