---
read_when:
  - Implementing Web hosted inference fallback.
  - Changing browser frame, face crop, or inference request payloads.
  - Adding hosted inference server endpoints or SDK client code.
---

# Web Hosted Inference Contract

## Scope

This contract defines the browser-safe inference fallback for Phase 7. It sends
a downscaled frame or face crop to a hosted endpoint instead of distributing
production model assets to the browser.

## Endpoint

- Method: `POST`
- Path: `/sdk/web/infer`
- Transport: HTTPS only outside localhost development.
- Authentication: publishable SDK key or short-lived session token, never the
  SDK secret.
- Content type: `application/json`.

## Request

Required fields:

- `requestId`: client-generated UUID or trace id.
- `modelId`: server-side model id or alias.
- `image`: object containing encoded image data.
- `image.format`: `jpeg` or `png`.
- `image.dataB64`: base64-encoded downscaled frame or face crop.
- `image.width`: encoded image width in pixels.
- `image.height`: encoded image height in pixels.
- `image.colorSpace`: `srgb`.
- `source`: `camera`, `upload`, or `test_fixture`.
- `client`: object with non-sensitive telemetry.
- `client.sdkVersion`: Flutter/Web SDK version.
- `client.platform`: `web`.
- `client.origin`: browser origin.

Optional fields:

- `faceBox`: `{ "left": 0, "top": 0, "width": 0, "height": 0 }`.
- `debug`: boolean requesting server timing fields.

Forbidden fields:

- SDK secret or signing secret.
- User code, CEK, shard, wrapped key, or plaintext model bytes.
- Production model package bytes, `.enc`, `.onnx`, `.tflite`, or `.wasm`.
- Raw full-resolution frames when a face crop is available.

## Response

Required fields:

- `requestId`: echoes the request id.
- `modelId`: model id used by the server.
- `scores`: label-to-score map.
- `topLabel`: label with the highest score.
- `timingMs`: object containing server timings.
- `timingMs.preprocess`
- `timingMs.inference`
- `timingMs.total`

Rules:

- Score labels must be non-empty strings.
- Scores must be finite numbers between `0.0` and `1.0`.
- Score sum should be within `0.01` of `1.0`.
- `topLabel` must exist in `scores`.
- Errors must return a structured error code and message, not partial scores.

## Debug Fields

Clients should log these fields for browser smoke reports:

- `requestId`
- `origin`
- `image.width`
- `image.height`
- `response.topLabel`
- `response.timingMs.total`
- `roundTripMs`

## Gate

Hosted inference fallback work is acceptable only when the client sends no
model material or secrets, validates response score shape, and records round
trip latency for the browser smoke report.
