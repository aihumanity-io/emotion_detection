import Flutter
import UIKit
import CoreML
import CoreImage
import MobileCoreServices

@available(iOS 15.0, *)
private enum UserCodeBridgeError: LocalizedError {
    case emptyAccount
    case invalidBase64
    case invalidLength

    var errorDescription: String? {
        switch self {
        case .emptyAccount:
            return "userName must not be empty"
        case .invalidBase64:
            return "userCodeB64 must be valid base64"
        case .invalidLength:
            return "user code must decode to exactly 32 bytes"
        }
    }
}

@available(iOS 15.0, *)
private enum UserCodeBridge {
    static func saveUserCode(b64: String, userName: String, modelId: String?, requireBiometrics: Bool) throws {
        let account = UserCodeUtils.account(userName: userName, modelId: modelId)
        guard !account.isEmpty else { throw UserCodeBridgeError.emptyAccount }
        let trimmed = b64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: trimmed) else {
            throw UserCodeBridgeError.invalidBase64
        }
        guard decoded.count == 32 else { throw UserCodeBridgeError.invalidLength }
        try User32Store.save(decoded, account: account, requireBiometrics: requireBiometrics)
        print("UserCode: saved bytes=\(decoded.count) biometrics=\(requireBiometrics)")
    }

    static func clearUserCode(userName: String, modelId: String?) throws {
        let account = UserCodeUtils.account(userName: userName, modelId: modelId)
        guard !account.isEmpty else { throw UserCodeBridgeError.emptyAccount }
        try User32Store.delete(account: account)
    }
}

@available(iOS 15.0, *)
enum UserCodeUtils {
    static func sanitize(userName: String) -> String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func account(userName: String, modelId: String?) -> String {
        let base = sanitize(userName: userName)
        if let mid = modelId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !mid.isEmpty {
            return "\(base)|\(mid)"
        }
        return base
    }

    static func loadUser32(userName: String, modelId: String?) throws -> Data {
        let acct = account(userName: userName, modelId: modelId)
        if let cached = try? User32Store.load(account: acct) {
            print("User32: loadUser32 hit keychain for \(acct) bytes=\(cached.count)")
            return cached
        }
        let side = try User32SideLoad.loadUser32Data(bundle: .main)
        print("User32: loadUser32 fell back to sideload bytes=\(side.count)")
        return side
    }
}

@available(iOS 15.0, *)
private extension EmotionDetectionPlugin {
    static func resetModels() {
        onnxEmotionModel = nil
    }

    func ensureModelsReady() throws {
        if EmotionDetectionPlugin.onnxEmotionModel == nil {
            do {
                EmotionDetectionPlugin.onnxEmotionModel = try OnnxEmotionModel(userName: EmotionDetectionPlugin.currentUserName)
            } catch {
                print("ONNX model load failed: \(error.localizedDescription)")
                throw error
            }
        }

        if EmotionDetectionPlugin.onnxEmotionModel == nil {
            throw MLError.Error("No ONNX model could be loaded.")
        }
    }
}

@available(iOS 15.0, *)
public class EmotionDetectionPlugin: NSObject, FlutterPlugin {
    var image_count = 0
    static private var onnxEmotionModel: OnnxEmotionModel?
    static private var currentUserName: String = UserCodeUtils.sanitize(userName: "dev@tartalabs.io")


  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "face_emotion_detection", binaryMessenger: registrar.messenger())
    let instance = EmotionDetectionPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
      print("plugin: EmotionDetectionPlugin registered")
  }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        case "faceEmotion":
            self.faceEmotionDetection(result: result, call: call)

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

            
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func faceEmotionDetection(result: @escaping FlutterResult, call: FlutterMethodCall) {
        do {
            try ensureModelsReady()
        } catch {
            result(FlutterError(code: "model_load_error", message: error.localizedDescription, details: nil))
            return
        }
        do {
                guard let arguments = call.arguments as? [String:Any],
                let data:FlutterStandardTypedData = arguments["image"] as? FlutterStandardTypedData else {
                    result("Couldn't find image data")
                    return
                }
                let width = arguments["width"] as? Int ?? 0
                let height = arguments["height"] as? Int ?? 0
                let orientation = arguments["orientation"] as? String ?? "up"
                let left = arguments["left"] as? Int ?? 0
                let top = arguments["top"] as? Int ?? 0
              let boxwidth = arguments["boxwidth"] as? Int ?? 0
              let boxheight = arguments["boxheight"] as? Int ?? 0


                #if os(iOS)
                    if #available(iOS 15.0, *) {
                        //let nsData = NSData(bytes: data, length: 4*width*height)
                        let dataD = Data(data.data)
                      //let image = UIImage(data: data)
                        //let uiImage = UIImage(data: dataD)
                        let ciImage = convertImage(Data(data.data),CGSize(width: width , height: height),CIFormat.BGRA8,orientation)
                        if ciImage != nil {
                            let cgImage = convertCIImageToCGImage(ciImage!)
                            if cgImage != nil {
                                do {
                                    let faceBox = CGRect(x: left, y: top, width: boxwidth, height: boxheight)
                                    guard let faceImage = cgImage!.cropping(to: faceBox) else {
                                        print("failed to crop face image")
                                        return result("None")
                                    }

                                    guard let onnxModel = EmotionDetectionPlugin.onnxEmotionModel else {
                                        throw MLError.Error("ONNX model is not loaded.")
                                    }
                                    let startT = Date().timeIntervalSince1970
                                    let retFromModel = try onnxModel.runModel(faceImage: faceImage)
                                    print("ONNX Model time: \((Date().timeIntervalSince1970 - startT)*1000) ms")
                                    return result(retFromModel)

                                } catch {
                                    print("Model Run Failed")
                                    return result("None")
                                }
                            } else {
                                print("failed to convert to image")
                                return result("None")
                            }
                        }
                    }
                #endif
                }
                catch {
                        result(FlutterError(code: "MODEL_LOAD_ERROR", message: error.localizedDescription, details: nil))
                      }
    }
    func saveImage(image: CGImage, name: String = "face") {
        let path = getDocumentsDirectory()
        let name = "image_\(Int.random(in: 1..<100))_\(name).jpeg"
        let filename = path.appendingPathComponent(name)
        writeCGImage(image, to: filename)
    }
  @discardableResult func writeCGImage(_ image: CGImage, to destinationURL: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, kUTTypeJPEG, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
  }

    func getDocumentsDirectory() -> URL { // returns your application folder
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        //let documentsDirectory = paths[0]
        return paths!
    }

    private func handleSetUserCode(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let userName = args["userName"] as? String,
              let userCodeB64 = args["userCodeB64"] as? String else {
            result(FlutterError(code: "invalid_args", message: "userName and userCodeB64 are required", details: nil))
            return
        }
        let requireBiometrics = args["requireBiometrics"] as? Bool ?? false
        let modelId = args["modelId"] as? String
        do {
            try UserCodeBridge.saveUserCode(b64: userCodeB64, userName: userName, modelId: modelId, requireBiometrics: requireBiometrics)
            EmotionDetectionPlugin.currentUserName = UserCodeUtils.sanitize(userName: userName)
            EmotionDetectionPlugin.resetModels()
            result(nil)
        } catch {
            result(FlutterError(code: "user_code_error", message: error.localizedDescription, details: nil))
        }
    }

    private func handleClearUserCode(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let userName = args["userName"] as? String else {
            result(FlutterError(code: "invalid_args", message: "userName is required", details: nil))
            return
        }
        let modelId = args["modelId"] as? String
        do {
            try UserCodeBridge.clearUserCode(userName: userName, modelId: modelId)
            EmotionDetectionPlugin.resetModels()
            result(nil)
        } catch {
            result(FlutterError(code: "user_code_error", message: error.localizedDescription, details: nil))
        }
    }

    private func handleSetKeyShard(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelId = args["modelId"] as? String,
              let shardB64 = args["keyShardB64"] as? String else {
            result(FlutterError(code: "invalid_args", message: "modelId and keyShardB64 are required", details: nil))
            return
        }
        let expiresAtMs = (args["expiresAtMs"] as? NSNumber)?.int64Value ?? (args["expiresAt"] as? NSNumber)?.int64Value
        do {
            try ShardCache.setShard(modelId: modelId, base64: shardB64, expiresAtMs: expiresAtMs)
            if let userName = (args["userName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !userName.isEmpty {
                let acct = UserCodeUtils.sanitize(userName: userName)
                try? ShardCache.setShard(modelId: acct, base64: shardB64, expiresAtMs: expiresAtMs)
                print("setKeyShard: stored for modelId=\(modelId)")
            } else {
                print("setKeyShard: stored for modelId=\(modelId) (no user alias)")
            }
            result(nil)
        } catch {
            result(FlutterError(code: "shard_store_error", message: error.localizedDescription, details: nil))
        }
    }

    private func handleClearKeyShard(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelId = args["modelId"] as? String else {
            result(FlutterError(code: "invalid_args", message: "modelId is required", details: nil))
            return
        }
        ShardCache.clearShard(modelId: modelId)
        result(nil)
    }

    private func handleSetModelLicense(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelId = args["modelId"] as? String else {
            result(FlutterError(code: "invalid_args", message: "modelId is required", details: nil))
            return
        }

        do {
            if let licenseMap = args["license"] as? [String: Any] {
                try LicenseCache.setLicense(modelId: modelId, licenseMap: licenseMap)
            } else if let licenseJson = args["licenseJson"] as? String {
                guard let data = licenseJson.data(using: .utf8) else {
                    result(FlutterError(code: "license_error", message: "licenseJson is not valid UTF-8", details: nil))
                    return
                }
                try LicenseCache.setLicense(modelId: modelId, jsonData: data)
            } else {
                result(FlutterError(code: "invalid_args", message: "license or licenseJson is required", details: nil))
                return
            }
            EmotionDetectionPlugin.resetModels()
            result(nil)
        } catch {
            result(FlutterError(code: "license_error", message: error.localizedDescription, details: nil))
        }
    }

    private func handleClearModelLicense(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelId = args["modelId"] as? String else {
            result(FlutterError(code: "invalid_args", message: "modelId is required", details: nil))
            return
        }
        LicenseCache.clear(modelId: modelId)
        EmotionDetectionPlugin.resetModels()
        result(nil)
    }


    #if os(iOS)
    @available(iOS 15.0, *)
    #endif
    func convertImage(_ data: Data,_ imageSize: CGSize,_ format: CIFormat,_ oriString: String) -> CIImage? {
        var orientation:CGImagePropertyOrientation = CGImagePropertyOrientation.downMirrored
        switch oriString{
            case "down":
                orientation = CGImagePropertyOrientation.down
                break
            case "right":
                orientation = CGImagePropertyOrientation.right
                break
            case "rightMirrored":
                orientation = CGImagePropertyOrientation.rightMirrored
                break
            case "left":
                orientation = CGImagePropertyOrientation.left
                break
            case "leftMirrored":
                orientation = CGImagePropertyOrientation.leftMirrored
                break
            case "up":
                orientation = CGImagePropertyOrientation.up
                break
            case "upMirrored":
                orientation = CGImagePropertyOrientation.upMirrored
                break
            default:
                orientation = CGImagePropertyOrientation.downMirrored
                break
        }

        if data.count == (Int(imageSize.height)*Int(imageSize.width)*4){
            // Create a bitmap graphics context with the sample buffer data
            return  CIImage(bitmapData: data, bytesPerRow: Int(imageSize.width)*4, size: imageSize, format: format, colorSpace: nil)
        } else {
            print("Image format not known")

            return nil

        }
}

    func convertCIImageToCGImage(_ inputImage: CIImage) -> CGImage? {
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
            return cgImage
        }
        return nil
    }

}
