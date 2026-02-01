import Cocoa
import FlutterMacOS
import CoreML
import CoreImage
import ImageIO
import Vision
import AVFoundation
import VideoToolbox
import CryptoKit
import Security
import ZIPFoundation

public class EmotionDetectionPlugin: NSObject, FlutterPlugin {
  private var runtimeChannel: FlutterMethodChannel!
  private var cameraEventChannel: FlutterEventChannel!
  private var cameraEventSink: FlutterEventSink?

  // Camera session state (macOS only)
  private var captureSession: AVCaptureSession?
  private var videoOutput: AVCaptureVideoDataOutput?
  private let cameraQueue = DispatchQueue(label: "com.tartalabs.emotion.camera.queue")
  private let ciContext = CIContext(options: nil)
  private var isProcessingFrame = false
  private var currentModelId: String = "mobilenetv1_fer2024-11-06-08-48-50"

  // Preview window/layer for macOS camera
  private var previewWindow: NSWindow?
  private var previewLayer: AVCaptureVideoPreviewLayer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Keep the existing public API channel.
    let channel = FlutterMethodChannel(name: "emotion_detection", binaryMessenger: registrar.messenger)
    let instance = EmotionDetectionPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Add the model runtime channel used by Dart ModelRuntime/UserCodeChannel.
    let runtime = FlutterMethodChannel(name: "face_emotion_detection", binaryMessenger: registrar.messenger)
    instance.runtimeChannel = runtime
    registrar.addMethodCallDelegate(instance, channel: runtime)

    // Camera prediction stream channel (macOS)
    let stream = FlutterEventChannel(name: "face_emotion_detection/camera", binaryMessenger: registrar.messenger)
    stream.setStreamHandler(instance)
    instance.cameraEventChannel = stream
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
    case "showMacCameraPreview":
      if let args = call.arguments as? [String: Any], let mid = args["modelId"] as? String, !mid.isEmpty { currentModelId = mid }
      showPreviewWindow()
      result(nil)
    case "hideMacCameraPreview":
      hidePreviewWindow()
      result(nil)
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

// MARK: - Camera stream (EventChannel)

extension EmotionDetectionPlugin: FlutterStreamHandler, AVCaptureVideoDataOutputSampleBufferDelegate {
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    cameraEventSink = events
    if let args = arguments as? [String: Any], let mid = args["modelId"] as? String, !mid.isEmpty {
      currentModelId = mid
    }
    startCameraSession()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopCameraSession()
    cameraEventSink = nil
    return nil
  }

  private func startCameraSession() {
    // Request permission if needed
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    if status == .notDetermined {
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async { if granted { self.configureAndStartSession() } else { self.cameraEventSink?([String: Double]()) } }
      }
      return
    } else if status == .authorized {
      configureAndStartSession()
    } else {
      cameraEventSink?([String: Double]())
    }
  }

  private func configureAndStartSession() {
    if captureSession != nil { return }
    let session = AVCaptureSession()
    session.beginConfiguration()
    session.sessionPreset = .high
    let selectedDevice: AVCaptureDevice?
    if #available(macOS 14.0, *) {
      let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.continuityCamera, .builtInWideAngleCamera, .externalUnknown],
        mediaType: .video,
        position: .unspecified
      )
      selectedDevice = discovery.devices.first
    } else {
      selectedDevice = AVCaptureDevice.default(for: .video)
    }
    guard let device = selectedDevice,
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      session.commitConfiguration(); return
    }
    session.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    if session.canAddOutput(output) {
      session.addOutput(output)
    }
    output.setSampleBufferDelegate(self, queue: cameraQueue)
    if let conn = output.connection(with: .video), conn.isVideoOrientationSupported {
      conn.videoOrientation = .portrait
    }
    session.commitConfiguration()
    captureSession = session
    videoOutput = output
    session.startRunning()
  }

  private func stopCameraSession() {
    guard let session = captureSession else { return }
    session.stopRunning()
    videoOutput?.setSampleBufferDelegate(nil, queue: nil)
    videoOutput = nil
    captureSession = nil
    isProcessingFrame = false
    // Do not close preview window here; caller manages via hideMacCameraPreview.
  }

  public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard cameraEventSink != nil, !isProcessingFrame else { return }
    isProcessingFrame = true
    defer { isProcessingFrame = false }

    guard let pb: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    var cgImage: CGImage?
    // Prefer VTCreateCGImageFromCVPixelBuffer for speed
    if VTCreateCGImageFromCVPixelBuffer(pb, options: nil, imageOut: &cgImage) != kCVReturnSuccess || cgImage == nil {
      let ci = CIImage(cvPixelBuffer: pb)
      cgImage = ciContext.createCGImage(ci, from: ci.extent)
    }
    guard let img = cgImage else { return }

    do {
      // Detect/crop face
      let faceRect = detectFace(in: img) ?? centerSquare(in: img)
      guard let crop = img.cropping(to: faceRect) else { return }
      guard let facePB = crop.pixelBuffer(width: 224, height: 224, orientation: .up) else { return }
      let model = try ModelCache.shared.model(for: currentModelId)
      // Pick first image input name dynamically
      let md = model.modelDescription
      let inputName: String = {
        for (name, desc) in md.inputDescriptionsByName { if desc.type == .image { return name } }
        return "input_1"
      }()
      let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: facePB)])
      let out = try model.prediction(from: provider)

      // Build probability map from available outputs
      var map: [String: Double] = [:]
      // Prefer dictionary (class probabilities) if present
      for name in out.featureNames {
        if let fv = out.featureValue(for: name) {
          if fv.type == .dictionary {
            let dict = fv.dictionaryValue
            for (k, v) in dict { if let ks = k as? String { map[ks] = v.doubleValue } }
            if !map.isEmpty { break }
          }
        }
      }
      if map.isEmpty {
        // Try multi-array fallback (e.g., 'Identity')
        let maNames = ["Identity", "output", "probabilities"]
        var arr: [Float]? = nil
        for n in maNames {
          if let m = out.featureValue(for: n)?.multiArrayValue { arr = m.toFloatArray(); break }
        }
        if arr == nil {
          // pick first multiArray output if any
          for name in out.featureNames { if let m = out.featureValue(for: name)?.multiArrayValue { arr = m.toFloatArray(); break } }
        }
        if let scores = arr {
          let labels = ["Anger","Disgust","Fear","Happiness","Neutral","Sadness","Surprise"]
          for i in 0..<min(scores.count, labels.count) { map[labels[i]] = Double(scores[i]) }
        }
      }
      if !map.isEmpty { cameraEventSink?(map) }
    } catch {
      // Log errors for visibility in debug runs
      NSLog("EmotionDetectionPlugin capture error: \(error.localizedDescription)")
    }
  }

  // MARK: - Preview window helpers
  private func showPreviewWindow() {
    if captureSession == nil { configureAndStartSession() }
    guard let session = captureSession else { return }
    if previewWindow == nil {
      let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered,
                         defer: false)
      win.title = "Emotion Camera Preview"
      let contentView = NSView(frame: win.contentLayoutRect)
      contentView.wantsLayer = true
      win.contentView = contentView
      previewWindow = win
    }
    if previewLayer == nil {
      let layer = AVCaptureVideoPreviewLayer(session: session)
      layer.videoGravity = .resizeAspectFill
      layer.frame = previewWindow?.contentView?.bounds ?? .zero
      previewWindow?.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
      previewWindow?.contentView?.layer?.addSublayer(layer)
      previewLayer = layer
    } else {
      previewLayer?.session = session
    }
    previewWindow?.makeKeyAndOrderFront(nil)
    // Adjust layer on resize
    NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: previewWindow, queue: .main) { [weak self] _ in
      guard let self = self else { return }
      self.previewLayer?.frame = self.previewWindow?.contentView?.bounds ?? .zero
    }
  }

  private func hidePreviewWindow() {
    previewLayer?.removeFromSuperlayer()
    previewLayer = nil
    previewWindow?.orderOut(nil)
    previewWindow = nil
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
  // Try exact file name first (including extension if provided)
  if let url = bundle.url(forResource: name, withExtension: nil) { return try decodeManifest(at: url) }
  let ns = name as NSString
  let base = ns.deletingPathExtension
  let full = name
  // Build robust candidates for both exact and split extensions
  let candidates: [(String, String?)] = [
    (full, nil),                 // e.g., base.manifest.json
    (full, "json"),            // e.g., base.manifest.json (split ext)
    (base + ".manifest", "json"),
    (base, "manifest.json"),
    (base, "json"),
    (base, "manifest"),
    (base + "-shard", "manifest.json"),
    (base + "_shard", "manifest.json"),
  ]
  let bundles: [Bundle] = [bundle] + Bundle.allBundles + Bundle.allFrameworks
  for b in bundles {
    for (n, e) in candidates {
      if let u = (e == nil ? b.url(forResource: n, withExtension: nil) : b.url(forResource: n, withExtension: e)) {
        return try decodeManifest(at: u)
      }
    }
  }
  throw ManifestLoadError.notFound
}
private func decodeManifest(at url: URL) throws -> ModelManifest { do { let d = try Data(contentsOf: url); return try JSONDecoder().decode(ModelManifest.self, from: d) } catch let err as DecodingError { throw ManifestLoadError.decodeFailed(err) } catch { throw ManifestLoadError.readFailed } }

enum CryptoError: Error { case badCiphertext }
struct ModelCrypto { static func decrypt(combined: Data, key: SymmetricKey, aad: Data) throws -> Data { let box = try AES.GCM.SealedBox(combined: combined); return try AES.GCM.open(box, using: key, authenticating: aad) }; static func sha256Hex(_ data: Data) -> String { let dig = SHA256.hash(data: data); return dig.map { String(format: "%02x", $0) }.joined() } }

enum FileErr: Error { case missing, unzip, notFound, noMLPackage }
struct FileIO {
  static func bundleURL(name: String, ext: String, in bundle: Bundle) throws -> URL { guard let url = bundle.url(forResource: name, withExtension: ext) else { throw FileErr.missing }; return url }
  static func tempDir(_ name: String = UUID().uuidString) throws -> URL { let d = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
  static func anyBundleURL(name: String, ext: String, prefer bundle: Bundle? = nil) throws -> URL {
    if let b = bundle, let u = b.url(forResource: name, withExtension: ext) { return u }
    for b in [bundle].compactMap({ $0 }) + Bundle.allBundles + Bundle.allFrameworks {
      if let u = b.url(forResource: name, withExtension: ext) { return u }
    }
    // Also scan resource bundles inside main bundle's Resources
    if let resURL = Bundle.main.resourceURL {
      if let it = FileManager.default.enumerator(at: resURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
        for case let url as URL in it {
          if url.pathExtension == "bundle", let rb = Bundle(url: url), let u = rb.url(forResource: name, withExtension: ext) {
            return u
          }
        }
      }
    }
    // Finally, try Flutter assets packaged under App.framework/Resources/flutter_assets
    let frameworks = Bundle.allFrameworks
    for fw in frameworks {
      if fw.bundleURL.lastPathComponent == "App.framework" || fw.bundleURL.path.contains("/App.framework") {
        if let base = fw.resourceURL?.appendingPathComponent("flutter_assets", isDirectory: true) {
          let file = ext.isEmpty ? name : "\(name).\(ext)"
          let rel = "packages/emotion_detection/ios/Assets/\(file)"
          let url = base.appendingPathComponent(rel)
          if FileManager.default.fileExists(atPath: url.path) { return url }
        }
      }
    }
    throw FileErr.missing
  }
  static func unzip(_ zipURL: URL, to dest: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: dest, withIntermediateDirectories: true)
    guard let archive = Archive(url: zipURL, accessMode: .read) else { throw FileErr.unzip }
    for entry in archive {
      if entry.path.hasPrefix("__MACOSX/") || entry.path.hasPrefix("._") { continue }
      let outURL = dest.appendingPathComponent(entry.path)
      switch entry.type {
      case .directory:
        try fm.createDirectory(at: outURL, withIntermediateDirectories: true)
      case .file:
        try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: outURL.path) { try fm.removeItem(at: outURL) }
        fm.createFile(atPath: outURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outURL)
        defer { try? handle.close() }
        try archive.extract(entry, bufferSize: 32 * 1024, consumer: { data in
          if #available(macOS 10.15.4, *) {
            try handle.write(contentsOf: data)
          } else {
            handle.write(data)
          }
        })
      default:
        continue
      }
    }
  }
  static func findMLPackage(in dir: URL) throws -> URL { if let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) { for case let u as URL in e where u.pathExtension == "mlpackage" { return u } } ; throw FileErr.noMLPackage }
}
enum EncryptedLoadError: Error { case integrityFailed }
struct EncryptedModelLoader {
  static func loadFromBundle(baseName: String, configuration: MLModelConfiguration, framework: Bundle, obtainKey: () throws -> SymmetricKey) throws -> MLModel {
    let manifestURL = try FileIO.anyBundleURL(name: baseName, ext: "manifest.json", prefer: framework)
    let encURL = try FileIO.anyBundleURL(name: baseName, ext: "enc", prefer: framework)
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

// HKDF-SHA256 (RFC 5869) using CryptoKit HMAC; available on macOS 10.15+
private func hkdfSHA256(ikm: Data, salt: Data, info: Data, outputLength: Int) -> Data {
  let saltKey = SymmetricKey(data: salt.isEmpty ? Data(repeating: 0, count: 32) : salt)
  let prkMac = HMAC<SHA256>.authenticationCode(for: ikm, using: saltKey)
  let prk = SymmetricKey(data: Data(prkMac))
  var okm = Data()
  var previous = Data()
  var counter: UInt8 = 1
  while okm.count < outputLength {
    var ctx = Data()
    ctx.append(previous)
    ctx.append(info)
    ctx.append(counter)
    let blockMac = HMAC<SHA256>.authenticationCode(for: ctx, using: prk)
    let block = Data(blockMac)
    okm.append(block)
    previous = block
    counter &+= 1
  }
  return okm.prefix(outputLength)
}

private func deriveKEK(user32: Data, shard: Data?, aad: String, kdfInfo: String) -> SymmetricKey {
  // Packaging binds shard via AAD/salt, not in IKM.
  let ikm = user32
  let salt = Data(aad.utf8)
  let info = Data(kdfInfo.utf8)
  let keyData = hkdfSHA256(ikm: ikm, salt: salt, info: info, outputLength: 32)
  return SymmetricKey(data: keyData)
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
