# Encryption & Decryption Flow

## Packaging & Encryption
- Run `../../decrypttest/encrypt_modelv2.sh` with `--model-dir <path/to/model.mlpackage>` and `--key-b64 <32-byte-CEK-b64>` to zip, encrypt, and emit `*.enc`, `*.manifest.json`, and a reproducibility `.zip`. The script cleans extended attributes, zips with `zip -r -X`, verifies the archive with `unzip -t`, then records the SHA-256 and size of the plaintext zip before encrypting.
- Encryption shells into `encrypt.swift`, which performs AES-256-GCM using the provided CEK (`SymmetricKey(data: key32)`) and the supplied AAD (e.g., `com.creataai.emotionsdk/ios`). The sealed output uses the `nonce|ciphertext|tag` combined format and the manifest captures both encrypted and plaintext hashes alongside timestamps.
- During packaging you append user-scoped metadata to the manifest (`wrapped_cek_b64`, `kdf_info`) so each model blob carries the AES envelope needed for per-user CEK derivation, plus identifiers such as `model_id` and version strings.

## Runtime Decryption Pipeline
- `EmotionMobilenetv1` (and `AIHFerModel`) load the manifest from the plugin bundle via `loadManifestJSON`, targeting names like `mobilenetv1_fer2024-11-06-08-48-50.manifest.json`.
- `User32SideLoad` searches for a `user32` secret in env overrides (`EMO_USER32_PATH`), App Group containers, `Documents`, `Application Support`, and bundle resources, normalizing base64/raw/hex files to 32 bytes.
- `obtainCEK_UserCodeGateSync` caches the `user32` value in the keychain (`User32Store`) and derives a KEK with `HKDF<SHA256>(salt=aad, info=kdf_info)`. It unwraps the manifest’s `wrapped_cek_b64` via AES-GCM to recover the CEK for the current `userName`/model pair.
- `EncryptedModelLoader.loadFromBundle` reads `<base>.enc`/`.manifest.json`, verifies SHA-256 of the encrypted blob, decrypts using the CEK and manifest AAD, confirms the decrypted zip hash, unzips into a temp directory, locates the `.mlpackage`, compiles it to `.mlmodelc`, and returns an `MLModel` instance for the typed CoreML wrapper.

## Key Management Notes
- `User32Store` persists user secrets without biometrics by default (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), ensuring subsequent launches skip file I/O. HKDF parameters (`aad`, `kdf_info`) tie KEKs to both user identity and model version to prevent misuse across bundles.
- For environments requiring device-bound keys, `SecureCEKProvider` and `SecureEnclaveKey` wrap CEKs to a Secure Enclave–backed EC key, with optional server-fetch or bootstrap flows. Though not used in `EmotionMobilenetv1`, these utilities support future models that must bind CEKs to specific devices rather than user codes.
