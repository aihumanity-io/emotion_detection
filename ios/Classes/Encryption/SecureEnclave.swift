import Foundation
import Security
import CryptoKit

// MARK: - Errors
enum SECEKError: Error {
    case secureEnclaveUnavailable
    case keyCreationFailed(String)
    case keyNotFound
    case algorithmNotSupported
    case wrapFailed(String)
    case unwrapFailed(String)
    case keychainSaveFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case invalidBootstrapKey
    case serverBootstrapRequired
}

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)
    var errorDescription: String? {
        SecCopyErrorMessageString(OSStatus((self as NSError).code), nil) as String? ?? "Keychain error"
    }
}

// MARK: - Keychain helpers (store wrapped CEK bytes)
private struct Keychain {
    static func saveWrappedCEK(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary) // idempotent replace
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SECEKError.keychainSaveFailed(status) }
    }

    static func loadWrappedCEK(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SECEKError.keychainReadFailed(status)
        }
        return data
    }
    
    static func deleteWrappedCEK(service: String,
                                     account: String,
                                     accessGroup: String? = nil) throws {
            var q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            if let ag = accessGroup { q[kSecAttrAccessGroup as String] = ag }
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unhandled(status)
            }
        }
}

// MARK: - Secure Enclave key management (device KEK)
struct SecureEnclaveKey {
    /// Ensure a non-exportable private key exists in Secure Enclave (EC P-256).
    /// Access control: After first unlock, no biometry required (works in background).
    static func ensurePrivateKey(tag: String) throws -> SecKey {
        if let existing = try loadPrivateKey(tag: tag) { return existing }

        // Create access control
        var error: Unmanaged<CFError>?
        guard let ac = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [.privateKeyUsage], &error
        ) else {
            throw SECEKError.keyCreationFailed(error?.takeRetainedValue().localizedDescription ?? "AC failed")
        }

        // Create new Secure Enclave key
        let attributes: [String: Any] = [
            kSecAttrKeyType as String:            kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String:      256,
            kSecAttrTokenID as String:            kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
                kSecAttrAccessControl as String: ac
            ]
        ]

        var cfErr: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attributes as CFDictionary, &cfErr) else {
            throw SECEKError.keyCreationFailed(cfErr?.takeRetainedValue().localizedDescription ?? "CreateRandomKey failed")
        }
        return priv
    }

    static func loadPrivateKey(tag: String) throws -> SecKey? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let k = (item as! SecKey?) else {
            throw SECEKError.keyNotFound
        }
        return k
    }

    static func publicKey(_ privateKey: SecKey) -> SecKey {
        SecKeyCopyPublicKey(privateKey)!
    }

    /// Export public key in ANSI X9.63 (uncompressed) for server use
    static func publicKeyX963(_ publicKey: SecKey) throws -> Data {
        var err: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &err) as Data? else {
            throw SECEKError.keyCreationFailed(err?.takeRetainedValue().localizedDescription ?? "Public export failed")
        }
        return data
    }
}

// MARK: - Wrap/Unwrap CEK using device KEK
struct CEKEnvelope {
    private static let alg = SecKeyAlgorithm.eciesEncryptionCofactorX963SHA256AESGCM

    static func wrap(cek: Data, with publicKey: SecKey) throws -> Data {
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, alg) else { throw SECEKError.algorithmNotSupported }
        var err: Unmanaged<CFError>?
        guard let c = SecKeyCreateEncryptedData(publicKey, alg, cek as CFData, &err) as Data? else {
            throw SECEKError.wrapFailed(err?.takeRetainedValue().localizedDescription ?? "wrap")
        }
        return c
    }

    static func unwrap(wrappedCEK: Data, with privateKey: SecKey) throws -> Data {
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, alg) else { throw SECEKError.algorithmNotSupported }
        var err: Unmanaged<CFError>?
        guard let p = SecKeyCreateDecryptedData(privateKey, alg, wrappedCEK as CFData, &err) as Data? else {
            throw SECEKError.unwrapFailed(err?.takeRetainedValue().localizedDescription ?? "unwrap")
        }
        return p
    }
}

// MARK: - Public provider
struct SecureCEKProvider {
    /// Returns raw CEK bytes by unwrapping with Secure Enclave.
    /// - Parameters:
    ///   - tag: applicationTag for the device KEK (e.g., "com.yourco.model.DemoModel.kek.v1")
    ///   - modelKeychainService: keychain service name to store wrapped CEK (per model/version)
    ///   - modelAccount: keychain account name to store wrapped CEK
    ///   - bootstrapCEKBase64: (DEV ONLY) plaintext CEK for one-time local wrap on first launch
    ///   - serverFetcher: optional closure; given the device public key (X9.63) returns wrapped CEK from server
    static func obtainCEK(
    tag: String,
    modelKeychainService: String,
    modelAccount: String,
    bootstrapCEKBase64: String? = nil,
    serverFetcher: ((Data) throws -> Data)? = nil
    ) throws -> Data {

        #if targetEnvironment(simulator)
        // Simulator: no Secure Enclave. Fall back to bootstrap key for testing.
        guard let b64 = bootstrapCEKBase64,
        let d = Data(base64Encoded: b64), d.count == 32 else {
            throw SECEKError.secureEnclaveUnavailable
        }
        return d
        #else
        // 1) Ensure KEK exists on device
        let priv = try SecureEnclaveKey.ensurePrivateKey(tag: tag)
        let pub = SecureEnclaveKey.publicKey(priv)

        // 2) If we already have a wrapped CEK, unwrap and return
        if let stored = try Keychain.loadWrappedCEK(service: modelKeychainService, account: modelAccount) {
            return try CEKEnvelope.unwrap(wrappedCEK: stored, with: priv)
        }

        // 3) No wrapped CEK yet:
        if let fetch = serverFetcher {
            // a) ask server for wrapped CEK (encrypted to device's pubkey)
            let pubX963 = try SecureEnclaveKey.publicKeyX963(pub)
            let wrapped = try fetch(pubX963)
            // b) persist wrapped CEK
            try Keychain.saveWrappedCEK(wrapped, service: modelKeychainService, account: modelAccount)
            // c) unwrap and return
            return try CEKEnvelope.unwrap(wrappedCEK: wrapped, with: priv)
        }

        // 4) DEV/bootstrap only: wrap local plaintext CEK *once*, store wrapped CEK
        if let b64 = bootstrapCEKBase64, let d = Data(base64Encoded: b64), d.count == 32 {
            let wrapped = try CEKEnvelope.wrap(cek: d, with: pub)
            try Keychain.saveWrappedCEK(wrapped, service: modelKeychainService, account: modelAccount)
            return d
        }

        throw SECEKError.serverBootstrapRequired
        #endif
    }
    
    static func obtainCEKWithMigration(currentTag: String,
                                previousTags: [String],
                                svc: String, acct: String,
                                bootstrapB64: String?,
                                serverFetcher: ((Data) throws -> Data)? = nil) throws -> Data {
        // 1) Try current tag
        if let cek = try? SecureCEKProvider.obtainCEK(tag: currentTag,
                                                      modelKeychainService: svc,
                                                      modelAccount: acct,
                                                      bootstrapCEKBase64: bootstrapB64,
                                                      serverFetcher: serverFetcher) {
            return cek
        }
        // 2) Try old tags to recover
        for old in previousTags {
            if let cek = try? SecureCEKProvider.obtainCEK(tag: old,
                                                          modelKeychainService: svc,
                                                          modelAccount: acct,
                                                          bootstrapCEKBase64: bootstrapB64,
                                                          serverFetcher: serverFetcher) {
                // Re-wrap to current
                let priv = try SecureEnclaveKey.ensurePrivateKey(tag: currentTag)
                let pub  = SecureEnclaveKey.publicKey(priv)
                let wrappedNew = try CEKEnvelope.wrap(cek: cek, with: pub)
                try Keychain.saveWrappedCEK(wrappedNew, service: svc, account: acct)
                // Delete old blob
                try? Keychain.deleteWrappedCEK(service: svc, account: acct)
                return cek
            }
        }
        // 3) No old tag works → bootstrap/server
        return try SecureCEKProvider.obtainCEK(tag: currentTag,
                                               modelKeychainService: svc,
                                               modelAccount: acct,
                                               bootstrapCEKBase64: bootstrapB64,
                                               serverFetcher: serverFetcher)
    }

}
