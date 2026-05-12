---
read_when:
  - Comparing Web prototype output with native ONNX output.
  - Adding TFLite/Web, WASM, or hosted inference implementations.
  - Updating fixture images, labels, preprocessing, or result tolerances.
---

# Web Accuracy Baseline

## Scope

This baseline defines how Phase 7 Web prototypes compare against the native
ONNX runtime. It is required before promoting a browser runtime beyond
experiment status.

## Fixture

- Fixture image: `native/tests/resources/sample_rgb.ppm`.
- Input color order: RGB.
- Input shape: use the model manifest input shape.
- Preprocessing: match native preprocessing for resize, normalization,
  channel order, orientation, and face crop coordinates.

## Labels

Expected labels must match the model manifest order:

- `Anger`
- `Disgust`
- `Fear`
- `Happiness`
- `Neutral`
- `Sadness`
- `Surprise`

## Comparison Rules

- Native baseline source: ONNX runtime output from the shared native SDK.
- Web candidate source: TFLite/Web, WASM, or hosted inference output.
- Top label must match the native baseline.
- Each score must be finite and between `0.0` and `1.0`.
- Sum of scores should be within `0.01` of `1.0`.
- Per-label absolute score drift must be less than or equal to `0.05`.
- Top-label score drift must be less than or equal to `0.03`.

## Required Report Fields

- `fixturePath`
- `modelId`
- `nativeRuntime`
- `webRuntime`
- `nativeTopLabel`
- `webTopLabel`
- `maxPerLabelDrift`
- `topLabelScoreDrift`
- `scoreSum`
- `passed`

## Gate

The Web accuracy gate passes only when the report includes every required field,
the top labels match, all scores are valid probabilities, and drift remains
within the documented tolerances.
