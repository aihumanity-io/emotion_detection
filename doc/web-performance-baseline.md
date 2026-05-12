---
read_when:
  - Adding Web SDK prototype assets or browser samples.
  - Measuring Web bundle size, load time, or camera startup.
  - Deciding whether a Web SDK build is acceptable to publish.
---

# Web Performance Baseline

## Scope

This is the Phase 7 pre-prototype baseline for the checked-in Web sample shell.
It does not replace a compiled `flutter build web --release` report. It keeps
the source Web sample small before TFLite/Web, WASM, or hosted-inference
prototype assets are added.

## Source Shell Budget

- Source shell budget: 65536 bytes.
- Current source-shell bytes: 43309.
- Counted path: `example/web`.
- Counted files: `index.html`, `manifest.json`, `favicon.png`, and app icons.
- Excluded files: AppleDouble `._*` sidecars and generated build outputs.

## Prototype Reporting Requirements

Before promoting any Web prototype beyond experiment status, record:

- Compiled release output size from `flutter build web --release`.
- Largest JavaScript, WASM, and model assets by byte size.
- Cold-start load time on desktop Chrome and one mobile browser.
- Camera permission-to-first-frame time.
- Inference call latency or hosted-inference round-trip latency.

## Gate

`test/web_model_protection_decision_test.dart` enforces the source shell budget
so Web assets do not grow silently while the production model decision remains
no-go.
