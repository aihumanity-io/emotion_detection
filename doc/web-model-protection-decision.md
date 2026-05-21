---
read_when:
  - Evaluating Web SDK support or browser model distribution.
  - Deciding whether to ship TFLite/Web, WASM, or hosted inference.
  - Changing model lease, watermarking, or browser sample behavior.
---

# Web Model Protection Decision

## Decision

Status: no-go for client-side production model distribution.

Do not ship production emotion models directly in the browser until the
business accepts extraction risk or chooses a hosted-inference path. Web SDK
work may continue as a prototype only, using non-production models or fixture
models.

## Rationale

Browser clients cannot provide strong model secrecy. A user can inspect network
traffic, JavaScript, WASM memory, IndexedDB/cache storage, and runtime tensors.
Encryption in the browser can slow casual extraction, but the browser must
eventually hold enough key material and plaintext model data to run inference.

## Accepted Prototype Scope

- TFLite/Web or WASM runtime experiments with non-production model assets.
- Camera permission and frame preprocessing smoke tests.
- Accuracy comparison against the native ONNX baseline.
- Bundle size and cold-start/load-time reporting.
- Hosted inference fallback experiments.

## Production Gates

Before changing this to go, document one of these choices:

- Hosted inference is the production path.
- The business explicitly accepts client-side extraction risk.
- A short-lived lease, watermarking, abuse monitoring, and revocation plan is
  approved as sufficient for the target deployment.

## Required Test Evidence

- Accuracy comparison against native ONNX baseline.
- Browser smoke test for camera permission, frame capture, and inference call.
- Bundle size and load-time report.
- Explicit asset audit proving production encrypted models are not bundled in
  the Web sample unless the decision status changes to go.

Current automated guard: `test/web_model_protection_decision_test.dart` scans
`example/web` and fails if model binaries or encrypted model payloads are added
to the Web sample while this decision remains no-go.

The same test also enforces the source Web shell budget documented in
`doc/web-performance-baseline.md` before larger prototype assets are added.

Browser smoke work is scoped in `doc/web-browser-smoke-harness.md`; it uses
camera/frame plumbing plus a hosted inference stub until the model exposure
decision changes.

Hosted inference fallback payloads are scoped in
`doc/web-hosted-inference-contract.md`; browser clients must not send SDK
secrets, key material, or production model bytes.
