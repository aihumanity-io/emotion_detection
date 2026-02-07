import Security
import CryptoKit
import Foundation

struct CekShardLease {
    let shard: Data
    let shardB64: String?
    let expiresAt: Date?

    func isExpired(now: Date = Date()) -> Bool {
        guard let exp = expiresAt else { return false }
        return now >= exp
    }
}

enum ShardCacheError: Error { case invalidBase64, emptyShard }

enum ShardCache {
    private static var shards: [String: CekShardLease] = [:]
    private static let lock = NSLock()

    static func setShard(modelId rawModelId: String, base64: String, expiresAtMs: Int64?) throws {
        let modelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { throw ShardCacheError.invalidBase64 }
        let normalized = ShardCache.normalizeB64(base64)
        guard let data = Data(base64Encoded: normalized) else { throw ShardCacheError.invalidBase64 }
        guard !data.isEmpty else { throw ShardCacheError.emptyShard }

        let expiry: Date?
        if let ms = expiresAtMs {
            expiry = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        } else {
            expiry = nil
        }

        let lease = CekShardLease(shard: data, shardB64: base64, expiresAt: expiry)
        lock.lock(); defer { lock.unlock() }
        shards[modelId] = lease
        print("ShardCache: stored shard for id=\(modelId) bytes=\(data.count) exp=\(expiry?.timeIntervalSince1970 ?? -1)")
    }

    static func clearShard(modelId rawModelId: String) {
        let modelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        shards.removeValue(forKey: modelId)
    }

    static func activeShard(for identifiers: [String], now: Date = Date()) -> CekShardLease? {
        lock.lock(); defer { lock.unlock() }
        for id in identifiers {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lease = shards[trimmed] else { continue }
            if lease.isExpired(now: now) {
                shards.removeValue(forKey: trimmed)
                continue
            }
            print("ShardCache: hit id=\(trimmed) exp=\(lease.expiresAt?.timeIntervalSince1970 ?? -1)")
            return lease
        }
        return nil
    }
}
extension ShardCache {
    static func normalizeB64(_ value: String) -> String {
        var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let missing = (4 - s.count % 4) % 4
        if missing > 0 { s = s.padding(toLength: s.count + missing, withPad: "=", startingAt: 0) }
        return s
    }
}
enum User32StoreErr: Error { case notFound, badStatus(OSStatus) }

enum User32Store {
    static let service = "com.creataai.emotionsdk.user32"
    static func delete(account: String, accessGroup: String? = nil) throws {
            var q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
            ]
            if let ag = accessGroup { q[kSecAttrAccessGroup as String] = ag }
            let st = SecItemDelete(q as CFDictionary)
            guard st == errSecSuccess || st == errSecItemNotFound else { throw User32StoreErr.badStatus(st) }
        }

    static func save(_ data: Data, account: String, requireBiometrics: Bool = false, accessGroup: String? = nil) throws {
            var q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecValueData as String: data
            ]
            if let ag = accessGroup { q[kSecAttrAccessGroup as String] = ag }

            if requireBiometrics {
                let ac = SecAccessControlCreateWithFlags(nil,
                                                         kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                         [.biometryCurrentSet],
                                                         nil)!
                q.removeValue(forKey: kSecAttrAccessible as String)
                q[kSecAttrAccessControl as String] = ac
            }

            // Idempotent replace
            try delete(account: account, accessGroup: accessGroup)
            let st = SecItemAdd(q as CFDictionary, nil)
            guard st == errSecSuccess else { throw User32StoreErr.badStatus(st) }
        }

        /// Probe fetch that **never** shows UI. If this returns errSecInteractionNotAllowed,
        /// the item requires biometry/user presence.
        static func loadNoUI(account: String, accessGroup: String? = nil) throws -> Data {
            var q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
            ]
            if let ag = accessGroup { q[kSecAttrAccessGroup as String] = ag }

            var item: CFTypeRef?
            let st = SecItemCopyMatching(q as CFDictionary, &item)
            guard st == errSecSuccess, let d = item as? Data else {
                throw User32StoreErr.badStatus(st)
            }
            return d
        }
    static func saveOD(_ data: Data, account: String, requireBiometrics: Bool = false) throws {
        var q: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        if false /*requireBiometrics*/ {
            let sac = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.biometryCurrentSet], nil)!
            q.removeValue(forKey: kSecAttrAccessible as String)
            q[kSecAttrAccessControl as String] = sac
        }
        SecItemDelete(q as CFDictionary)
        let st = SecItemAdd(q as CFDictionary, nil)
        guard st == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(st)) }
    }
    static func load(account: String) throws -> Data {
        let q: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &item)
        guard st == errSecSuccess, let d = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(st))
        }
        return d
    }
}

@available(iOS 14.0, *)
func deriveKEK(user32: Data, shard: Data?, aad: String, kdfInfo: String) -> SymmetricKey {
    // Packaging binds shard via AAD/salt, not in IKM.
    return HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: user32),
        salt: Data(aad.utf8),
        info: Data(kdfInfo.utf8),
        outputByteCount: 32
    )
}

func unwrapCEK_fromManifest(wrappedCEK_B64: String, kek: SymmetricKey, aad: String) throws -> Data {
    let trimmed = wrappedCEK_B64.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let env = Data(base64Encoded: trimmed) else {
        throw UserGateError.manifestMissingFields
    }
    let box = try AES.GCM.SealedBox(combined: env) // typo? fix: AES.GCM
    return try AES.GCM.open(box, using: kek, authenticating: Data(aad.utf8))
}

struct LicenseDoc: Decodable {
    struct Wrap: Decodable { let type: String; let wrapIv: String; let salt: String; let shardUsed: Bool; let aad: String? }
    let version: Int
    let licenseId: String
    let userId: String
    let modelId: String
    let algo: String
    let plainSha256: String
    let wrap: Wrap
    let wrappedCek: String
    let issuedAt: String
    let expiresAt: String?
}

private func b64urlDecode(_ s: String) -> Data? {
    let std = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let pad = (4 - std.count % 4) % 4
    return Data(base64Encoded: std + String(repeating: "=", count: pad))
}

@available(iOS 14.0, *)
func unwrapCEK_fromLicense(userCode: Data, shard: Data?, license: LicenseDoc) throws -> Data {
    if license.wrap.shardUsed && shard == nil { throw UserGateError.missingShard }
    let ikm: Data = {
        if let s = shard {
            var v = Data(userCode)
            v.append(s)
            return v
        } else {
            return userCode
        }
    }()
    let salt = b64urlDecode(license.wrap.salt) ?? Data()
    let info = Data("model:\(license.modelId)".utf8)
    let kek = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt, info: info, outputByteCount: 32)
    let iv = try AES.GCM.Nonce(data: b64urlDecode(license.wrap.wrapIv) ?? Data())
    let aad = Data((license.wrap.aad ?? "").utf8)
    guard let combined = b64urlDecode(license.wrappedCek) else { throw UserGateError.manifestMissingFields }
    let box = try AES.GCM.SealedBox(combined: combined)
    let cek = try AES.GCM.open(box, using: kek, authenticating: aad)
    precondition(cek.count == 32)
    return cek
}

private func loadLicenseIfPresent(baseName: String, in bundle: Bundle = .main) -> LicenseDoc? {
    let candidates = ["\(baseName).ios.license", "\(baseName).license", baseName]
    for n in candidates {
        if let url = bundle.url(forResource: n, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let lic = try? JSONDecoder().decode(LicenseDoc.self, from: data) {
            return lic
        }
    }
    return nil
}
struct Manifest: Decodable {
    let model_name: String?
    let model_id: String?
    let enc_sha256: String
    let aad: String
    let wrapped_cek_b64: String
    let kdf_info: String
    let shard_required: Bool?
    let expiry_epoch_ms: Int?

    private enum CodingKeys: String, CodingKey {
        case model_name
        case model_id
        case enc_sha256
        case aad
        case wrapped_cek_b64
        case kdf_info
        case shard_required
        case shardRequired
        case expiry_epoch_ms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model_name = try c.decodeIfPresent(String.self, forKey: .model_name)
        model_id = try c.decodeIfPresent(String.self, forKey: .model_id)
        enc_sha256 = try c.decode(String.self, forKey: .enc_sha256)
        aad = try c.decode(String.self, forKey: .aad)
        wrapped_cek_b64 = try c.decode(String.self, forKey: .wrapped_cek_b64)
        kdf_info = try c.decode(String.self, forKey: .kdf_info)
        let shardSnake = try c.decodeIfPresent(Bool.self, forKey: .shard_required)
        let shardCamel = try c.decodeIfPresent(Bool.self, forKey: .shardRequired)
        shard_required = shardSnake ?? shardCamel
        expiry_epoch_ms = try c.decodeIfPresent(Int.self, forKey: .expiry_epoch_ms)
    }
}

@available(iOS 14.0, *)
/*func obtainCEK_UserCodeGate(
manifest: Manifest,
userName: String,
user32Supplier: () async throws -> Data  // server fetch or side-loaded file
) async throws -> Data {
    // Load or import user32 (32 bytes)
    let acct = userName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let user32: Data = (try? User32Store.load(account: acct)) ?? {
        let d = try! await user32Supplier()
        try! User32Store.save(d, account: acct, requireBiometrics: true)   // turn biometrics on/off
        return d
    }()

    // Derive KEK and unwrap CEK
    let kek = deriveKEK(user32: user32, shard: nil, aad: manifest.aad, kdfInfo: manifest.kdf_info)
    let cek = try unwrapCEK_fromManifest(wrappedCEK_B64: manifest.wrapped_cek_b64,
        kek: kek, aad: manifest.aad)
    return cek
}*/

// Errors you already use can replace this
enum UserGateError: Error { case manifestMissingFields, invalidUser32, missingShard, shardExpired }

private func activeShard(for manifest: Manifest, userName: String, now: Date = Date()) -> CekShardLease? {
    let sanitizedUser = UserCodeUtils.sanitize(userName: userName)
    let candidates = [manifest.model_id, manifest.model_name, sanitizedUser].compactMap { $0 }
    print("Shard lookup candidates: \(candidates)")
    return ShardCache.activeShard(for: candidates, now: now)
}

@available(iOS 14.0, *)
private func resolveShardLease(from manifest: Manifest, userName: String, now: Date = Date()) throws -> CekShardLease? {
    if let manifestExpiry = manifest.expiry_epoch_ms {
        let expiryDate = Date(timeIntervalSince1970: TimeInterval(manifestExpiry) / 1000.0)
        if now >= expiryDate {
            print("Shard: manifest expiry reached for \(manifest.model_id ?? manifest.model_name ?? "<unknown>")")
            throw UserGateError.shardExpired
        }
    }

    let lease = activeShard(for: manifest, userName: userName, now: now)
    if manifest.shard_required == true && lease == nil {
        print("Shard: required but missing for \(manifest.model_id ?? manifest.model_name ?? "<unknown>")")
        throw UserGateError.missingShard
    }
    if let lease = lease, lease.isExpired(now: now) {
        print("Shard: found but expired for \(manifest.model_id ?? manifest.model_name ?? "<unknown>")")
        throw UserGateError.shardExpired
    }
    return lease
}

/// Async supplier version (server or side-loaded async)
@available(iOS 14.0, *)
func obtainCEK_UserCodeGate(
    manifest: Manifest,
    userName: String,
    modelId: String?,
    user32Supplier: () async throws -> Data
) async throws -> Data {
    let acct = UserCodeUtils.account(userName: userName, modelId: modelId)

    // 1) Load cached user32 or fetch & cache
    let user32: Data
    if let cached = try? User32Store.load(account: acct) {
        print("User32: loaded cached for \(acct) bytes=\(cached.count)")
        user32 = cached
    } else {
        let fetched = try await user32Supplier()
        guard fetched.count == 32 else {
            throw UserGateError.invalidUser32
       }
        print("User32: fetched via supplier for \(acct) bytes=\(fetched.count)")
        try User32Store.save(fetched, account: acct, requireBiometrics: false)
        user32 = fetched
    }

    // 2) Unwrap CEK from manifest using HKDF(user32) → KEK, then AES-GCM open
    /*guard
        let aad = manifest.aad, !aad.isEmpty,
        let wrapped = manifest.wrapped_cek_b64, !wrapped.isEmpty,
        let kdfInfo = manifest.kdf_info, !kdfInfo.isEmpty
    else { if #available(iOS 14.0, *) {
        throw UserGateError.manifestMissingFields
    } else {
        // Fallback on earlier versions
    } }*/
    let aad = manifest.aad
    let wrapped = manifest.wrapped_cek_b64
    let kdfInfo = manifest.kdf_info
    guard !aad.isEmpty, !wrapped.isEmpty, !kdfInfo.isEmpty else {
        throw UserGateError.manifestMissingFields
    }

    let shardLease = try resolveShardLease(from: manifest, userName: userName)
    let useShard = manifest.shard_required == true
    let shardData = useShard ? shardLease?.shard : nil
    let shardB64 = shardLease?.shardB64 ?? shardLease?.shard.base64EncodedString()
    let aadAuth: String
    if useShard, let s = shardB64, !s.isEmpty {
        aadAuth = "\(aad)|shard:\(s)"
        print("KEK: using shard bytes=\(shardData?.count ?? 0) aad=\(aadAuth)")
    } else {
        aadAuth = aad
        if shardLease != nil { print("KEK: ignoring optional shard; manifest.shard_required=false") }
    }
    let kek = deriveKEK(user32: user32, shard: shardData, aad: aadAuth, kdfInfo: kdfInfo)
    let cek = try unwrapCEK_fromManifest(wrappedCEK_B64: wrapped, kek: kek, aad: aadAuth)
    return cek
}

/// Sync supplier version (e.g., local file)
func obtainCEK_UserCodeGate(
    manifest: Manifest,
    userName: String,
    modelId: String?,
    user32Supplier: () throws -> Data
) async throws -> Data {
    try await obtainCEK_UserCodeGate(
        manifest: manifest,
        userName: userName,
        modelId: modelId,
        user32Supplier: {
            let d = try user32Supplier()
            return d
        }
    )
}

@available(iOS 14.0, *)
func obtainCEK_UserCodeGateSync(
    manifest: Manifest,
    userName: String,
    modelId: String?,
    user32Provider: () throws -> Data
) throws -> Data {
    let acct = UserCodeUtils.account(userName: userName, modelId: modelId)

    // load cached or import and cache
    let user32: Data
    if let cached = try? User32Store.load(account: acct) {
        print("User32: loaded cached for \(acct) bytes=\(cached.count)")
        user32 = cached
    } else {
        let fetched = try user32Provider()
        guard fetched.count == 32 else { throw UserGateError.invalidUser32 }
        print("User32: fetched via provider for \(acct) bytes=\(fetched.count)")
        try User32Store.save(fetched, account: acct, requireBiometrics: false)
        user32 = fetched
    }

    // Prefer license.json if present
    if let lic = loadLicenseIfPresent(baseName: manifest.model_id ?? manifest.model_name ?? "") {
        let shardLease = try resolveShardLease(from: manifest, userName: userName)
        let useShard = lic.wrap.shardUsed
        let shardData = useShard ? shardLease?.shard : nil
        let cek = try unwrapCEK_fromLicense(userCode: user32, shard: shardData, license: lic)
        return cek
    }
    // If your Manifest fields are optionals, switch to guard lets
    let aad = manifest.aad
    let wrapped = manifest.wrapped_cek_b64
    let kdfInfo = manifest.kdf_info
    guard !aad.isEmpty, !wrapped.isEmpty, !kdfInfo.isEmpty else {
        throw UserGateError.manifestMissingFields
    }

    let shardLease = try resolveShardLease(from: manifest, userName: userName)
    let useShard = manifest.shard_required == true
    let shardData = useShard ? shardLease?.shard : nil
    let shardB64 = shardLease?.shardB64 ?? shardLease?.shard.base64EncodedString()
    let aadAuth: String
    if useShard, let s = shardB64, !s.isEmpty {
        aadAuth = "\(aad)|shard:\(s)"
        print("KEK: using shard bytes=\(shardData?.count ?? 0) aad=\(aadAuth)")
    } else {
        aadAuth = aad
        if shardLease != nil { print("KEK: ignoring optional shard; manifest.shard_required=false") }
    }
    let kek = deriveKEK(user32: user32, shard: shardData, aad: aadAuth, kdfInfo: kdfInfo)
    let cek = try unwrapCEK_fromManifest(wrappedCEK_B64: wrapped, kek: kek, aad: aadAuth)
    return cek
}
