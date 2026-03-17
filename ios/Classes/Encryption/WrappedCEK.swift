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

enum ShardCacheError: Error {
    case invalidBase64
    case emptyShard
}

enum ShardCache {
    private static var shards: [String: CekShardLease] = [:]
    private static let lock = NSLock()

    static func setShard(modelId rawModelId: String, base64: String, expiresAtMs: Int64?) throws {
        let modelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { throw ShardCacheError.invalidBase64 }

        let normalized = normalizeB64(base64)
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

enum User32StoreErr: Error {
    case notFound
    case badStatus(OSStatus)
}

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

        try delete(account: account, accessGroup: accessGroup)
        let st = SecItemAdd(q as CFDictionary, nil)
        guard st == errSecSuccess else { throw User32StoreErr.badStatus(st) }
    }

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
            throw User32StoreErr.badStatus(st)
        }
        return d
    }
}

enum DistributionMode {
    case unified
    case perDeveloper
}

struct ManifestWrap: Decodable {
    let type: String
    let salt: String?
    let iv: String?
    let rsaScheme: String?
    let rsaKeyId: String?
    let shardRequired: Bool?
}

struct Manifest: Decodable {
    // Legacy fields
    let model_name: String?
    let model_id: String?
    let enc_sha256: String?
    let zip_sha256: String?
    let wrapped_cek_b64: String?
    let kdf_info: String?
    let shard_required: Bool?
    let expiry_epoch_ms: Int?

    // Shared
    let aad: String

    // New unified/per-dev fields
    let distributionMode: String?
    let modelId: String?
    let algo: String?
    let ciphertextLen: Int?
    let gcmIv: String?
    let plainSha256: String?
    let wrappedCek: String?
    let wrap: ManifestWrap?

    var resolvedModelId: String {
        if let v = modelId?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        if let v = model_id?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        if let v = model_name?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        return ""
    }

    var shardRequiredPolicy: Bool {
        return shard_required ?? wrap?.shardRequired ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case model_name
        case model_id
        case enc_sha256
        case zip_sha256
        case wrapped_cek_b64
        case kdf_info
        case shard_required
        case shardRequired
        case expiry_epoch_ms
        case aad

        case distributionMode
        case modelId
        case algo
        case algorithm
        case ciphertextLen
        case gcmIv
        case plainSha256
        case wrappedCek
        case wrap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        model_name = try c.decodeIfPresent(String.self, forKey: .model_name)
        model_id = try c.decodeIfPresent(String.self, forKey: .model_id)
        enc_sha256 = try c.decodeIfPresent(String.self, forKey: .enc_sha256)
        zip_sha256 = try c.decodeIfPresent(String.self, forKey: .zip_sha256)
        wrapped_cek_b64 = try c.decodeIfPresent(String.self, forKey: .wrapped_cek_b64)
        kdf_info = try c.decodeIfPresent(String.self, forKey: .kdf_info)

        let shardSnake = try c.decodeIfPresent(Bool.self, forKey: .shard_required)
        let shardCamel = try c.decodeIfPresent(Bool.self, forKey: .shardRequired)
        shard_required = shardSnake ?? shardCamel
        expiry_epoch_ms = try c.decodeIfPresent(Int.self, forKey: .expiry_epoch_ms)

        aad = try c.decodeIfPresent(String.self, forKey: .aad) ?? ""

        distributionMode = try c.decodeIfPresent(String.self, forKey: .distributionMode)
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId)
        let algoValue = try c.decodeIfPresent(String.self, forKey: .algo)
        let algorithmValue = try c.decodeIfPresent(String.self, forKey: .algorithm)
        algo = algoValue ?? algorithmValue
        ciphertextLen = try c.decodeIfPresent(Int.self, forKey: .ciphertextLen)
        gcmIv = try c.decodeIfPresent(String.self, forKey: .gcmIv)
        plainSha256 = try c.decodeIfPresent(String.self, forKey: .plainSha256)
        wrappedCek = try c.decodeIfPresent(String.self, forKey: .wrappedCek)
        wrap = try c.decodeIfPresent(ManifestWrap.self, forKey: .wrap)
    }
}

struct LicenseDoc: Decodable {
    struct Wrap: Decodable {
        let type: String
        let wrapIv: String
        let salt: String
        let shardUsed: Bool
        let aad: String?
    }

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

enum LicenseCacheError: Error {
    case invalidArgs
    case decodeFailed
}

enum LicenseCache {
    private static var docs: [String: LicenseDoc] = [:]
    private static let lock = NSLock()

    static func setLicense(modelId rawModelId: String, license: LicenseDoc) {
        let modelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        docs[modelId] = license
        docs[license.modelId] = license
        print("LicenseCache: stored license for id=\(modelId) modelId=\(license.modelId)")
    }

    static func setLicense(modelId rawModelId: String, jsonData: Data) throws {
        let doc = try JSONDecoder().decode(LicenseDoc.self, from: jsonData)
        setLicense(modelId: rawModelId, license: doc)
    }

    static func setLicense(modelId rawModelId: String, licenseMap: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: licenseMap, options: [])
        try setLicense(modelId: rawModelId, jsonData: data)
    }

    static func clear(modelId rawModelId: String) {
        let modelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if let doc = docs[modelId] {
            docs.removeValue(forKey: doc.modelId)
        }
        docs.removeValue(forKey: modelId)
    }

    static func clearAll() {
        lock.lock(); defer { lock.unlock() }
        docs.removeAll()
    }

    static func firstMatch(candidates: [String]) -> LicenseDoc? {
        lock.lock(); defer { lock.unlock() }
        for candidate in candidates {
            let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if let doc = docs[key] { return doc }
        }
        return nil
    }
}

private func normalizeB64(_ value: String) -> String {
    var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let missing = (4 - s.count % 4) % 4
    if missing > 0 { s = s.padding(toLength: s.count + missing, withPad: "=", startingAt: 0) }
    return s
}

private func b64DecodeAny(_ value: String) -> Data? {
    if let direct = Data(base64Encoded: value) { return direct }
    return Data(base64Encoded: normalizeB64(value))
}

private func shortSHA256(_ data: Data, prefixBytes: Int = 6) -> String {
    let digest = SHA256.hash(data: data)
    return digest.prefix(prefixBytes).map { String(format: "%02x", $0) }.joined()
}

@available(iOS 14.0, *)
func deriveKEK(user32: Data, shard: Data?, aad: String, kdfInfo: String) -> SymmetricKey {
    var ikm = Data(user32)
    if let shard, !shard.isEmpty {
        ikm.append(shard)
    }
    return HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: ikm),
        salt: Data(aad.utf8),
        info: Data(kdfInfo.utf8),
        outputByteCount: 32
    )
}

private func legacyAadAuthCandidates(
    manifestAad: String,
    useShard: Bool,
    shardB64Raw: String?
) -> [String] {
    var out: [String] = []
    var seen = Set<String>()

    func append(_ value: String) {
        guard !value.isEmpty else { return }
        guard seen.insert(value).inserted else { return }
        out.append(value)
    }

    append(manifestAad)
    guard useShard, let raw0 = shardB64Raw else { return out }
    let raw = raw0.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return out }

    let normalized = normalizeB64(raw)
    let normalizedNoPad = normalized.replacingOccurrences(of: "=", with: "")
    let rawNoPad = raw.replacingOccurrences(of: "=", with: "")

    append("\(manifestAad)|shard:\(raw)")
    append("\(manifestAad)|shard:\(normalized)")
    append("\(manifestAad)|shard:\(rawNoPad)")
    append("\(manifestAad)|shard:\(normalizedNoPad)")

    return out
}

private func unwrapLegacyManifestCEK(wrappedCEKB64: String, kek: SymmetricKey, aad: String) throws -> Data {
    let trimmed = wrappedCEKB64.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let env = Data(base64Encoded: trimmed) else {
        throw UserGateError.manifestMissingFields
    }
    let box = try AES.GCM.SealedBox(combined: env)
    return try AES.GCM.open(box, using: kek, authenticating: Data(aad.utf8))
}

@available(iOS 14.0, *)
private func unwrapV2ManifestCEK(userCode: Data, shard: Data?, manifest: Manifest, effectiveModelId: String) throws -> Data {
    guard let wrap = manifest.wrap,
          wrap.type.hasPrefix("HKDF-SHA256+code"),
          let wrapIvRaw = wrap.iv,
          let wrapSaltRaw = wrap.salt,
          let wrappedRaw = manifest.wrappedCek,
          !manifest.aad.isEmpty else {
        throw UserGateError.manifestMissingFields
    }

    let typeRequiresShard = wrap.type.contains("+shard+")
    let shardRequired = manifest.shardRequiredPolicy || typeRequiresShard
    if shardRequired && shard == nil { throw UserGateError.missingShard }

    let ikm: Data = {
        if shardRequired, let s = shard {
            var out = Data(userCode)
            out.append(s)
            return out
        }
        return userCode
    }()

    guard let wrapIv = b64DecodeAny(wrapIvRaw),
          let salt = b64DecodeAny(wrapSaltRaw),
          let ctTag = b64DecodeAny(wrappedRaw),
          ctTag.count > 16 else {
        throw UserGateError.manifestMissingFields
    }

    let info = Data("model:\(effectiveModelId)".utf8)
    let kek = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: ikm),
        salt: salt,
        info: info,
        outputByteCount: 32
    )

    let ct = ctTag.prefix(ctTag.count - 16)
    let tag = ctTag.suffix(16)
    let box = try AES.GCM.SealedBox(
        nonce: AES.GCM.Nonce(data: wrapIv),
        ciphertext: ct,
        tag: tag
    )
    let cek = try AES.GCM.open(box, using: kek, authenticating: Data(manifest.aad.utf8))
    guard cek.count == 32 else { throw UserGateError.invalidUser32 }
    return cek
}

@available(iOS 14.0, *)
private func unwrapCEK_fromLicense(userCode: Data, shard: Data?, license: LicenseDoc) throws -> Data {
    if license.wrap.shardUsed && shard == nil { throw UserGateError.missingShard }

    let ikm: Data = {
        if let s = shard {
            var out = Data(userCode)
            out.append(s)
            return out
        }
        return userCode
    }()

    guard let salt = b64DecodeAny(license.wrap.salt),
          let iv = b64DecodeAny(license.wrap.wrapIv),
          let combined = b64DecodeAny(license.wrappedCek),
          combined.count > 16 else {
        throw UserGateError.invalidLicense
    }

    let info = Data("model:\(license.modelId)".utf8)
    let kek = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: ikm),
        salt: salt,
        info: info,
        outputByteCount: 32
    )

    let ct = combined.prefix(combined.count - 16)
    let tag = combined.suffix(16)
    let aad = Data((license.wrap.aad ?? "").utf8)
    let box = try AES.GCM.SealedBox(
        nonce: AES.GCM.Nonce(data: iv),
        ciphertext: ct,
        tag: tag
    )
    let cek = try AES.GCM.open(box, using: kek, authenticating: aad)
    guard cek.count == 32 else { throw UserGateError.invalidLicense }
    return cek
}

private func parseISO8601(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let d = formatter.date(from: value) { return d }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}

private func detectDistributionMode(_ manifest: Manifest) -> DistributionMode {
    if let raw = manifest.distributionMode?.lowercased() {
        if raw == "unified" { return .unified }
        if raw == "per-developer" { return .perDeveloper }
    }

    if let wrapType = manifest.wrap?.type {
        if wrapType == "RSA-OAEP-256" || wrapType == "external" { return .unified }
        if wrapType.hasPrefix("HKDF-SHA256+code") { return .perDeveloper }
    }

    if let wrappedLegacy = manifest.wrapped_cek_b64, !wrappedLegacy.isEmpty {
        return .perDeveloper
    }

    return .unified
}

private func licenseCandidates(manifest: Manifest, effectiveModelId: String, userName: String) -> [String] {
    var out: [String] = []
    let sanitizedUser = UserCodeUtils.sanitize(userName: userName)

    for v in [effectiveModelId, manifest.modelId, manifest.model_id, manifest.model_name, sanitizedUser] {
        if let s = v?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            out.append(s)
        }
    }
    return Array(Set(out))
}

private func loadLicenseIfPresent(manifest: Manifest, effectiveModelId: String, userName: String, in bundle: Bundle = .main) -> LicenseDoc? {
    let candidates = licenseCandidates(manifest: manifest, effectiveModelId: effectiveModelId, userName: userName)

    if let cached = LicenseCache.firstMatch(candidates: candidates) {
        return cached
    }

    for c in candidates {
        let names = ["\(c).ios.license", "\(c).license", c]
        for n in names {
            if let url = bundle.url(forResource: n, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let lic = try? JSONDecoder().decode(LicenseDoc.self, from: data) {
                LicenseCache.setLicense(modelId: c, license: lic)
                return lic
            }
        }
    }
    return nil
}

// Errors used by caller
enum UserGateError: Error {
    case manifestMissingFields
    case invalidUser32
    case missingShard
    case shardExpired
    case missingLicense
    case invalidLicense
    case licenseExpired
}

private func activeShard(for manifest: Manifest, userName: String, effectiveModelId: String, now: Date = Date()) -> CekShardLease? {
    let sanitizedUser = UserCodeUtils.sanitize(userName: userName)
    let candidates = [effectiveModelId, manifest.modelId, manifest.model_id, manifest.model_name, sanitizedUser]
        .compactMap { $0 }
    print("Shard lookup candidates: \(candidates)")
    return ShardCache.activeShard(for: candidates, now: now)
}

@available(iOS 14.0, *)
private func resolveShardLease(from manifest: Manifest, userName: String, effectiveModelId: String, now: Date = Date()) throws -> CekShardLease? {
    if let manifestExpiry = manifest.expiry_epoch_ms {
        let expiryDate = Date(timeIntervalSince1970: TimeInterval(manifestExpiry) / 1000.0)
        if now >= expiryDate {
            print("Shard: manifest expiry reached for \(effectiveModelId)")
            throw UserGateError.shardExpired
        }
    }

    let lease = activeShard(for: manifest, userName: userName, effectiveModelId: effectiveModelId, now: now)
    if manifest.shardRequiredPolicy && lease == nil {
        print("Shard: required but missing for \(effectiveModelId)")
        throw UserGateError.missingShard
    }
    if let lease = lease, lease.isExpired(now: now) {
        print("Shard: found but expired for \(effectiveModelId)")
        throw UserGateError.shardExpired
    }
    return lease
}

@available(iOS 14.0, *)
private func resolveCEK(manifest: Manifest, userName: String, effectiveModelId: String, user32: Data) throws -> Data {
    guard user32.count == 32 else { throw UserGateError.invalidUser32 }

    switch detectDistributionMode(manifest) {
    case .unified:
        guard let license = loadLicenseIfPresent(manifest: manifest, effectiveModelId: effectiveModelId, userName: userName) else {
            throw UserGateError.missingLicense
        }
        let expectedIds = Set(
            [effectiveModelId, manifest.modelId, manifest.model_id, manifest.model_name]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        if !expectedIds.isEmpty && !expectedIds.contains(license.modelId) {
            throw UserGateError.invalidLicense
        }
        if let expectedHash = manifest.plainSha256, !expectedHash.isEmpty, license.plainSha256 != expectedHash {
            throw UserGateError.invalidLicense
        }
        if let algo = manifest.algo, !algo.isEmpty, license.algo != algo {
            throw UserGateError.invalidLicense
        }
        if let expRaw = license.expiresAt, !expRaw.isEmpty {
            guard let exp = parseISO8601(expRaw) else { throw UserGateError.invalidLicense }
            if exp <= Date() { throw UserGateError.licenseExpired }
        }

        let lease = try resolveShardLease(from: manifest, userName: userName, effectiveModelId: effectiveModelId)
        let shardRequired = manifest.shardRequiredPolicy || license.wrap.shardUsed
        if shardRequired && lease == nil { throw UserGateError.missingShard }
        let shardData = license.wrap.shardUsed ? lease?.shard : nil
        return try unwrapCEK_fromLicense(userCode: user32, shard: shardData, license: license)

    case .perDeveloper:
        if let license = loadLicenseIfPresent(manifest: manifest, effectiveModelId: effectiveModelId, userName: userName) {
            do {
                let expectedIds = Set(
                    [effectiveModelId, manifest.modelId, manifest.model_id, manifest.model_name]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
                if !expectedIds.isEmpty && !expectedIds.contains(license.modelId) {
                    throw UserGateError.invalidLicense
                }
                if let expectedHash = manifest.plainSha256, !expectedHash.isEmpty, license.plainSha256 != expectedHash {
                    throw UserGateError.invalidLicense
                }
                if let algo = manifest.algo, !algo.isEmpty, license.algo != algo {
                    throw UserGateError.invalidLicense
                }
                if let expRaw = license.expiresAt, !expRaw.isEmpty {
                    guard let exp = parseISO8601(expRaw) else { throw UserGateError.invalidLicense }
                    if exp <= Date() { throw UserGateError.licenseExpired }
                }

                let lease = try resolveShardLease(from: manifest, userName: userName, effectiveModelId: effectiveModelId)
                let shardRequired = manifest.shardRequiredPolicy || license.wrap.shardUsed
                if shardRequired && lease == nil { throw UserGateError.missingShard }
                let shardData = license.wrap.shardUsed ? lease?.shard : nil
                let cek = try unwrapCEK_fromLicense(userCode: user32, shard: shardData, license: license)
                print("CEK license unwrap ok model=\(effectiveModelId) licenseModel=\(license.modelId) shardUsed=\(license.wrap.shardUsed)")
                return cek
            } catch {
                print("CEK license unwrap failed for \(effectiveModelId); falling back to legacy manifest path: \(error)")
            }
        }

        if let wrapped = manifest.wrapped_cek_b64,
           let kdfInfo = manifest.kdf_info,
           !wrapped.isEmpty,
           !kdfInfo.isEmpty,
           !manifest.aad.isEmpty {
            let lease = try resolveShardLease(from: manifest, userName: userName, effectiveModelId: effectiveModelId)
            let useShard = manifest.shardRequiredPolicy
            let shardData = useShard ? lease?.shard : nil
            let shardB64 = lease?.shardB64 ?? lease?.shard.base64EncodedString()

            if useShard, shardData == nil {
                throw UserGateError.missingShard
            }

            let userHash = shortSHA256(user32)
            let shardHash = shardData.map { shortSHA256($0) } ?? "none"
            let wrappedHash = shortSHA256(Data(wrapped.utf8))
            print("CEK legacy inputs model=\(effectiveModelId) user32=\(userHash) shard=\(shardHash) wrapped=\(wrappedHash) kdfInfo=\(kdfInfo)")

            let aadCandidates = legacyAadAuthCandidates(
                manifestAad: manifest.aad,
                useShard: useShard,
                shardB64Raw: shardB64
            )

            var keyInputs: [(label: String, shard: Data?)] = [("user32+aad", nil)]
            if useShard, let shard = shardData {
                keyInputs.append(("user32+shard+aad", shard))
            }

            var attempts: [String] = []
            for (aadIdx, aadAuth) in aadCandidates.enumerated() {
                for keyInput in keyInputs {
                    do {
                        let kek = deriveKEK(
                            user32: user32,
                            shard: keyInput.shard,
                            aad: aadAuth,
                            kdfInfo: kdfInfo
                        )
                        let cek = try unwrapLegacyManifestCEK(
                            wrappedCEKB64: wrapped,
                            kek: kek,
                            aad: aadAuth
                        )
                        print("CEK legacy unwrap ok model=\(effectiveModelId) aadMode=\(aadAuth == manifest.aad ? "manifest" : "manifest+shard") keyMode=\(keyInput.label)")
                        return cek
                    } catch let err as NSError {
                        attempts.append("aad=\(aadIdx) key=\(keyInput.label) err=\(err.domain)#\(err.code)")
                    } catch {
                        attempts.append("aad=\(aadIdx) key=\(keyInput.label) err=\(error)")
                    }
                }
            }

            throw NSError(
                domain: "CEKAuth",
                code: -5,
                userInfo: [
                    NSLocalizedDescriptionKey: "Legacy CEK unwrap failed for \(effectiveModelId). Tried \(attempts.joined(separator: " | "))"
                ]
            )
        }

        let lease = try resolveShardLease(from: manifest, userName: userName, effectiveModelId: effectiveModelId)
        let shard = manifest.shardRequiredPolicy ? lease?.shard : nil
        return try unwrapV2ManifestCEK(userCode: user32, shard: shard, manifest: manifest, effectiveModelId: effectiveModelId)
    }
}

/// Async supplier version (server or side-loaded async)
@available(iOS 14.0, *)
func obtainCEK_UserCodeGate(
    manifest: Manifest,
    userName: String,
    modelId: String?,
    user32Supplier: () async throws -> Data
) async throws -> Data {
    let effectiveModelId = [modelId, manifest.resolvedModelId]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""
    let acct = UserCodeUtils.account(userName: userName, modelId: effectiveModelId.isEmpty ? nil : effectiveModelId)

    let user32: Data
    if let cached = try? User32Store.load(account: acct) {
        user32 = cached
    } else {
        let fetched = try await user32Supplier()
        guard fetched.count == 32 else { throw UserGateError.invalidUser32 }
        try User32Store.save(fetched, account: acct, requireBiometrics: false)
        user32 = fetched
    }

    return try resolveCEK(manifest: manifest, userName: userName, effectiveModelId: effectiveModelId, user32: user32)
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
    let effectiveModelId = [modelId, manifest.resolvedModelId]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""
    let acct = UserCodeUtils.account(userName: userName, modelId: effectiveModelId.isEmpty ? nil : effectiveModelId)

    let user32: Data
    if let cached = try? User32Store.load(account: acct) {
        user32 = cached
        print("User32 keychain hit account=\(acct) hash=\(shortSHA256(cached))")
    } else {
        let fetched = try user32Provider()
        guard fetched.count == 32 else { throw UserGateError.invalidUser32 }
        try User32Store.save(fetched, account: acct, requireBiometrics: false)
        user32 = fetched
        print("User32 provider fetch account=\(acct) hash=\(shortSHA256(fetched))")
    }

    return try resolveCEK(manifest: manifest, userName: userName, effectiveModelId: effectiveModelId, user32: user32)
}
