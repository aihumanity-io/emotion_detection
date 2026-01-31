import Cocoa
import FlutterMacOS
import CoreML
import CoreImage
import ImageIO
import Vision
import CryptoKit
import Security
import ZIPFoundation

public class EmotionDetectionPlugin: NSObject, FlutterPlugin {
  private var runtimeChannel: FlutterMethodChannel!

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Keep the existing public API channel.
    let channel = FlutterMethodChannel(name: "emotion_detection", binaryMessenger: registrar.messenger)
    let instance = EmotionDetectionPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Add the model runtime channel used by Dart ModelRuntime/UserCodeChannel.
    let runtime = FlutterMethodChannel(name: "face_emotion_detection", binaryMessenger: registrar.messenger)
    instance.runtimeChannel = runtime
    registrar.addMethodCallDelegate(instance, channel: runtime)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "getPlatformVersion" {
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
      return
    }

    // Runtime methods
    switch call.method {
    case "setUserCode":
      handleSetUserCode(call: call, result: result)
    case "clearUserCode":
      handleClearUserCode(call: call, result: result)
    case "setKeyShard":
      handleSetKeyShard(call: call, result: result)
    case "clearKeyShard":
      handleClearKeyShard(call: call, result: result)
    case "predict":
      handlePredict(call: call, result: result)
    case "registerModel", "warmUp":
      // No-op for macOS; models are loaded lazily on first predict.
      result(true)
    case "unload":
      // Simple unload: drop cached model.
      if let args = call.arguments as? [String: Any], let modelId = args["modelId"] as? String {
        ModelCache.shared.unload(modelId: modelId)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - User code + shard handlers

extension EmotionDetectionPlugin {
  private func handleSetUserCode(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let userName = args["userName"] as? String,
          let userCodeB64 = args["userCodeB64"] as? String else {
      return result(FlutterError(code: "invalid_args", message: "userName/userCodeB64 required", details: nil))
    }
    let requireBiometrics = (args["requireBiometrics"] as? Bool) ?? false
    let modelId = args["modelId"] as? String
    do {
      let acct = UserCodeUtils.account(userName: userName, modelId: modelId)
      guard let decoded = Data(base64Encoded: userCodeB64.trimmingCharacters(in: .whitespacesAndNewlines)), decoded.count == 32 else {
        return result(FlutterError(code: "invalid_args", message: "userCodeB64 must be 32-byte base64", details: nil))
      }
      try User32Store.save(decoded, account: acct, requireBiometrics: requireBiometrics)
      EmotionDetectionPluginState.currentUserName = UserCodeUtils.sanitize(userName: userName)
      result(nil)
    } catch {
      result(FlutterError(code: "user_code_error", message: error.localizedDescription, details: nil))
    }
  }

  private func handleClearUserCode(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let userName = args["userName"] as? String else {
      return result(FlutterError(code: "invalid_args", message: "userName required", details: nil))
    }
    let modelId = args["modelId"] as? String
    do {
      let acct = UserCodeUtils.account(userName: userName, modelId: modelId)
      try User32Store.delete(account: acct)
      result(nil)
    } catch {
      result(FlutterError(code: "user_code_error", message: error.localizedDescription, details: nil))
    }
  }

  private func handleSetKeyShard(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let modelId = args["modelId"] as? String,
          let keyShardB64 = args["keyShardB64"] as? String else {
      return result(FlutterError(code: "invalid_args", message: "modelId/keyShardB64 required", details: nil))
    }
    let exp = args["expiresAtMs"] as? Int64
    do {
      try ShardCache.setShard(modelId: modelId, base64: keyShardB64, expiresAtMs: exp)
      result(nil)
    } catch {
      result(FlutterError(code: "shard_store_error", message: error.localizedDescription, details: nil))
    }
  }

  private func handleClearKeyShard(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let modelId = args["modelId"] as? String else {
      return result(FlutterError(code: "invalid_args", message: "modelId required", details: nil))
    }
    ShardCache.clearShard(modelId: modelId)
    result(nil)
  }
}

// MARK: - Prediction

extension EmotionDetectionPlugin {
  private func handlePredict(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let modelId = args["modelId"] as? String,
          let inputs = args["inputs"] as? [String: Any]
    else { return result(FlutterError(code: "invalid_args", message: "modelId/inputs required", details: nil)) }

    do {
      // Decode image
      guard let cgImage = try makeCGImage(from: inputs) else {
        return result(FlutterError(code: "invalid_args", message: "image missing or invalid", details: nil))
      }

      // Detect face with Vision on macOS; fallback to center-crop square
      let faceRect = detectFace(in: cgImage) ?? centerSquare(in: cgImage)
      guard let crop = cgImage.cropping(to: faceRect) else {
        return result(FlutterError(code: "crop_error", message: "failed to crop face", details: nil))
      }

      // Load model lazily
      let model = try ModelCache.shared.model(for: modelId)

      // Convert to pixel buffer and run prediction
      guard let pb = crop.pixelBuffer(width: 224, height: 224, orientation: .up) else {
        return result(FlutterError(code: "pixelbuffer_error", message: "could not build pixel buffer", details: nil))
      }
      let provider = try MLDictionaryFeatureProvider(dictionary: ["input_1": MLFeatureValue(pixelBuffer: pb)])
      let out = try model.prediction(from: provider)
      guard let m = out.featureValue(for: "Identity")?.multiArrayValue else {
        return result([:])
      }
      let scores = m.toFloatArray()
      let labels = ["Anger","Disgust","Fear","Happiness","Neutral","Sadness","Surprise"]
      var map: [String: Double] = [:]
      for i in 0..<min(scores.count, labels.count) { map[labels[i]] = Double(scores[i]) }
      result(map)
    } catch {
      result(FlutterError(code: "predict_error", message: error.localizedDescription, details: nil))
    }
  }

  private func makeCGImage(from inputs: [String: Any]) throws -> CGImage? {
    // Accept either compressed image bytes or raw 4-channel buffers
    if let data = (inputs["imageBytes"] as? FlutterStandardTypedData)?.data {
      let cf = data as CFData
      guard let src = CGImageSourceCreateWithData(cf, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
      return img
    }

    let width = (inputs["width"] as? NSNumber)?.intValue
    let height = (inputs["height"] as? NSNumber)?.intValue
    if let w = width, let h = height {
      if let bgra = (inputs["bgra"] as? FlutterStandardTypedData)?.data {
        let info = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
        return cgImageFromBytes(bgra, width: w, height: h, bitmapInfo: info)
      }
      if let rgba = (inputs["rgba"] as? FlutterStandardTypedData)?.data {
        let info = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        return cgImageFromBytes(rgba, width: w, height: h, bitmapInfo: info)
      }
    }
    return nil
  }

  private func cgImageFromBytes(_ data: Data, width: Int, height: Int, bitmapInfo: CGBitmapInfo) -> CGImage? {
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let cfdata = data as CFData
    guard let provider = CGDataProvider(data: cfdata) else { return nil }
    return CGImage(width: width,
                   height: height,
                   bitsPerComponent: 8,
                   bitsPerPixel: 32,
                   bytesPerRow: bytesPerRow,
                   space: colorSpace,
                   bitmapInfo: bitmapInfo,
                   provider: provider,
                   decode: nil,
                   shouldInterpolate: true,
                   intent: .defaultIntent)
  }

  private func detectFace(in image: CGImage) -> CGRect? {
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    let req = VNDetectFaceRectanglesRequest()
    do {
      try handler.perform([req])
      guard let obs = (req.results as? [VNFaceObservation])?.first else { return nil }
      // Convert normalized [0,1] rect (origin at bottom-left) to image pixels
      let w = CGFloat(image.width)
      let h = CGFloat(image.height)
      let r = obs.boundingBox
      let x = r.origin.x * w
      let y = (1.0 - r.origin.y - r.size.height) * h
      var rect = CGRect(x: x, y: y, width: r.size.width * w, height: r.size.height * h)
      // Expand to square around center
      rect = square(rect: rect, maxSize: CGSize(width: w, height: h))
      return rect.integral
    } catch {
      return nil
    }
  }

  private func square(rect: CGRect, maxSize: CGSize) -> CGRect {
    let side = max(rect.width, rect.height)
    var cx = rect.midX
    var cy = rect.midY
    var sq = CGRect(x: cx - side/2, y: cy - side/2, width: side, height: side)
    if sq.minX < 0 { cx += -sq.minX; sq.origin.x = 0 }
    if sq.minY < 0 { cy += -sq.minY; sq.origin.y = 0 }
    if sq.maxX > maxSize.width { sq.origin.x = maxSize.width - sq.width }
    if sq.maxY > maxSize.height { sq.origin.y = maxSize.height - sq.height }
    return sq
  }

  private func centerSquare(in image: CGImage) -> CGRect {
    let w = CGFloat(image.width)
    let h = CGFloat(image.height)
    let side = min(w, h)
    return CGRect(x: (w - side)/2, y: (h - side)/2, width: side, height: side)
  }
}

// MARK: - Model cache and loading

final class ModelCache {
  static let shared = ModelCache()
  private var cache: [String: MLModel] = [:]
  private let lock = NSLock()

  func model(for modelId: String) throws -> MLModel {
    lock.lock(); defer { lock.unlock() }
    if let m = cache[modelId] { return m }
    let baseName: String
    if modelId.contains("mobilenetv1_fer") { baseName = "mobilenetv1_fer2024-11-06-08-48-50" }
    else if modelId.contains("aih_fer") { baseName = "aih_fer20250115" }
    else { baseName = "mobilenetv1_fer2024-11-06-08-48-50" }

    // Load manifest and unwrap CEK using user32 (keychain) and optional shard
    let bundle = Bundle(for: EmotionDetectionPlugin.self)
    let manifest = try loadManifestJSON(fromBundle: baseName + ".manifest.json", in: bundle)
    let modelIdentifier = manifest.model_name
    let userName = UserCodeUtils.sanitize(userName: EmotionDetectionPluginState.currentUserName)
    let cek = try obtainCEK_UserCodeGateSync(
      manifest: manifest,
      userName: userName,
      modelId: modelIdentifier,
      user32Provider: { try UserCodeUtils.loadUser32(userName: userName, modelId: modelIdentifier) }
    )
    let model = try EncryptedModelLoader.loadFromBundle(
      baseName: baseName,
      configuration: MLModelConfiguration(),
      framework: bundle,
      obtainKey: { SymmetricKey(data: cek) }
    )
    cache[modelId] = model
    return model
  }

  func unload(modelId: String) { lock.lock(); defer { lock.unlock() }; cache.removeValue(forKey: modelId) }
}

enum EmotionDetectionPluginState { static var currentUserName: String = "dev@tartalabs.io" }

// MARK: - Small helpers/types reused from iOS

enum UserCodeUtils {
  static func sanitize(userName: String) -> String { userName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
  static func account(userName: String, modelId: String?) -> String {
    let base = sanitize(userName: userName)
    if let mid = modelId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !mid.isEmpty { return "\(base)|\(mid)" }
    return base
  }
  static func loadUser32(userName: String, modelId: String?) throws -> Data {
    let acct = account(userName: userName, modelId: modelId)
    if let cached = try? User32Store.load(account: acct) { return cached }
    // optional: side-load from bundle if present
    // Fallback: throw if missing
    throw NSError(domain: "User32", code: -1, userInfo: [NSLocalizedDescriptionKey: "User32 not found for \(acct)"])
  }
}

enum User32StoreErr: Error { case badStatus(OSStatus) }
enum User32Store {
  static let service = "com.creataai.emotionsdk.user32"
  static func delete(account: String) throws {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
    ]
    let st = SecItemDelete(q as CFDictionary)
    guard st == errSecSuccess || st == errSecItemNotFound else { throw User32StoreErr.badStatus(st) }
  }
  static func save(_ data: Data, account: String, requireBiometrics: Bool) throws {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecValueData as String: data
    ]
    if requireBiometrics {
      if let ac = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.biometryCurrentSet], nil) {
        q.removeValue(forKey: kSecAttrAccessible as String)
        q[kSecAttrAccessControl as String] = ac
      }
    }
    try? delete(account: account)
    let st = SecItemAdd(q as CFDictionary, nil)
    guard st == errSecSuccess else { throw User32StoreErr.badStatus(st) }
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
    guard st == errSecSuccess, let d = item as? Data else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(st)) }
    return d
  }
}

struct CekShardLease { let shard: Data; let shardB64: String?; let expiresAt: Date?; func isExpired(now: Date = Date()) -> Bool { guard let exp = expiresAt else { return false }; return now >= exp } }
enum ShardCacheError: Error { case invalidBase64, emptyShard }
enum ShardCache {
  private static var shards: [String: CekShardLease] = [:]
  private static let lock = NSLock()
  static func setShard(modelId rawModelId: String, base64: String, expiresAtMs: Int64?) throws {
    let modelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !modelId.isEmpty else { throw ShardCacheError.invalidBase64 }
    let normalized = normalizeB64(base64)
    guard let data = Data(base64Encoded: normalized) else { throw ShardCacheError.invalidBase64 }
    guard !data.isEmpty else { throw ShardCacheError.emptyShard }
    let expiry = expiresAtMs != nil ? Date(timeIntervalSince1970: TimeInterval(expiresAtMs!) / 1000.0) : nil
    let lease = CekShardLease(shard: data, shardB64: base64, expiresAt: expiry)
    lock.lock(); defer { lock.unlock() }
    shards[modelId] = lease
  }
  static func clearShard(modelId rawModelId: String) { let id = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines); guard !id.isEmpty else { return }; lock.lock(); defer { lock.unlock() }; shards.removeValue(forKey: id) }
  static func activeShard(for identifiers: [String], now: Date = Date()) -> CekShardLease? {
    lock.lock(); defer { lock.unlock() }
    for id in identifiers { let t = id.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty, let lease = shards[t] else { continue }; if lease.isExpired(now: now) { shards.removeValue(forKey: t); continue }; return lease }
    return nil
  }
  static func normalizeB64(_ value: String) -> String { var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); let missing = (4 - s.count % 4) % 4; if missing > 0 { s = s.padding(toLength: s.count + missing, withPad: "=", startingAt: 0) }; return s }
}

// MARK: - Minimal encryption + manifest loaders

struct ModelManifest: Decodable {
  let model_name: String
  let model_id: String?
  let version: String
  let zip_sha256: String
  let enc_sha256: String
  let aad: String
  let algorithm: String
  let combined_format: String
  let nonce_len: Int
  let tag_len: Int
  let created_at: String
  let wrapped_cek_b64: String
  let kdf_info: String
  let shard_required: Bool?
  let shardRequired: Bool?
  let expiry_epoch_ms: Int?
}

enum ManifestLoadError: Error { case notFound, readFailed, decodeFailed(Error) }
func loadManifestJSON(fromBundle name: String, in bundle: Bundle = .main) throws -> ModelManifest {
  if let url = bundle.url(forResource: name, withExtension: nil) { return try decodeManifest(at: url) }
  let ns = name as NSString
  let base = ns.deletingPathExtension
  let ext  = ns.pathExtension
  var candidates: [(String, String?)] = []
  if ext == "manifest" { candidates.append((base, "manifest.json")) }
  candidates += [("\(base)-shard", "manifest.json"), ("\(base)_shard", "manifest.json"), (name, "json"), (base, "manifest.json"), (base, "json"), (name, nil)]
  let bundles: [Bundle] = [bundle] + Bundle.allBundles + Bundle.allFrameworks
  for b in bundles { for (n,e) in candidates { if let u = b.url(forResource: n, withExtension: e) { return try decodeManifest(at: u) } } }
  throw ManifestLoadError.notFound
}
private func decodeManifest(at url: URL) throws -> ModelManifest { do { let d = try Data(contentsOf: url); return try JSONDecoder().decode(ModelManifest.self, from: d) } catch let err as DecodingError { throw ManifestLoadError.decodeFailed(err) } catch { throw ManifestLoadError.readFailed } }

enum CryptoError: Error { case badCiphertext }
struct ModelCrypto { static func decrypt(combined: Data, key: SymmetricKey, aad: Data) throws -> Data { let box = try AES.GCM.SealedBox(combined: combined); return try AES.GCM.open(box, using: key, authenticating: aad) }; static func sha256Hex(_ data: Data) -> String { let dig = SHA256.hash(data: data); return dig.map { String(format: "%02x", $0) }.joined() } }

enum FileErr: Error { case missing, unzip, notFound, noMLPackage }
struct FileIO {
  static func bundleURL(name: String, ext: String, in bundle: Bundle) throws -> URL { guard let url = bundle.url(forResource: name, withExtension: ext) else { throw FileErr.missing }; return url }
  static func tempDir(_ name: String = UUID().uuidString) throws -> URL { let d = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
  static func unzip(_ zipURL: URL, to dest: URL) throws { let fm = FileManager.default; try fm.createDirectory(at: dest, withIntermediateDirectories: true); guard let archive = Archive(url: zipURL, accessMode: .read) else { throw FileErr.unzip }; for entry in archive { if entry.path.hasPrefix("__MACOSX/") || entry.path.hasPrefix("._") { continue }; let outURL = dest.appendingPathComponent(entry.path); switch entry.type { case .directory: try fm.createDirectory(at: outURL, withIntermediateDirectories: true); case .file: try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true); if fm.fileExists(atPath: outURL.path) { try fm.removeItem(at: outURL) }; fm.createFile(atPath: outURL.path, contents: nil); let handle = try FileHandle(forWritingTo: outURL); defer { try? handle.close() }; try archive.extract(entry, bufferSize: 32 * 1024, consumer: { data in try handle.write(contentsOf: data) }); default: continue } } }
  static func findMLPackage(in dir: URL) throws -> URL { if let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) { for case let u as URL in e where u.pathExtension == "mlpackage" { return u } } ; throw FileErr.noMLPackage }
}
enum EncryptedLoadError: Error { case integrityFailed }
struct EncryptedModelLoader {
  static func loadFromBundle(baseName: String, configuration: MLModelConfiguration, framework: Bundle, obtainKey: () throws -> SymmetricKey) throws -> MLModel {
    let manifestURL = try FileIO.bundleURL(name: baseName, ext: "manifest.json", in: framework)
    let encURL = try FileIO.bundleURL(name: baseName, ext: "enc", in: framework)
    let manifest = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: manifestURL))
    let encData = try Data(contentsOf: encURL)
    let encHash = ModelCrypto.sha256Hex(encData)
    guard encHash == manifest.enc_sha256 else { throw EncryptedLoadError.integrityFailed }
    let key = try obtainKey(); let aad = Data(manifest.aad.utf8)
    let zipData = try ModelCrypto.decrypt(combined: encData, key: key, aad: aad)
    let zipHash = ModelCrypto.sha256Hex(zipData)
    guard zipHash == manifest.zip_sha256 else { throw EncryptedLoadError.integrityFailed }
    let work = try FileIO.tempDir("model_dec_\(baseName)"); let zipOut = work.appendingPathComponent("model_\(baseName).zip"); try zipData.write(to: zipOut, options: .atomic); try FileIO.unzip(zipOut, to: work)
    let pkg = try FileIO.findMLPackage(in: work); let compiled = try MLModel.compileModel(at: pkg)
    return try MLModel(contentsOf: compiled, configuration: configuration)
  }
}

// MARK: - MLMultiArray → [Float]
extension MLMultiArray {
  func toFloatArray() -> [Float] {
    let count = self.count
    var result = [Float](repeating: 0, count: count)
    let ptr = self.dataPointer.assumingMemoryBound(to: Float.self)
    for i in 0..<count { result[i] = ptr[i] }
    return result
  }
}

// MARK: - CEK unwrap (UserCode gate + optional shard)

private func deriveKEK(user32: Data, shard: Data?, aad: String, kdfInfo: String) -> SymmetricKey {
  // Packaging binds shard via AAD/salt, not in IKM.
  return HKDF<SHA256>.deriveKey(
    inputKeyMaterial: SymmetricKey(data: user32),
    salt: Data(aad.utf8),
    info: Data(kdfInfo.utf8),
    outputByteCount: 32
  )
}

private func unwrapCEK_fromManifest(wrappedCEK_B64: String, kek: SymmetricKey, aad: String) throws -> Data {
  let env = Data(base64Encoded: wrappedCEK_B64.trimmingCharacters(in: .whitespacesAndNewlines))!
  let box = try AES.GCM.SealedBox(combined: env)
  return try AES.GCM.open(box, using: kek, authenticating: Data(aad.utf8))
}

private func obtainCEK_UserCodeGateSync(
  manifest: ModelManifest,
  userName: String,
  modelId: String?,
  user32Provider: () throws -> Data
) throws -> Data {
  // Load or import user32
  let acct = UserCodeUtils.account(userName: userName, modelId: modelId)
  let user32: Data
  if let cached = try? User32Store.load(account: acct) {
    user32 = cached
  } else {
    let fetched = try user32Provider()
    guard fetched.count == 32 else { throw NSError(domain: "User32", code: -2) }
    try User32Store.save(fetched, account: acct, requireBiometrics: false)
    user32 = fetched
  }

  // Resolve shard lease if present and not expired
  let candidates = [manifest.model_id, manifest.model_name, UserCodeUtils.sanitize(userName: userName)].compactMap { $0 }
  let lease = ShardCache.activeShard(for: candidates)
  let useShard = (manifest.shard_required ?? manifest.shardRequired) == true
  let shardData = useShard ? lease?.shard : nil
  let shardB64 = lease?.shardB64 ?? lease?.shard.base64EncodedString()
  let aadAuth: String
  if useShard, let s = shardB64, !s.isEmpty {
    aadAuth = "\(manifest.aad)|shard:\(s)"
  } else {
    aadAuth = manifest.aad
  }

  let kek = deriveKEK(user32: user32, shard: shardData, aad: aadAuth, kdfInfo: manifest.kdf_info)
  let cek = try unwrapCEK_fromManifest(wrappedCEK_B64: manifest.wrapped_cek_b64, kek: kek, aad: aadAuth)
  return cek
}
