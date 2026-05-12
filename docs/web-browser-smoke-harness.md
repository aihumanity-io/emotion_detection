---
read_when:
  - Building or running Phase 7 Web browser smoke tests.
  - Adding a Web camera sample, hosted inference fallback, or TFLite/Web prototype.
  - Debugging Web camera permission, frame capture, or inference-call startup.
---

# Web Browser Smoke Harness

## Scope

This harness verifies browser plumbing only. It must not bundle production
models while `docs/web-model-protection-decision.md` remains no-go.

## Preconditions

- Serve the Web app from `localhost` or HTTPS.
- Use non-production fixture assets or a hosted inference stub.
- Keep production `.enc`, `.onnx`, `.tflite`, `.wasm`, and Core ML assets out
  of `example/web`.
- Enable browser camera permissions for the test origin.

## Smoke Steps

1. Start the Web app.
2. Assert the Flutter app reaches first paint.
3. Request camera permission.
4. Capture the first video frame.
5. Send a downscaled frame or face crop to a hosted inference stub.
6. Assert the inference response shape is a label-to-score map.
7. Record camera permission-to-first-frame time.
8. Record inference call latency or hosted round-trip latency.

## Expected Stub Response

```json
{
  "Neutral": 0.8,
  "Happiness": 0.2
}
```

Scores must be numeric and labels must be non-empty strings. The smoke does not
validate model accuracy; native-vs-Web accuracy belongs in a separate baseline.
See `docs/web-accuracy-baseline.md` for the native ONNX comparison contract.

## Debug Output

Capture these fields in the smoke report:

- `origin`
- `browser`
- `firstPaintMs`
- `cameraPermissionMs`
- `firstFrameMs`
- `inferenceRoundTripMs`
- `responseLabels`
- `assetAuditPassed`

## Gate

The Web smoke is passing only when first paint, camera permission, first-frame
capture, and inference-stub response validation all succeed without bundled
production model assets.
