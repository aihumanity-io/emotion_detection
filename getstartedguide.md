# Getting Started Guide

This guide gets the Flutter example app running on iOS and macOS.
Android and Windows are intentionally left for later.

## What You Need

- Flutter 3.38.8 or newer on macOS.
- Xcode installed with command line tools selected.
- CocoaPods installed.
- SDK credentials for the emotion backend:
  - `SDK_KEY_ID`
  - `SDK_KEY_SECRET`
- An APFS workspace. Do not build iOS/macOS from ExFAT, SMB, Dropbox sync, or
  other filesystems that create `._*` AppleDouble files. Xcode can fail during
  code signing with errors like `code object is not signed at all` in `._Headers`.

Useful references:

- Flutter iOS setup: https://docs.flutter.dev/platform-integration/ios/setup
- Flutter macOS build notes: https://docs.flutter.dev/platform-integration/macos/building

## 1. Put The Repo On APFS

Native Apple builds should run from an APFS path such as `~/Project`.

```bash
mkdir -p ~/Project
cd ~/Project
git clone https://github.com/fdchiu/emotion_detection.git
cd emotion_detection
```

If you already have the repo on an ExFAT volume, move or clone it to APFS before
building. A cleanup like `dot_clean -m .` can help once, but ExFAT can recreate
`._*` files during the next Xcode build.

Check your current volume:

```bash
df -P . | awk 'NR==2 {print $1}' | xargs diskutil info | grep -E "File System|Type \\(Bundle\\)"
```

Expected: `APFS`.

## 2. Check Tools

```bash
flutter --version
flutter doctor -v
pod --version
xcodebuild -version
```

For iOS/macOS, `flutter doctor -v` must show Xcode and CocoaPods as available.
Android license warnings do not block this guide.

## 3. Get SDK Credentials

Create a developer account:

```text
https://developer.aihumanity.io
```

Use a real email address. The email must be verified before the SDK key can be
used, and the same email is used later at runtime as the user name for model
decryption.

After email verification:

1. Open the dashboard.
2. Copy the SDK key id.
3. Copy the SDK key secret.
4. Use the verified email address as `EXAMPLE_USER_NAME`.

## 4. Create Local Secrets

Create `example/.env`:

```bash
cd example
cat > .env <<'EOF'
SDK_KEY_ID=your-sdk-key-id
SDK_KEY_SECRET=your-sdk-key-secret
EXAMPLE_USER_NAME=your-verified-email@example.com
EXAMPLE_SERVER_BASE_URL=https://backend.aihumanity.io
EOF
```

Keep `example/.env` local. Do not commit real SDK credentials.

The screenshot error:

```text
Missing SDK_KEY_ID/SDK_KEY_SECRET.
Provide via .env, environment, or --dart-define.
```

means `example/.env` is missing, empty, not rebuilt into the app, or the
`--dart-define` values were not passed.

Alternative without `.env`:

```bash
flutter run -d macos \
  --dart-define=SDK_KEY_ID=your-sdk-key-id \
  --dart-define=SDK_KEY_SECRET=your-sdk-key-secret \
  --dart-define=EXAMPLE_USER_NAME=your-verified-email@example.com
```

Use the same `--dart-define` flags for iOS if you do not use `.env`.

## 5. Install Dependencies

From repo root:

```bash
flutter pub get
cd example
flutter pub get
```

Optional explicit pod install:

```bash
cd ios && pod install && cd ..
cd macos && pod install && cd ..
```

Flutter usually runs `pod install` during `flutter build` and `flutter run`, but
running it explicitly makes pod errors easier to see.

## 6. Run macOS

From `example/`:

```bash
flutter build macos --debug
flutter run -d macos
```

Expected first good state:

- The app starts.
- It provisions model secrets automatically through
  `EmotionDetection.initializeWithDeveloperCredentials`.
- After secrets load, macOS shows buttons like `Select image` and `Start camera`.

If macOS fails with `._Headers` or `._*.h` in a code signing error, the repo is
on a filesystem creating AppleDouble files. Move the repo to APFS and rebuild:

```bash
cd ~/Project/emotion_detection/example
flutter clean
flutter pub get
flutter build macos --debug
```

## 7. Run iOS Simulator

The simulator is useful for build validation. Live camera testing should use a
real iPhone.

```bash
open -a Simulator
flutter devices
flutter build ios --simulator --debug
flutter run -d "iPhone 16 Pro Max"
```

If the simulator build fails with:

```text
Framework 'Pods_Runner' not found
```

build the CocoaPods aggregate framework once, then rerun Flutter:

```bash
xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Pods-Runner \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath build/ios \
  build

flutter build ios --simulator --debug
flutter run -d "iPhone 16 Pro Max"
```

## 8. Run iOS On A Real iPhone

Use a real device for camera flows.

1. Connect or unlock the iPhone.
2. Enable Developer Mode on the iPhone if iOS asks.
3. Trust the Mac from the iPhone prompt.
4. Open signing settings if needed:

```bash
open ios/Runner.xcworkspace
```

In Xcode:

- Select `Runner`.
- Open `Signing & Capabilities`.
- Enable `Automatically manage signing`.
- Select your Apple development team.
- Make the bundle id unique if Xcode asks.

Then run:

```bash
flutter devices
flutter run -d <ios-device-id>
```

On first launch, accept camera permission.

## 9. Success Checklist

- `flutter build macos --debug` succeeds.
- `flutter run -d macos` starts the app.
- `flutter build ios --simulator --debug` succeeds.
- `flutter run -d <ios-device-id>` installs on a real iPhone.
- No `Missing SDK_KEY_ID/SDK_KEY_SECRET` message.
- iOS camera permission prompt appears on first camera use.
- macOS can select an image or start the camera after secrets are fetched.

## SDK Provisioning Boundary

In this phase the example still uses `SDK_KEY_ID`, `SDK_KEY_SECRET`, and
`EXAMPLE_USER_NAME`, but app code no longer handles model-decryption payloads
directly. The SDK initializer fetches backend payloads and stores user
code/shard/license data through native secure storage.

```dart
await EmotionDetection.initializeWithDeveloperCredentials(
  sdkKeyId: '<sdk-key-id>',
  sdkKeySecret: '<sdk-key-secret>',
  userName: '<verified-email>',
  serverBaseUrl: 'https://backend.aihumanity.io',
);
```

The encrypted model assets and decryption method are unchanged.

## Troubleshooting

### Missing SDK keys

Fix `example/.env`, then fully rebuild:

```bash
flutter clean
flutter pub get
flutter run -d macos
```

For iOS, rerun with your iOS device id:

```bash
flutter run -d <ios-device-id>
```

### AppleDouble `._*` files

Symptoms:

```text
Failed to decode data using encoding 'utf-8'
code object is not signed at all
In subcomponent: .../._Headers
```

Fix:

```bash
cd ~/Project/emotion_detection
dot_clean -m .
cd example
flutter clean
flutter pub get
flutter build macos --debug
```

If the repo is still on ExFAT, this can come back. Move to APFS.

### iOS signing failure

Open `ios/Runner.xcworkspace` in Xcode and fix `Runner > Signing & Capabilities`.
Use a real Apple team and a unique bundle id.

### Simulator camera does not work

Use a real iPhone. The simulator is mainly a build check for this example.

### Device not found

```bash
flutter devices
```

Unlock the device, trust the Mac, enable Developer Mode, or plug in over USB.
