---
read_when:
  - Preparing an SDK release.
  - Deciding whether the package is stable, alpha, or internal-only.
  - Changing platform support or Web distribution scope.
---

# Release Readiness

Status: not ready for a stable public SDK release.

Recommended next release scope: native alpha / release candidate after package
validation and platform smoke gates pass.

## Platform Scope

| Platform | Release status | Required before stable |
| --- | --- | --- |
| Flutter/Dart API | Alpha candidate | Keep `flutter analyze`, `flutter test`, and API export tests green. |
| iOS | Alpha candidate | Run example on device, verify camera permission, model load, and inference. |
| macOS | Alpha candidate | Run example on device, verify camera permission, model load, and inference. |
| Android | Alpha candidate | Run example on device, verify camera permission, model load, and inference. |
| Windows | Alpha candidate | Run Windows build/smoke and secure-store validation on Windows. |
| Linux/RPi native | Experimental native library | Run toolchain/package smoke on target hardware before advertising SDK support. |
| Web | Evaluation only | Keep production client-side model distribution no-go unless risk is accepted. |

## Release Gates

- `flutter analyze`
- `flutter test`
- `flutter pub publish --dry-run`
- Example app smoke on every advertised platform.
- Permission and entitlement docs verified for every advertised platform.
- Model asset scope accepted, including package archive size and encrypted model
  distribution risk.
- `CHANGELOG.md` and `pubspec.yaml` version aligned.
- Tag only after the release candidate commit is pushed and CI is green.

## Local macOS Build Smoke

This workspace may live on an external volume that creates AppleDouble `._*`
sidecar files during CocoaPods and Flutter framework copies. The example iOS
and macOS Podfiles strip those generated files before signing. For a local
macOS debug compile on this workspace, use Xcode with signing disabled so build
products stay under DerivedData:

```sh
cd example/macos
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  EXPANDED_CODE_SIGN_IDENTITY= build
```

## Web Gate

Web is not part of the stable SDK release scope while
`doc/web-model-protection-decision.md` says client-side production model
distribution is no-go. A Web release needs either a hosted inference production
service or a signed acceptance of client-side extraction risk.
