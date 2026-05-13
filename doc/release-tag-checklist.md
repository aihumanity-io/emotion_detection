---
read_when:
  - Preparing an alpha, release-candidate, or stable SDK tag.
  - Checking whether a commit is safe to tag for pub.dev or native SDK consumers.
---

# Release Tag Checklist

Do not tag until the release candidate commit is pushed and the CI run for that
exact commit is green.

## Version Gate

- `pubspec.yaml` version matches the top `CHANGELOG.md` entry.
- `CHANGELOG.md` calls out platform scope and known release blockers.
- `doc/release-readiness.md` platform smoke table is current.

## Local Gate

Run from the repository root:

```sh
flutter test
flutter analyze
flutter pub publish --dry-run
```

Run native release checks:

```sh
cd native
cmake --preset host-release
cmake --build --preset host-release --parallel
ctest --preset host-release
```

## CI Gate

- `gh run list --workflow Flutter --branch <branch>` shows the candidate commit.
- Flutter job is green.
- Native Ubuntu job is green.
- Native Windows job is green, including `emotion_windows_secure_store_test`
  and DPAPI secure-store behavior.
- No tag until CI is green after the final release commit.

## Platform Smoke Gate

- macOS example launches and completes runtime model load plus inference.
- iOS example launches on a real device and completes runtime model load plus
  inference.
- Android debug APK builds; real-device camera/model/inference smoke passes.
- Windows native CTest passes on `windows-latest`; packaged app smoke is still
  required before a stable Windows claim.
- Linux/RPi native package smoke passes on target hardware before advertising
  those targets.

## Tag Gate

After all gates pass:

```sh
git tag v<version>
git push origin v<version>
```
