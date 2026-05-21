# EmotionNativeSDK

Native Apple SDK wrapper for the emotion detection core ABI.

## Local Verification

```sh
xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swift test --package-path apple/EmotionNativeSDK
ruby -c apple/EmotionNativeSDK/EmotionNativeSDK.podspec
```

Use the Xcode default toolchain locally; the repo PATH may contain an older
Swift toolchain that cannot build against the installed macOS SDK.
