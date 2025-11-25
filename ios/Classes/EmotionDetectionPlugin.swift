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
    static func saveUserCode(b64: String, userName: String, requireBiometrics: Bool) throws {
        let account = UserCodeUtils.sanitize(userName: userName)
        guard !account.isEmpty else { throw UserCodeBridgeError.emptyAccount }
        let trimmed = b64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: trimmed) else {
            throw UserCodeBridgeError.invalidBase64
        }
        guard decoded.count == 32 else { throw UserCodeBridgeError.invalidLength }
        try User32Store.save(decoded, account: account, requireBiometrics: requireBiometrics)
        print("UserCode: saved for account=\(account) bytes=\(decoded.count) biometrics=\(requireBiometrics)")
    }

    static func clearUserCode(userName: String) throws {
        let account = UserCodeUtils.sanitize(userName: userName)
        guard !account.isEmpty else { throw UserCodeBridgeError.emptyAccount }
        try User32Store.delete(account: account)
    }
}

@available(iOS 15.0, *)
enum UserCodeUtils {
    static func sanitize(userName: String) -> String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func loadUser32(userName: String) throws -> Data {
        let acct = sanitize(userName: userName)
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
        emotionModelMobilenet = nil
        ahiEmotionModel = nil
    }

    func ensureModelsReady() throws {
        if EmotionDetectionPlugin.ahiEmotionModel == nil {
            EmotionDetectionPlugin.ahiEmotionModel = try AIHFerModel(userName: EmotionDetectionPlugin.currentUserName)
        }
        if EmotionDetectionPlugin.emotionModelMobilenet == nil {
            EmotionDetectionPlugin.emotionModelMobilenet = try EmotionMobilenet(userName: EmotionDetectionPlugin.currentUserName)
        }
    }
}

@available(iOS 15.0, *)
public class EmotionDetectionPlugin: NSObject, FlutterPlugin {
    var image_count = 0
    static private var emotionModelMobilenet: EmotionMobilenet?
    static private var ahiEmotionModel: AIHFerModel?
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
       /*
        guard let modelURL = Bundle.main.url(forResource: "AIHFerModel", withExtension: "mlpackage") else {
                result(FlutterError(code: "MODEL_NOT_FOUND", message: "Could not find model", details: nil))
                return
              }

        */
        //var ahiEmotionModel: AIHFerModel?
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
              let landmarks = arguments["landmarks"] as? [[Int]] ?? [[]]


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
                                    let faceImage = cgImage!.cropping(to: faceBox)

                                    if landmarks.count >= 3 {
                                        // order [mijnx, miny, maxx, maxy]
                                        let leftEyeImage = cgImage!.cropping(to:
                                                                              CGRect(x:landmarks[0][0], y:landmarks[0][1],
                                                                                     width: landmarks[0][2]-landmarks[0][0],
                                                                                     height: landmarks[0][3]-landmarks[0][1])
                                        )

                                        let rightEyeImage = cgImage!.cropping(to:
                                                                                  CGRect(x:landmarks[1][0], y:landmarks[1][1],
                                                                                         width: (landmarks[1][2]-landmarks[1][0]),
                                                                                         height: (landmarks[1][3]-landmarks[1][1])))

                                        let mouthImage = cgImage!.cropping(to:
                                                                              CGRect(x:landmarks[2][0], y:landmarks[2][1],
                                                                                     width: (landmarks[2][2]-landmarks[2][0]),
                                                                                     height: (landmarks[2][3]-landmarks[2][1])))

                                        if(leftEyeImage == nil || rightEyeImage == nil || mouthImage == nil) {
                                            let startT = Date().timeIntervalSince1970
                                            let retFromModel = try EmotionDetectionPlugin.emotionModelMobilenet!.runModel(faceImage: faceImage!)
                                            print("Mobilenet Model time: \((Date().timeIntervalSince1970 - startT)*1000) ms")
                                            return result(retFromModel)

                                        }

                                        /// Used to debug
                                        if image_count > 0 {
                                            saveImage(image: faceImage!)
                                            saveImage(image: leftEyeImage!, name: "leftEye")
                                            saveImage(image: rightEyeImage!, name: "rightEye")
                                            saveImage(image: mouthImage!, name: "mouth")
                                            image_count = image_count - 1
                                        }
                                        //
                                        //let retFromModel = try emotionModel!.runModel(faceImage: faceImage!)
                                        let startT = Date().timeIntervalSince1970
                                        let retFromModel = try EmotionDetectionPlugin.ahiEmotionModel!.runModel(faceImage: faceImage!, leftEyeImage: leftEyeImage!,
                                                                                         rightEyeImage: rightEyeImage!, mouthImage: mouthImage!)
                                        print("AIH Model time: \((Date().timeIntervalSince1970 - startT)*1000) ms")
                                        return result(retFromModel)
                                    } else {
                                        // only face dtected
                                        let startT = Date().timeIntervalSince1970
                                        let retFromModel = try EmotionDetectionPlugin.emotionModelMobilenet!.runModel(faceImage: faceImage!)
                                        print("Mobilenet Model time: \((Date().timeIntervalSince1970 - startT)*1000) ms")
                                        return result(retFromModel)

                                    }

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
        do {
            try UserCodeBridge.saveUserCode(b64: userCodeB64, userName: userName, requireBiometrics: requireBiometrics)
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
        do {
            try UserCodeBridge.clearUserCode(userName: userName)
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
                print("setKeyShard: stored for modelId=\(modelId) and user=\(acct)")
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
