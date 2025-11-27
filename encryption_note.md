# Encryption & Decryption Flow

## Packaging & Encryption
- Use your model-packaging script (e.g., `encrypt_model.sh`) with `--model-dir <path/to/model.mlpackage>` and `--key-b64 <32-byte-CEK-b64>` to zip, encrypt, and emit `*.enc`, `*.manifest.json`, and a reproducibility `.zip`. The script should clean extended attributes, zip with `zip -r -X`, verify with `unzip -t`, and record the SHA-256 and size of the plaintext zip before encrypting.
- Encryption runs AES-256-GCM using the provided CEK (`SymmetricKey(data: key32)`) and the supplied AAD (for example, `com.example.app/ios`). The sealed output uses the `nonce|ciphertext|tag` combined format and the manifest captures both encrypted and plaintext hashes alongside timestamps.
- During packaging, append user-scoped metadata to the manifest (`wrapped_cek_b64`, `kdf_info`) so each model blob carries the AES envelope needed for per-user CEK derivation, plus identifiers such as `model_id` and version strings.

## Runtime Decryption Pipeline
- The models load their manifest from the plugin bundle via `loadManifestJSON`, targeting names like `<model>.manifest.json`. Manifests may set `"shard_required": true` and optionally `"expiry_epoch_ms"` to gate unwraps on a fresh server shard.
- `User32SideLoad` searches for a `user32` secret in env overrides (`EMO_USER32_PATH`), App Group containers, `Documents`, `Application Support`, and bundle resources, normalizing base64/raw/hex files to 32 bytes.
- `obtainCEK_UserCodeGateSync` caches the `user32` value in the keychain (`User32Store`) and derives a KEK with `HKDF<SHA256>(salt=aad, info=kdf_info)` over `[user32 || shard?]`. If the manifest flags `shard_required`, the caller must supply a valid shard lease first; otherwise derive without a shard. Shards come from the server, live only in memory, and are dropped/invalid when expired.
- `EncryptedModelLoader.loadFromBundle` reads `<base>.enc`/`.manifest.json`, verifies SHA-256 of the encrypted blob, decrypts using the CEK and manifest AAD, confirms the decrypted zip hash, unzips into a temp directory, locates the `.mlpackage`, compiles it to `.mlmodelc`, and returns an `MLModel` instance for the typed CoreML wrapper.

## Key Management Notes
- `User32Store` persists user secrets without biometrics by default (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), ensuring subsequent launches skip file I/O. HKDF parameters (`aad`, `kdf_info`) tie KEKs to both user identity and model version to prevent misuse across bundles. When a shard is present, it is concatenated to the user secret before HKDF to bind the KEK to a server-issued lease.
- Shard leases are stored only in-memory on iOS via `ShardCache` and can be cleared or replaced at runtime. Expired shards (either by manifest `expiry_epoch_ms` or the lease’s own `expiresAtMs`) reject CEK unwraps until refreshed from the server.
- For environments requiring device-bound keys, `SecureCEKProvider` and `SecureEnclaveKey` wrap CEKs to a Secure Enclave–backed EC key, with optional server-fetch or bootstrap flows. Though not used in `EmotionMobilenetv1`, these utilities support future models that must bind CEKs to specific devices rather than user codes.
