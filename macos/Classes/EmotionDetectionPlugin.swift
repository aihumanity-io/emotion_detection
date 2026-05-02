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
  private var currentModelId: String = "aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx"

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
    case "setModelLicense":
      handleSetModelLicense(call: call, result: result)
    case "clearModelLicense":
      handleClearModelLicense(call: call, result: result)
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
      let runtimeModel = try ModelCache.shared.model(for: currentModelId)
      let map = try predictDistribution(runtimeModel: runtimeModel, crop: crop)
      if !map.isEmpty { cameraEventSink?(map) }
    } catch {
      // Keep full error for root-cause debugging (enum/error codes often hidden in localizedDescription).
      NSLog("EmotionDetectionPlugin capture error: \(String(describing: error))")
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
      let userCodePrefix = String(userCodeB64.prefix(8))
      NSLog("EmotionDetectionPlugin setUserCode account=\(acct) bytes=\(decoded.count) b64prefix=\(userCodePrefix) sha256=\(shortSHA256(decoded))")
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
      if let shardData = Data(base64Encoded: ShardCache.normalizeB64(keyShardB64)) {
        let shardPrefix = String(keyShardB64.prefix(8))
        NSLog("EmotionDetectionPlugin setKeyShard modelId=\(modelId) bytes=\(shardData.count) b64prefix=\(shardPrefix) sha256=\(shortSHA256(shardData)) exp=\(exp ?? -1)")
      } else {
        NSLog("EmotionDetectionPlugin setKeyShard modelId=\(modelId) invalidBase64")
      }
      if let userName = (args["userName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
         !userName.isEmpty {
        let acct = UserCodeUtils.sanitize(userName: userName)
        try? ShardCache.setShard(modelId: acct, base64: keyShardB64, expiresAtMs: exp)
      }
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

  private func handleSetModelLicense(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let modelId = args["modelId"] as? String else {
      return result(FlutterError(code: "invalid_args", message: "modelId required", details: nil))
    }

    do {
      if let licenseMap = args["license"] as? [String: Any] {
        try LicenseCache.setLicense(modelId: modelId, licenseMap: licenseMap)
      } else if let licenseJson = args["licenseJson"] as? String {
        guard let data = licenseJson.data(using: .utf8) else {
          return result(FlutterError(code: "license_error", message: "licenseJson is not valid UTF-8", details: nil))
        }
        try LicenseCache.setLicense(modelId: modelId, jsonData: data)
      } else {
        return result(FlutterError(code: "invalid_args", message: "license or licenseJson required", details: nil))
      }
      ModelCache.shared.unload(modelId: modelId)
      result(nil)
    } catch {
      result(FlutterError(code: "license_error", message: error.localizedDescription, details: nil))
    }
  }

  private func handleClearModelLicense(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let modelId = args["modelId"] as? String else {
      return result(FlutterError(code: "invalid_args", message: "modelId required", details: nil))
    }
    LicenseCache.clear(modelId: modelId)
    ModelCache.shared.unload(modelId: modelId)
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

      let runtimeModel = try ModelCache.shared.model(for: modelId)
      let map = try predictDistribution(runtimeModel: runtimeModel, crop: crop)
      result(map)
    } catch {
      result(FlutterError(code: "predict_error", message: error.localizedDescription, details: nil))
    }
  }

  private func predictDistribution(runtimeModel: RuntimeModel, crop: CGImage) throws -> [String: Double] {
    switch runtimeModel {
    case .onnx(let model):
      return try model.predict(faceImage: crop)
    case .coreML(let model):
      guard let pb = crop.pixelBuffer(width: 224, height: 224, orientation: .up) else {
        throw NSError(
          domain: "ModelLoad",
          code: -31,
          userInfo: [NSLocalizedDescriptionKey: "could not build pixel buffer"]
        )
      }

      let md = model.modelDescription
      let inputName: String = {
        for (name, desc) in md.inputDescriptionsByName {
          if desc.type == .image { return name }
        }
        return "input_1"
      }()
      let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: pb)])
      let out = try model.prediction(from: provider)

      var map: [String: Double] = [:]
      for name in out.featureNames {
        if let fv = out.featureValue(for: name), fv.type == .dictionary {
          let dict = fv.dictionaryValue
          for (k, v) in dict {
            if let ks = k as? String { map[ks] = v.doubleValue }
          }
          if !map.isEmpty { break }
        }
      }
      if !map.isEmpty { return map }

      let maNames = ["Identity", "output", "probabilities"]
      var arr: [Float]? = nil
      for n in maNames {
        if let m = out.featureValue(for: n)?.multiArrayValue {
          arr = m.toFloatArray()
          break
        }
      }
      if arr == nil {
        for n in out.featureNames {
          if let m = out.featureValue(for: n)?.multiArrayValue {
            arr = m.toFloatArray()
            break
          }
        }
      }
      guard let scores = arr else { return [:] }
      let labels = ["Anger", "Disgust", "Fear", "Happiness", "Neutral", "Sadness", "Surprise"]
      for i in 0..<min(scores.count, labels.count) { map[labels[i]] = Double(scores[i]) }
      return map
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

enum RuntimeModel {
  case coreML(MLModel)
  case onnx(OnnxEmotionModel)

  var isOnnx: Bool {
    if case .onnx = self { return true }
    return false
  }
}

final class ModelCache {
  static let shared = ModelCache()
  private var cache: [String: RuntimeModel] = [:]
  private let lock = NSLock()

  func model(for modelId: String) throws -> RuntimeModel {
    lock.lock(); defer { lock.unlock() }
    if let m = cache[modelId] { return m }
    let bundle = Bundle(for: EmotionDetectionPlugin.self)
    let baseName = resolveModelBaseName(for: modelId, in: bundle)

    // Load manifest and unwrap CEK using user32 (keychain) and optional shard
    let manifestURL = try FileIO.anyBundleURL(name: baseName, ext: "manifest.json", prefer: bundle)
    NSLog("EmotionDetectionPlugin loading modelId=\(modelId), baseName=\(baseName), manifest=\(manifestURL.path)")
    let manifest = try decodeManifest(at: manifestURL)
    let manifestModelId = manifest.resolvedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    let lookupModelId = manifestModelId.isEmpty ? modelId : manifestModelId
    let modelIdentifierCandidates = [
      lookupModelId,
      manifest.modelId,
      manifest.model_id,
      manifest.model_name,
      modelId
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let userName = UserCodeUtils.sanitize(userName: EmotionDetectionPluginState.currentUserName)
    let cek = try obtainCEK_UserCodeGateSync(
      manifest: manifest,
      userName: userName,
      modelId: lookupModelId,
      user32Provider: { try UserCodeUtils.loadUser32(userName: userName, modelIds: modelIdentifierCandidates) }
    )
    NSLog("EmotionDetectionPlugin CEK ready for modelId=\(modelId) bytes=\(cek.count)")
    let runtimeModel = try EncryptedModelLoader.loadFromBundle(
      baseName: baseName,
      configuration: MLModelConfiguration(),
      framework: bundle,
      obtainKey: { SymmetricKey(data: cek) }
    )
    let backendName = (runtimeModel.isOnnx ? "onnx" : "coreml")
    NSLog("EmotionDetectionPlugin model ready modelId=\(modelId) baseName=\(baseName) backend=\(backendName)")
    cache[modelId] = runtimeModel
    return runtimeModel
  }

  private func resolveModelBaseName(for modelId: String, in bundle: Bundle) -> String {
    let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidates = [String]()
    func addCandidate(_ value: String?) {
      guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
      if !candidates.contains(raw) { candidates.append(raw) }
    }

    addCandidate(normalizedModelId)

    // Legacy shard alias -> base id (e.g. foo_v2024-...-shard -> foo2024-...)
    if normalizedModelId.hasSuffix("-shard"),
       let vRange = normalizedModelId.range(of: "_v") {
      let prefix = String(normalizedModelId[..<vRange.lowerBound])
      let tsEnd = normalizedModelId.index(normalizedModelId.endIndex, offsetBy: -"-shard".count)
      if tsEnd > vRange.upperBound {
        let timestamp = String(normalizedModelId[vRange.upperBound..<tsEnd])
        let parts = timestamp.split(separator: "-")
        if parts.count == 6 {
          addCandidate("\(prefix)\(timestamp)")
        }
      }
    }

    addCandidate("aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx")

    for candidate in candidates {
      let hasManifest = (try? FileIO.anyBundleURL(name: candidate, ext: "manifest.json", prefer: bundle)) != nil
      let hasEncryptedModel = (try? FileIO.anyBundleURL(name: candidate, ext: "enc", prefer: bundle)) != nil
      if hasManifest && hasEncryptedModel { return candidate }
    }

    NSLog("EmotionDetectionPlugin model assets missing for modelId=\(modelId), candidates=\(candidates)")
    return candidates[0]
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
  static func accountCandidates(userName: String, modelIds: [String]) -> [String] {
    var accountsToTry = [String]()
    for modelId in modelIds {
      let acct = account(userName: userName, modelId: modelId)
      if accountsToTry.contains(acct) { continue }
      accountsToTry.append(acct)
    }
    let legacy = account(userName: userName, modelId: nil)
    if !accountsToTry.contains(legacy) { accountsToTry.append(legacy) }
    return accountsToTry
  }
  static func loadUser32(userName: String, modelIds: [String]) throws -> Data {
    let accountsToTry = accountCandidates(userName: userName, modelIds: modelIds)
    for acct in accountsToTry {
      if let cached = try? User32Store.load(account: acct) {
        NSLog("EmotionDetectionPlugin user32 keychain hit account=\(acct) bytes=\(cached.count)")
        return cached
      }
    }
    if let sideLoaded = try? User32SideLoad.loadUser32Data(bundle: Bundle.main), sideLoaded.count == 32 {
      NSLog("EmotionDetectionPlugin user32 sideload hit bytes=\(sideLoaded.count)")
      return sideLoaded
    }
    if let sideLoaded = try? User32SideLoad.loadUser32Data(bundle: Bundle(for: EmotionDetectionPlugin.self)), sideLoaded.count == 32 {
      NSLog("EmotionDetectionPlugin user32 sideload hit(plugin bundle) bytes=\(sideLoaded.count)")
      return sideLoaded
    }
    throw NSError(domain: "User32", code: -1, userInfo: [
      NSLocalizedDescriptionKey: "User32 not found for accounts: \(accountsToTry.joined(separator: ", "))"
    ])
  }
}

enum User32SideLoadError: Error { case notFound, badFormat(String) }

struct User32SideLoad {
  static func sideLoadedURL(
    fileNames: [String] = ["user32.b64", "user_code.b64", "user32.bin", "user_code.bin", "user32.txt", "user_code.txt"],
    bundle: Bundle = .main
  ) throws -> URL {
    let fm = FileManager.default
    if let path = ProcessInfo.processInfo.environment["EMO_USER32_PATH"], !path.isEmpty {
      let u = URL(fileURLWithPath: path)
      if fm.fileExists(atPath: u.path) { return u }
    }
    if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
      for name in fileNames {
        let u = docs.appendingPathComponent(name, isDirectory: false)
        if fm.fileExists(atPath: u.path) { return u }
      }
    }
    if let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      for name in fileNames {
        let u = appSup.appendingPathComponent(name, isDirectory: false)
        if fm.fileExists(atPath: u.path) { return u }
      }
    }
    for name in fileNames {
      if let u = bundle.url(forResource: name, withExtension: nil) { return u }
      let ns = name as NSString
      let base = ns.deletingPathExtension
      let ext = ns.pathExtension.isEmpty ? "b64" : ns.pathExtension
      if let u = bundle.url(forResource: base, withExtension: ext) { return u }
    }
    throw User32SideLoadError.notFound
  }

  static func loadUser32Data(
    fileNames: [String] = ["user32.b64", "user_code.b64", "user32.bin", "user_code.bin", "user32.txt", "user_code.txt"],
    bundle: Bundle = .main
  ) throws -> Data {
    let url = try sideLoadedURL(fileNames: fileNames, bundle: bundle)
    let raw = try Data(contentsOf: url)
    if let s = String(data: raw, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
       let b64 = Data(base64Encoded: s),
       b64.count == 32 {
      return b64
    }
    if raw.count == 32 { return raw }
    if let s = String(data: raw, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
       let hex = Data(hexString: s),
       hex.count == 32 {
      return hex
    }
    throw User32SideLoadError.badFormat("Expected base64(32B), raw 32B, or 64-hex")
  }
}

private extension Data {
  init?(hexString: String) {
    let s = hexString.lowercased()
      .replacingOccurrences(of: "0x", with: "")
      .replacingOccurrences(of: " ", with: "")
    guard s.count % 2 == 0 else { return nil }
    var out = Data(capacity: s.count / 2)
    var idx = s.startIndex
    while idx < s.endIndex {
      let next = s.index(idx, offsetBy: 2)
      let byteStr = s[idx..<next]
      guard let b = UInt8(byteStr, radix: 16) else { return nil }
      out.append(b)
      idx = next
    }
    self = out
  }
}

enum User32StoreErr: Error { case badStatus(OSStatus) }
enum User32Store {
  static let service = "com.creataai.emotionsdk.user32"
  private static let volatileLock = NSLock()
  private static var volatileUser32: [String: Data] = [:]

  private static func setVolatile(_ data: Data, account: String) {
    volatileLock.lock(); defer { volatileLock.unlock() }
    volatileUser32[account] = data
  }

  private static func getVolatile(account: String) -> Data? {
    volatileLock.lock(); defer { volatileLock.unlock() }
    return volatileUser32[account]
  }

  private static func clearVolatile(account: String) {
    volatileLock.lock(); defer { volatileLock.unlock() }
    volatileUser32.removeValue(forKey: account)
  }

  static func delete(account: String, clearVolatileCache: Bool = true) throws {
    if clearVolatileCache { clearVolatile(account: account) }
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
    ]
    q.removeValue(forKey: kSecUseAuthenticationUI as String)
    let st = SecItemDelete(q as CFDictionary)
    guard st == errSecSuccess || st == errSecItemNotFound else {
      throw User32StoreErr.badStatus(st)
    }
  }
  static func save(_ data: Data, account: String, requireBiometrics: Bool) throws {
    try delete(account: account, clearVolatileCache: false)
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
    let st = SecItemAdd(q as CFDictionary, nil)
    guard st == errSecSuccess else { throw User32StoreErr.badStatus(st) }
    setVolatile(data, account: account)
  }
  static func load(account: String) throws -> Data {
    if let volatile = getVolatile(account: account) {
      NSLog("EmotionDetectionPlugin user32 load source=volatile account=\(account) bytes=\(volatile.count)")
      return volatile
    }
    var q: [String:Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let st = SecItemCopyMatching(q as CFDictionary, &item)
    if st == errSecSuccess, let d = item as? Data {
      NSLog("EmotionDetectionPlugin user32 load source=keychain account=\(account) bytes=\(d.count)")
      return d
    }
    throw NSError(domain: NSOSStatusErrorDomain, code: Int(st))
  }

  static func loadNoUI(account: String) throws -> Data {
    return try load(account: account)
  }

  static func volatileCandidates(forUserName userName: String) -> [(String, Data)] {
    let prefix = UserCodeUtils.sanitize(userName: userName) + "|"
    let exact = UserCodeUtils.sanitize(userName: userName)
    volatileLock.lock(); defer { volatileLock.unlock() }
    return volatileUser32.compactMap { (acct, data) in
      if acct.hasPrefix(prefix) || acct == exact { return (acct, data) }
      return nil
    }
  }

  static func keychainCandidates(forUserName userName: String) -> [(String, Data)] {
    let prefix = UserCodeUtils.sanitize(userName: userName) + "|"
    let exact = UserCodeUtils.sanitize(userName: userName)
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnAttributes as String: true,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll
    ]
    var out: CFTypeRef?
    let st = SecItemCopyMatching(q as CFDictionary, &out)
    guard st == errSecSuccess else { return [] }
    guard let items = out as? [[String: Any]] else { return [] }

    var result: [(String, Data)] = []
    for item in items {
      guard let account = item[kSecAttrAccount as String] as? String else { continue }
      guard account == exact || account.hasPrefix(prefix) else { continue }
      guard let data = item[kSecValueData as String] as? Data, data.count == 32 else { continue }
      result.append((account, data))
    }
    return result
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
  static func activeShards(for identifiers: [String], now: Date = Date()) -> [(String, CekShardLease)] {
    lock.lock(); defer { lock.unlock() }
    var out: [(String, CekShardLease)] = []
    var seen = Set<String>()
    for id in identifiers {
      let key = id.trimmingCharacters(in: .whitespacesAndNewlines)
      if key.isEmpty || seen.contains(key) { continue }
      seen.insert(key)
      guard let lease = shards[key] else { continue }
      if lease.isExpired(now: now) {
        shards.removeValue(forKey: key)
        continue
      }
      out.append((key, lease))
    }
    return out
  }
  static func allActiveShards(now: Date = Date()) -> [(String, CekShardLease)] {
    lock.lock(); defer { lock.unlock() }
    var out: [(String, CekShardLease)] = []
    for (key, lease) in shards {
      if lease.isExpired(now: now) {
        shards.removeValue(forKey: key)
        continue
      }
      out.append((key, lease))
    }
    return out
  }
  static func normalizeB64(_ value: String) -> String { var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); let missing = (4 - s.count % 4) % 4; if missing > 0 { s = s.padding(toLength: s.count + missing, withPad: "=", startingAt: 0) }; return s }
}

enum DistributionMode {
  case unified
  case perDeveloper
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

enum LicenseCache {
  private static var docs: [String: LicenseDoc] = [:]
  private static let lock = NSLock()

  static func setLicense(modelId rawModelId: String, license: LicenseDoc) {
    let modelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !modelId.isEmpty else { return }
    lock.lock(); defer { lock.unlock() }
    docs[modelId] = license
    docs[license.modelId] = license
    NSLog("EmotionDetectionPlugin license set id=\(modelId) modelId=\(license.modelId)")
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
    if let doc = docs[modelId] { docs.removeValue(forKey: doc.modelId) }
    docs.removeValue(forKey: modelId)
  }

  static func firstMatch(candidates: [String]) -> LicenseDoc? {
    lock.lock(); defer { lock.unlock() }
    for candidate in candidates {
      let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
      if key.isEmpty { continue }
      if let doc = docs[key] { return doc }
    }
    return nil
  }
}

// MARK: - Minimal encryption + manifest loaders

struct ModelManifest: Decodable {
  struct ManifestWrap: Decodable {
    let type: String?
    let salt: String?
    let iv: String?
    let rsaScheme: String?
    let rsaKeyId: String?
    let shardRequired: Bool?
  }

  // Legacy fields
  let model_name: String
  let model_id: String?
  let version: String?
  let zip_sha256: String
  let enc_sha256: String
  let aad: String
  let algorithm: String?
  let combined_format: String?
  let nonce_len: Int?
  let tag_len: Int?
  let created_at: String?
  let wrapped_cek_b64: String
  let kdf_info: String
  let shard_required: Bool?
  let expiry_epoch_ms: Int?

  // Newer fields (kept for compatibility with iOS logic).
  let distributionMode: String?
  let sourceKind: String?
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
    let v = model_name.trimmingCharacters(in: .whitespacesAndNewlines)
    return v
  }

  var shardRequiredPolicy: Bool {
    return shard_required ?? wrap?.shardRequired ?? false
  }

  private enum CodingKeys: String, CodingKey {
    case model_name
    case model_id
    case version
    case zip_sha256
    case enc_sha256
    case aad
    case algorithm
    case combined_format
    case nonce_len
    case tag_len
    case created_at
    case wrapped_cek_b64
    case kdf_info
    case shard_required
    case shardRequired
    case expiry_epoch_ms

    case distributionMode
    case sourceKind
    case modelId
    case algo
    case ciphertextLen
    case gcmIv
    case plainSha256
    case wrappedCek
    case wrap
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)

    model_name = try c.decodeIfPresent(String.self, forKey: .model_name) ?? ""
    model_id = try c.decodeIfPresent(String.self, forKey: .model_id)
    if let stringVersion = (try? c.decodeIfPresent(String.self, forKey: .version)) ?? nil {
      version = stringVersion
    } else if let intVersion = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? nil {
      version = String(intVersion)
    } else {
      version = nil
    }
    zip_sha256 = try c.decodeIfPresent(String.self, forKey: .zip_sha256) ?? ""
    enc_sha256 = try c.decodeIfPresent(String.self, forKey: .enc_sha256) ?? ""
    aad = try c.decodeIfPresent(String.self, forKey: .aad) ?? ""
    algorithm = try c.decodeIfPresent(String.self, forKey: .algorithm)
    combined_format = try c.decodeIfPresent(String.self, forKey: .combined_format)
    nonce_len = try c.decodeIfPresent(Int.self, forKey: .nonce_len)
    tag_len = try c.decodeIfPresent(Int.self, forKey: .tag_len)
    created_at = try c.decodeIfPresent(String.self, forKey: .created_at)
    wrapped_cek_b64 = try c.decodeIfPresent(String.self, forKey: .wrapped_cek_b64) ?? ""
    kdf_info = try c.decodeIfPresent(String.self, forKey: .kdf_info) ?? ""
    let shardSnake = try c.decodeIfPresent(Bool.self, forKey: .shard_required)
    let shardCamel = try c.decodeIfPresent(Bool.self, forKey: .shardRequired)
    shard_required = shardSnake ?? shardCamel
    expiry_epoch_ms = try c.decodeIfPresent(Int.self, forKey: .expiry_epoch_ms)

    distributionMode = try c.decodeIfPresent(String.self, forKey: .distributionMode)
    sourceKind = try c.decodeIfPresent(String.self, forKey: .sourceKind)
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
struct ModelCrypto {
  static func decrypt(combined: Data, key: SymmetricKey, aad: Data) throws -> Data {
    let box = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(box, using: key, authenticating: aad)
  }

  static func decrypt(iv: Data, combinedCtTag: Data, key: SymmetricKey, aad: Data) throws -> Data {
    guard combinedCtTag.count > 16 else { throw CryptoError.badCiphertext }
    let ct = combinedCtTag.prefix(combinedCtTag.count - 16)
    let tag = combinedCtTag.suffix(16)
    let box = try AES.GCM.SealedBox(
      nonce: AES.GCM.Nonce(data: iv),
      ciphertext: ct,
      tag: tag
    )
    return try AES.GCM.open(box, using: key, authenticating: aad)
  }

  static func sha256Hex(_ data: Data) -> String {
    let dig = SHA256.hash(data: data)
    return dig.map { String(format: "%02x", $0) }.joined()
  }

  static func sha256Base64URL(_ data: Data) -> String {
    let digest = Data(SHA256.hash(data: data))
    return digest
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

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
  private static func resolvedSourceKind(_ manifest: ModelManifest) -> String {
    let raw = manifest.sourceKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let raw, !raw.isEmpty { return raw }
    return "directory"
  }

  private static func inferredFileExtension(baseName: String, manifest: ModelManifest) -> String {
    let ids = [
      baseName,
      manifest.modelId,
      manifest.model_id,
      manifest.model_name
    ].compactMap { $0?.lowercased() }

    for id in ids {
      if id.hasSuffix(".onnx") || id.hasSuffix("_onnx") { return "onnx" }
      if id.hasSuffix(".mlmodel") || id.hasSuffix("_mlmodel") { return "mlmodel" }
    }
    return "bin"
  }

  static func loadFromBundle(baseName: String, configuration: MLModelConfiguration, framework: Bundle, obtainKey: () throws -> SymmetricKey) throws -> RuntimeModel {
    let manifestURL = try FileIO.anyBundleURL(name: baseName, ext: "manifest.json", prefer: framework)
    let encURL = try FileIO.anyBundleURL(name: baseName, ext: "enc", prefer: framework)
    NSLog("EmotionDetectionPlugin decrypt start base=\(baseName) manifest=\(manifestURL.lastPathComponent) enc=\(encURL.lastPathComponent)")
    let manifest = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: manifestURL))
    let encData = try Data(contentsOf: encURL)
    let encHash = ModelCrypto.sha256Hex(encData)
    if !manifest.enc_sha256.isEmpty {
      guard encHash == manifest.enc_sha256 else { throw EncryptedLoadError.integrityFailed }
    }
    let key = try obtainKey()
    let aad = Data(manifest.aad.utf8)
    let zipData: Data
    if let ivRaw = manifest.gcmIv, !ivRaw.isEmpty {
      guard let iv = Data(base64Encoded: ShardCache.normalizeB64(ivRaw)) else {
        throw EncryptedLoadError.integrityFailed
      }
      zipData = try ModelCrypto.decrypt(iv: iv, combinedCtTag: encData, key: key, aad: aad)
    } else {
      zipData = try ModelCrypto.decrypt(combined: encData, key: key, aad: aad)
    }
    if !manifest.zip_sha256.isEmpty {
      let zipHash = ModelCrypto.sha256Hex(zipData)
      guard zipHash == manifest.zip_sha256 else { throw EncryptedLoadError.integrityFailed }
    } else if let plainSha = manifest.plainSha256, !plainSha.isEmpty {
      let calc = ModelCrypto.sha256Base64URL(zipData)
      guard calc == plainSha else { throw EncryptedLoadError.integrityFailed }
    }
    let sourceKind = resolvedSourceKind(manifest)
    if sourceKind == "file" {
      NSLog("EmotionDetectionPlugin decrypt ok base=\(baseName) fileBytes=\(zipData.count)")
      let ext = inferredFileExtension(baseName: baseName, manifest: manifest)
      let work = try FileIO.tempDir("model_dec_file_\(baseName)")
      let modelURL = work.appendingPathComponent("model_\(baseName).\(ext)")
      try zipData.write(to: modelURL, options: .atomic)
      if ext == "onnx" {
        NSLog("EmotionDetectionPlugin initializing onnx runtime base=\(baseName) modelId=\(manifest.resolvedModelId)")
        return .onnx(try OnnxEmotionModel(modelURL: modelURL))
      }
      let compiled = try MLModel.compileModel(at: modelURL)
      NSLog("EmotionDetectionPlugin compile ok base=\(baseName) file=\(modelURL.lastPathComponent) compiled=\(compiled.lastPathComponent)")
      return .coreML(try MLModel(contentsOf: compiled, configuration: configuration))
    }
    if sourceKind != "directory" {
      throw NSError(
        domain: "ModelLoad",
        code: -21,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported sourceKind '\(sourceKind)' for modelId=\(manifest.resolvedModelId)"]
      )
    }
    NSLog("EmotionDetectionPlugin decrypt ok base=\(baseName) zipBytes=\(zipData.count)")
    let work = try FileIO.tempDir("model_dec_\(baseName)"); let zipOut = work.appendingPathComponent("model_\(baseName).zip"); try zipData.write(to: zipOut, options: .atomic); try FileIO.unzip(zipOut, to: work)
    NSLog("EmotionDetectionPlugin unzip ok base=\(baseName) dir=\(work.path)")
    let pkg = try FileIO.findMLPackage(in: work); let compiled = try MLModel.compileModel(at: pkg)
    NSLog("EmotionDetectionPlugin compile ok base=\(baseName) compiled=\(compiled.lastPathComponent)")
    return .coreML(try MLModel(contentsOf: compiled, configuration: configuration))
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

private func shortSHA256(_ data: Data) -> String {
  return String(ModelCrypto.sha256Hex(data).prefix(12))
}

// HKDF-SHA256 (RFC 5869) fallback for macOS < 11.
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
  var ikm = Data(user32)
  if let shard, !shard.isEmpty { ikm.append(shard) }
  let salt = Data(aad.utf8)
  let info = Data(kdfInfo.utf8)
  if #available(macOS 11.0, *) {
    // Keep HKDF behavior aligned with iOS: IKM = user32 || shard?
    return HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: ikm),
      salt: salt,
      info: info,
      outputByteCount: 32
    )
  }
  let keyData = hkdfSHA256(ikm: ikm, salt: salt, info: info, outputLength: 32)
  return SymmetricKey(data: keyData)
}

private func deriveHKDFKey(ikm: Data, salt: Data, info: Data) -> SymmetricKey {
  if #available(macOS 11.0, *) {
    return HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: ikm),
      salt: salt,
      info: info,
      outputByteCount: 32
    )
  }
  let keyData = hkdfSHA256(ikm: ikm, salt: salt, info: info, outputLength: 32)
  return SymmetricKey(data: keyData)
}

private func unwrapCEK_fromManifest(wrappedCEK_B64: String, kek: SymmetricKey, aad: String) throws -> Data {
  guard let env = Data(base64Encoded: wrappedCEK_B64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    throw NSError(
      domain: "CEKAuth",
      code: -9,
      userInfo: [NSLocalizedDescriptionKey: "Invalid wrapped_cek_b64 encoding"]
    )
  }
  let box = try AES.GCM.SealedBox(combined: env)
  return try AES.GCM.open(box, using: kek, authenticating: Data(aad.utf8))
}

private func decodeB64Any(_ value: String) -> Data? {
  if let direct = Data(base64Encoded: value) { return direct }
  return Data(base64Encoded: ShardCache.normalizeB64(value))
}

private func parseISO8601(_ value: String) -> Date? {
  let formatter = ISO8601DateFormatter()
  if let d = formatter.date(from: value) { return d }
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.date(from: value)
}

private func detectDistributionMode(_ manifest: ModelManifest) -> DistributionMode {
  if let raw = manifest.distributionMode?.lowercased() {
    if raw == "unified" { return .unified }
    if raw == "per-developer" { return .perDeveloper }
  }
  if let wrapType = manifest.wrap?.type {
    if wrapType == "RSA-OAEP-256" || wrapType == "external" { return .unified }
    if wrapType.hasPrefix("HKDF-SHA256+code") { return .perDeveloper }
  }
  if !manifest.wrapped_cek_b64.isEmpty {
    return .perDeveloper
  }
  return .unified
}

private func licenseCandidates(manifest: ModelManifest, effectiveModelId: String, userName: String) -> [String] {
  var out: [String] = []
  let sanitizedUser = UserCodeUtils.sanitize(userName: userName)
  for value in [effectiveModelId, manifest.modelId, manifest.model_id, manifest.model_name, sanitizedUser] {
    guard let s = value?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { continue }
    if !out.contains(s) { out.append(s) }
  }
  return out
}

private func loadLicenseIfPresent(
  manifest: ModelManifest,
  effectiveModelId: String,
  userName: String,
  in bundle: Bundle = .main
) -> LicenseDoc? {
  let candidates = licenseCandidates(manifest: manifest, effectiveModelId: effectiveModelId, userName: userName)
  if let cached = LicenseCache.firstMatch(candidates: candidates) { return cached }
  for candidate in candidates {
    let names = ["\(candidate).macos.license", "\(candidate).ios.license", "\(candidate).license", candidate]
    for name in names {
      guard let url = bundle.url(forResource: name, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let license = try? JSONDecoder().decode(LicenseDoc.self, from: data) else { continue }
      LicenseCache.setLicense(modelId: candidate, license: license)
      return license
    }
  }
  return nil
}

private func resolveShardLease(
  manifest: ModelManifest,
  effectiveModelId: String,
  userName: String
) throws -> CekShardLease? {
  if let manifestExpiry = manifest.expiry_epoch_ms {
    let expiryDate = Date(timeIntervalSince1970: TimeInterval(manifestExpiry) / 1000.0)
    if Date() >= expiryDate {
      throw NSError(
        domain: "CEKAuth",
        code: -6,
        userInfo: [NSLocalizedDescriptionKey: "Shard expired by manifest expiry for \(effectiveModelId)"]
      )
    }
  }

  let candidates = [
    effectiveModelId,
    manifest.modelId,
    manifest.model_id,
    manifest.model_name,
    UserCodeUtils.sanitize(userName: userName)
  ]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }

  let lease = ShardCache.activeShard(for: candidates)
  if manifest.shardRequiredPolicy && lease == nil {
    throw NSError(
      domain: "CEKAuth",
      code: -3,
      userInfo: [NSLocalizedDescriptionKey: "Shard required but missing for model candidates: \(candidates.joined(separator: ", "))"]
    )
  }
  if let lease, lease.isExpired() {
    throw NSError(
      domain: "CEKAuth",
      code: -6,
      userInfo: [NSLocalizedDescriptionKey: "Shard expired for model \(effectiveModelId)"]
    )
  }
  return lease
}

private func unwrapCEKFromLicense(user32: Data, shard: Data?, license: LicenseDoc) throws -> Data {
  if license.wrap.shardUsed && shard == nil {
    throw NSError(domain: "CEKAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "License requires shard"])
  }

  let ikm: Data = {
    if let shard {
      var out = Data(user32)
      out.append(shard)
      return out
    }
    return Data(user32)
  }()

  guard let salt = decodeB64Any(license.wrap.salt),
        let iv = decodeB64Any(license.wrap.wrapIv),
        let combined = decodeB64Any(license.wrappedCek),
        combined.count > 16 else {
    throw NSError(domain: "CEKAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "Invalid license wrap fields"])
  }

  let info = Data("model:\(license.modelId)".utf8)
  let kek = deriveHKDFKey(ikm: ikm, salt: salt, info: info)
  let ct = combined.prefix(combined.count - 16)
  let tag = combined.suffix(16)
  let aad = Data((license.wrap.aad ?? "").utf8)
  let box = try AES.GCM.SealedBox(
    nonce: AES.GCM.Nonce(data: iv),
    ciphertext: ct,
    tag: tag
  )
  let cek = try AES.GCM.open(box, using: kek, authenticating: aad)
  guard cek.count == 32 else {
    throw NSError(domain: "CEKAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "Invalid CEK length from license"])
  }
  return cek
}

private func unwrapV2ManifestCEK(user32: Data, shard: Data?, manifest: ModelManifest, effectiveModelId: String) throws -> Data {
  guard let wrap = manifest.wrap,
        let wrapType = wrap.type,
        wrapType.hasPrefix("HKDF-SHA256+code"),
        let wrapIvRaw = wrap.iv,
        let wrapSaltRaw = wrap.salt,
        let wrappedRaw = manifest.wrappedCek,
        !manifest.aad.isEmpty else {
    throw NSError(domain: "CEKAuth", code: -10, userInfo: [NSLocalizedDescriptionKey: "Manifest missing v2 wrap fields"])
  }

  let typeRequiresShard = wrapType.contains("+shard+")
  let shardRequired = manifest.shardRequiredPolicy || typeRequiresShard
  if shardRequired && shard == nil {
    throw NSError(domain: "CEKAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "Manifest v2 wrap requires shard"])
  }

  let ikm: Data = {
    if shardRequired, let shard {
      var out = Data(user32)
      out.append(shard)
      return out
    }
    return Data(user32)
  }()

  guard let wrapIv = decodeB64Any(wrapIvRaw),
        let wrapSalt = decodeB64Any(wrapSaltRaw),
        let ctTag = decodeB64Any(wrappedRaw),
        ctTag.count > 16 else {
    throw NSError(domain: "CEKAuth", code: -10, userInfo: [NSLocalizedDescriptionKey: "Manifest v2 wrap decode failed"])
  }

  let info = Data("model:\(effectiveModelId)".utf8)
  let kek = deriveHKDFKey(ikm: ikm, salt: wrapSalt, info: info)
  let ct = ctTag.prefix(ctTag.count - 16)
  let tag = ctTag.suffix(16)
  let box = try AES.GCM.SealedBox(
    nonce: AES.GCM.Nonce(data: wrapIv),
    ciphertext: ct,
    tag: tag
  )
  let cek = try AES.GCM.open(box, using: kek, authenticating: Data(manifest.aad.utf8))
  guard cek.count == 32 else {
    throw NSError(domain: "CEKAuth", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid CEK length from manifest v2 wrap"])
  }
  return cek
}

private func resolveCEKForUser32(
  manifest: ModelManifest,
  effectiveModelId: String,
  userName: String,
  user32: Data
) throws -> Data {
  guard user32.count == 32 else {
    throw NSError(domain: "User32", code: -2, userInfo: [NSLocalizedDescriptionKey: "user32 must be 32 bytes"])
  }

  let lease = try resolveShardLease(manifest: manifest, effectiveModelId: effectiveModelId, userName: userName)
  let shardForLegacy = manifest.shardRequiredPolicy ? lease?.shard : nil

  switch detectDistributionMode(manifest) {
  case .unified:
    guard let license = loadLicenseIfPresent(
      manifest: manifest,
      effectiveModelId: effectiveModelId,
      userName: userName,
      in: Bundle(for: EmotionDetectionPlugin.self)
    ) else {
      throw NSError(domain: "CEKAuth", code: -7, userInfo: [NSLocalizedDescriptionKey: "License required for unified distribution mode"])
    }

    let expectedIds = Set([
      effectiveModelId,
      manifest.modelId,
      manifest.model_id,
      manifest.model_name
    ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    if !expectedIds.isEmpty && !expectedIds.contains(license.modelId) {
      throw NSError(domain: "CEKAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "License modelId mismatch"])
    }
    if let expectedHash = manifest.plainSha256, !expectedHash.isEmpty, license.plainSha256 != expectedHash {
      throw NSError(domain: "CEKAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "License plainSha256 mismatch"])
    }
    if let algo = manifest.algo, !algo.isEmpty, license.algo != algo {
      throw NSError(domain: "CEKAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "License algo mismatch"])
    }
    if let expRaw = license.expiresAt, !expRaw.isEmpty {
      guard let exp = parseISO8601(expRaw), exp > Date() else {
        throw NSError(domain: "CEKAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "License expired"])
      }
    }

    if license.wrap.shardUsed && lease == nil {
      throw NSError(domain: "CEKAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "License wrap requires shard"])
    }
    let shardData = license.wrap.shardUsed ? lease?.shard : nil
    return try unwrapCEKFromLicense(user32: user32, shard: shardData, license: license)

  case .perDeveloper:
    // Prefer license if provided, then fall back to legacy manifest wrapped CEK.
    if let license = loadLicenseIfPresent(
      manifest: manifest,
      effectiveModelId: effectiveModelId,
      userName: userName,
      in: Bundle(for: EmotionDetectionPlugin.self)
    ) {
      do {
        let expectedIds = Set([
          effectiveModelId,
          manifest.modelId,
          manifest.model_id,
          manifest.model_name
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        if !expectedIds.isEmpty && !expectedIds.contains(license.modelId) {
          throw NSError(domain: "CEKAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "License modelId mismatch"])
        }
        if let expectedHash = manifest.plainSha256, !expectedHash.isEmpty, license.plainSha256 != expectedHash {
          throw NSError(domain: "CEKAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "License plainSha256 mismatch"])
        }
        if let algo = manifest.algo, !algo.isEmpty, license.algo != algo {
          throw NSError(domain: "CEKAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "License algo mismatch"])
        }
        if let expRaw = license.expiresAt, !expRaw.isEmpty {
          guard let exp = parseISO8601(expRaw), exp > Date() else {
            throw NSError(domain: "CEKAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "License expired"])
          }
        }
        let shardData = license.wrap.shardUsed ? lease?.shard : nil
        let cek = try unwrapCEKFromLicense(user32: user32, shard: shardData, license: license)
        NSLog("EmotionDetectionPlugin CEK license unwrap ok model=\(effectiveModelId) licenseModel=\(license.modelId) shardUsed=\(license.wrap.shardUsed)")
        return cek
      } catch {
        NSLog("EmotionDetectionPlugin CEK license unwrap failed model=\(effectiveModelId); fallback to legacy: \(error)")
      }
    }

    if !manifest.wrapped_cek_b64.isEmpty, !manifest.kdf_info.isEmpty, !manifest.aad.isEmpty {
      let shardB64 = lease?.shardB64 ?? lease?.shard.base64EncodedString()
      let aadAuth = manifest.shardRequiredPolicy ? "\(manifest.aad)|shard:\(shardB64 ?? "")" : manifest.aad
      do {
        let kek = deriveKEK(user32: user32, shard: nil, aad: aadAuth, kdfInfo: manifest.kdf_info)
        return try unwrapCEK_fromManifest(wrappedCEK_B64: manifest.wrapped_cek_b64, kek: kek, aad: aadAuth)
      } catch {
        if let shard = shardForLegacy {
          let fallback = deriveKEK(user32: user32, shard: shard, aad: aadAuth, kdfInfo: manifest.kdf_info)
          return try unwrapCEK_fromManifest(wrappedCEK_B64: manifest.wrapped_cek_b64, kek: fallback, aad: aadAuth)
        }
        throw error
      }
    }

    return try unwrapV2ManifestCEK(
      user32: user32,
      shard: shardForLegacy,
      manifest: manifest,
      effectiveModelId: effectiveModelId
    )
  }
}

private func obtainCEK_UserCodeGateSync(
  manifest: ModelManifest,
  userName: String,
  modelId: String?,
  user32Provider: () throws -> Data
) throws -> Data {
  // iOS parity: prefer requested model id, then manifest model id.
  let effectiveModelId = [modelId, manifest.resolvedModelId]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .first(where: { !$0.isEmpty }) ?? ""
  let modelCandidates = [
    effectiveModelId,
    manifest.modelId,
    manifest.model_id,
    manifest.model_name
  ]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  let accountsToTry = UserCodeUtils.accountCandidates(userName: userName, modelIds: modelCandidates)
  let accountHint = accountsToTry.first ?? UserCodeUtils.account(
    userName: userName,
    modelId: effectiveModelId.isEmpty ? nil : effectiveModelId
  )

  var user32Candidates: [(account: String, data: Data)] = []
  for acct in accountsToTry {
    guard !user32Candidates.contains(where: { $0.account == acct }) else { continue }
    if let cached = try? User32Store.load(account: acct), cached.count == 32 {
      user32Candidates.append((account: acct, data: cached))
    }
  }
  for candidate in User32Store.volatileCandidates(forUserName: userName) {
    guard !user32Candidates.contains(where: { $0.account == candidate.0 }) else { continue }
    guard candidate.1.count == 32 else { continue }
    user32Candidates.append((account: candidate.0, data: candidate.1))
  }
  for candidate in User32Store.keychainCandidates(forUserName: userName) {
    guard !user32Candidates.contains(where: { $0.account == candidate.0 }) else { continue }
    guard candidate.1.count == 32 else { continue }
    user32Candidates.append((account: candidate.0, data: candidate.1))
  }
  if let sideLoadedMain = try? User32SideLoad.loadUser32Data(bundle: Bundle.main),
     sideLoadedMain.count == 32,
     !user32Candidates.contains(where: { $0.data == sideLoadedMain }) {
    user32Candidates.append((account: "sideload:main", data: sideLoadedMain))
  }
  if let sideLoadedPlugin = try? User32SideLoad.loadUser32Data(bundle: Bundle(for: EmotionDetectionPlugin.self)),
     sideLoadedPlugin.count == 32,
     !user32Candidates.contains(where: { $0.data == sideLoadedPlugin }) {
    user32Candidates.append((account: "sideload:plugin", data: sideLoadedPlugin))
  }
  if user32Candidates.isEmpty {
    let fetched = try user32Provider()
    guard fetched.count == 32 else {
      throw NSError(
        domain: "User32",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "user32 must be 32 bytes"]
      )
    }
    try User32Store.save(fetched, account: accountHint, requireBiometrics: false)
    user32Candidates.append((account: accountHint, data: fetched))
    NSLog("EmotionDetectionPlugin user32 provider fallback account=\(accountHint) bytes=\(fetched.count)")
  }

  var attempts: [String] = []
  for candidate in user32Candidates {
    let user32Hash = shortSHA256(candidate.data)
    do {
      let cek = try resolveCEKForUser32(
        manifest: manifest,
        effectiveModelId: effectiveModelId,
        userName: userName,
        user32: candidate.data
      )
      NSLog("EmotionDetectionPlugin CEK resolved account=\(candidate.account) u32=\(user32Hash)")
      return cek
    } catch {
      attempts.append("account=\(candidate.account) u32=\(user32Hash) err=\(error)")
    }
  }

  throw NSError(
    domain: "CEKAuth",
    code: -5,
    userInfo: [
      NSLocalizedDescriptionKey: "Failed CEK unwrap; model=\(effectiveModelId) account=\(accountHint) attempts=\(attempts.joined(separator: " | "))"
    ]
  )
}
