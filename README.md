
# emotion\_detection

Real-time emotion detection widget for Flutter using the device camera, and our native emotion classifier.

## ✨ Features

* Plug-and-play `EmotionDetectorView` widget
* Live face detection (ML Kit)
* Emotion inference via native plugin (`EmotionDetectionController`)
* Optional callbacks for face crops, per-frame image, and emotion distribution
* Front camera by default with overlay painter for detected faces

---

## 🚀 Installation

Add to your `pubspec.yaml` (users of the plugin do this in their app):

```yaml
dependencies:
  emotion_detection: ^0.0.1
```

Then run:

```bash
flutter pub get
```

---

## ⚙️ Platform setup

### Android

1. **Camera permission**
   In `android/app/src/main/AndroidManifest.xml`:

   ```xml
   <uses-permission android:name="android.permission.CAMERA" />
   <uses-feature android:name="android.hardware.camera.any" />
   ```

2. **minSdk**
   ML Kit and `camera` usually require `minSdkVersion >= 21`. Set in `android/app/build.gradle`:

   ```gradle
   defaultConfig {
       minSdkVersion 21
   }
   ```

### iOS

1. **Camera permission**
   In `ios/Runner/Info.plist`:

   ```xml
   <key>NSCameraUsageDescription</key>
   <string>This app needs camera access for emotion detection.</string>
   ```

2. **ML Kit / Pod setup**
   Run:

   ```bash
   cd ios
   pod install
   ```

> If you import any UTType constants in native code, use `UniformTypeIdentifiers` (iOS 14+) instead of deprecated MobileCoreServices (avoid `kUTTypeJPEG`).

### macOS

* Add camera permission to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

  ```xml
  <key>com.apple.security.device.camera</key>
  <true/>
  ```

> Note: Live camera preview in `EmotionDetectorView` is currently targeted for
> iOS/Android. The example app guards `availableCameras()` on desktop to avoid
> `MissingPluginException`. Desktop camera support is on the roadmap.

### Web

* Ensure the page is served over HTTPS and user grants camera access.
* Not all browsers/devices support the same camera APIs; test on target browsers.

### Windows

* No additional setup typically required, but you must have a working camera and appropriate drivers.

---

## 🧩 Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:emotion_detection/emotion_detection.dart'; // plugin entrypoint
import 'package:camera/camera.dart';
import 'dart:io' show Platform;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Warm up camera on mobile only to avoid MissingPluginException on desktop/web.
  if (Platform.isAndroid || Platform.isIOS) {
    try { await availableCameras(); } catch (_) {}
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Emotion Detection Demo')),
        body: Center(
          child: EmotionDetectorView(
            onEmotion: (dist) {
              // dist = {'happy': 0.62, 'neutral': 0.31, 'sad': 0.04, ...}
              debugPrint('Emotion distribution: $dist');
            },
            onFaceImage: (faces) {
              // faces = List<image.Image> cropped faces (if any)
              return Image.memory(
                // Example: render first face crop if present
                faces.isNotEmpty
                    ? Uint8List.fromList(imagelib.encodePng(faces.first))
                    : Uint8List(0),
              );
            },
            onImage: (frame) {
              // Full frame (image.Image) if you want it
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
```

## 🔐 SDK Secrets

Use `CekSecretClient.fetchCekSecret` to fetch per-model CEK shards from your
emotion server. Provide your SDK key pair and model key, plus optional `aad` and
`overrideBaseUrl` if you need to target a staging cluster.

```dart
final cekPayload = await CekSecretClient.fetchCekSecret(
  apiKeyId: '<sdk-key-id>',
  apiKeySecret: '<sdk-key-secret>',
  modelKey: 'aih_fer2025',
  aad: 'com.creataai.emotionsdk/ios',
);
```

By default the client reads `EMOTION_SERVER_URL` from `--dart-define` at build
time. Pass `overrideBaseUrl` per call when you need to bypass the compiled
value.

### Passing secrets to native decryption

1. Use `ModelRuntime.registerModel` (see `lib/native/model_runtime.dart`) to tell
   the native layer which encrypted bundle and manifest to load.
2. After `CekSecretClient.fetchCekSecret` returns, grab the CEK shard field (for
   example `payload['keyShardB64']`).
3. Call `ModelRuntime.setKeyShard(modelId: '<id>', keyShardB64: shard)` before
   invoking `ModelRuntime.warmUp` or `EmotionDetectionController.processImage`
   so the native runtime can decrypt the model.
4. Never persist the shard; keep it in memory per the `encryption_note.md`
   guidance.

Use `UserCodeChannel.saveUserCode` to persist the 32-byte user code (a.k.a.
`user32`) into the native keychain once your backend returns it:

```dart
final payload = await CekSecretClient.fetchCekSecret(...);
final userCode = payload?['userCodeB64'] ?? payload?['userSecretB64'];
if (userCode is String && userCode.isNotEmpty) {
  await UserCodeChannel.saveUserCode(
    userName: 'dev@tartalabs.io',
    userCodeB64: userCode,
  );
}
```

When running the example app, set `EXAMPLE_USER_NAME` via `--dart-define` so the
UI knows which keychain account to use when saving the user code.

---

## 🧠 Widget API: `EmotionDetectorView`

```dart
class EmotionDetectorView extends StatefulWidget {
  EmotionDetectorView({
    Key? key,
    this.onFaceImage,
    this.onEmotion,
    this.onImage,
  }) : super(key: key);

  /// Called with a list of cropped face images (if faces are found).
  /// Return a Flutter [Image] to render if you want, or ignore.
  /// typedef OnFaceImage = Image Function(List<imagelib.Image>? images);
  final OnFaceImage? onFaceImage;

  /// Called with the latest emotion distribution map:
  /// e.g. {'angry': 0.01, 'happy': 0.72, 'neutral': 0.22, ...}
  /// typedef OnEmotion = void Function(Map<String, double> emotions);
  final OnEmotion? onEmotion;

  /// Called with the current full frame as an [image.Image] (nullable).
  /// Return a Flutter [Image] to render if you want, or ignore.
  /// typedef OnImage = Image Function(imagelib.Image? image);
  final OnImage? onImage;
}
```

### Behavior & Rendering

* Uses front camera by default (`CameraLensDirection.front`).
* Draws face bounding boxes via `FaceDetectorPainter`.
* Displays the top-predicted emotion as overlay text.
* Snapshot flow (`_onSnapShot`) navigates to `EmotionDisplayScreen` with the captured frame.

---

## 📦 Dependencies

From plugin `pubspec.yaml`:

* `camera`
* `google_mlkit_face_detection`
* `image`
* `plugin_platform_interface`
* (optionally used in example) `provider`, `path_provider`, `image_picker`, `face_camera`

Ensure your app’s `minSdkVersion` / iOS deployment target meets these packages’ requirements.

---

## 🧪 Example App

A minimal example is included (snippet adapted from `example.dart`). It initializes cameras, mounts `EmotionDetectorView`, and prints emotion results.

---

## 🔍 How it works (high level)

1. Camera frames are converted (NV21 → `image.Image`) for processing.
2. ML Kit detects faces and bounding boxes.
3. Cropped faces (and/or whole frame) are passed to a native emotion model via `EmotionDetectionController`.
4. Top emotion & distribution are emitted to `onEmotion`, and face crops to `onFaceImage`.

---

## ❗ Troubleshooting

* **`MissingPluginException` (e.g., `availableCameras`)**
  Make sure you:

    * Call `WidgetsFlutterBinding.ensureInitialized()` before `availableCameras()`.
    * Use a real device or a simulator with camera support.
    * Rebuild the app after adding a plugin (hot reload won’t register native code changes).

* **iOS build errors referencing UTType constants (e.g., `kUTTypeJPEG`)**
  Import and use `UniformTypeIdentifiers` (`UTType.jpeg`) instead of deprecated MobileCoreServices symbols.

* **Black preview / no frames**

    * Verify camera permissions were granted.
    * Test on another device/camera.
    * For web, serve over HTTPS and accept permission prompts.

---

## 🗺 Roadmap (suggested)

* Public exposure of more configuration (e.g., lens selection, detection options)
* Frame rate throttling / performance toggles
* Batch snapshot capture & gallery
* Optional on-device model bundling docs

---

## 📝 License

Contact us for licensing terms. @Copyright 2024-2026

---

## 👏 Acknowledgements

* Flutter `camera` plugin
* `image` (Dart image processing)

---
