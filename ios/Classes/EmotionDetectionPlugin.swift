import Flutter
import UIKit
import CoreML
import CoreImage
import MobileCoreServices

@available(iOS 15.0, *)
public class EmotionDetectionPlugin: NSObject, FlutterPlugin {
    var image_count = 0
    static private var emotionModelMobilenet: EmotionMobilenet?
    static private var ahiEmotionModel: AIHFerModel?


  public static func register(with registrar: FlutterPluginRegistrar) {
    try! ahiEmotionModel = AIHFerModel()
      try! emotionModelMobilenet = EmotionMobilenet()
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

            
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func faceEmotionDetection(result: @escaping FlutterResult, call: FlutterMethodCall) {
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
            result(nil)
        } catch {
            result(FlutterError(code: "user_code_error", message: error.localizedDescription, details: nil))
        }
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
