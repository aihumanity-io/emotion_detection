---
read_when:
  - Changing encrypted model package contents or manifest fields.
  - Adding SDK support for a new native runtime or platform.
  - Updating provisioning, signing, hashing, or decryption behavior.
---

# Model Package Schema

Native SDKs use one model package layout across non-web platforms:

```text
model-name/
  model.enc
  model.manifest.json
  model.signature
```

The manifest is JSON and versioned independently from the SDK ABI.

## Manifest Fields

Required fields:

- `manifest_schema_version`: integer. Current value: `1`.
- `model_id`: stable model identifier used by SDK registration.
- `model_version`: release version for the model package.
- `model_format`: `onnx` for the native rebuild. `tflite` is reserved.
- `input_shape`: array of positive integers in runtime input order.
- `labels`: ordered output labels. Result indices map into this array.
- `aad`: authenticated associated data used by AES-GCM.
- `kdf_info`: object describing key derivation inputs and algorithm.
- `shard_required`: boolean. `true` for protected production models.
- `expiry_epoch_ms`: integer epoch milliseconds, or `0` for no package expiry.
- `encrypted_sha256`: lowercase hex SHA-256 of `model.enc`.
- `plaintext_sha256`: lowercase hex SHA-256 after decrypt.
- `runtime_min_version`: minimum compatible runtime version.
- `sdk_min_version`: minimum compatible SDK version.
- `signature_algorithm`: signature algorithm for `model.signature`.

`kdf_info` required fields:

- `algorithm`: `hkdf-sha256`.
- `salt_b64`: base64 salt.
- `info`: context string bound into key derivation.

## Validation Rules

- Reject unknown `manifest_schema_version` values.
- Reject missing required fields.
- Reject unsupported `model_format` values.
- Reject empty labels, non-positive input dimensions, and malformed hashes.
- Verify manifest signature before decrypting `model.enc`.
- Verify `encrypted_sha256` before decrypting.
- Verify `plaintext_sha256` after decrypting.
- Fail closed when package expiry is in the past.
- Log validation stage and `model_id`; never log key material.
