import CoreGraphics
import Foundation
import Vision

public struct EmotionFaceBox: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var confidence: Double

    public init(x: Double, y: Double, width: Double, height: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
    }
}

public struct EmotionCameraFrame: Equatable {
    public var image: EmotionImage
    public var timestampSeconds: Double

    public init(image: EmotionImage, timestampSeconds: Double) {
        self.image = image
        self.timestampSeconds = timestampSeconds
    }
}

public protocol EmotionFaceDetecting {
    func detectFace(in image: EmotionImage) throws -> EmotionFaceBox?
}

public protocol EmotionCameraFrameSource {
    func start(_ onFrame: @escaping (EmotionCameraFrame) -> Void) throws
    func stop()
}

public final class EmotionCameraPredictionSession {
    private let sdk: EmotionNativeSDK
    private let modelID: String
    private let faceDetector: EmotionFaceDetecting

    public init(sdk: EmotionNativeSDK, modelID: String, faceDetector: EmotionFaceDetecting) {
        self.sdk = sdk
        self.modelID = modelID
        self.faceDetector = faceDetector
    }

    public func predict(frame: EmotionCameraFrame) throws -> EmotionPrediction? {
        guard try faceDetector.detectFace(in: frame.image) != nil else {
            return nil
        }
        return try sdk.predict(modelID: modelID, image: frame.image)
    }
}

public final class VisionFaceDetector: EmotionFaceDetecting {
    public init() {}

    public func detectFace(in image: EmotionImage) throws -> EmotionFaceBox? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: try cgImage(from: image), orientation: .up)
        try handler.perform([request])
        return request.results?
            .compactMap { observation in
                EmotionFaceBox(
                    x: observation.boundingBox.origin.x,
                    y: observation.boundingBox.origin.y,
                    width: observation.boundingBox.width,
                    height: observation.boundingBox.height,
                    confidence: Double(observation.confidence)
                )
            }
            .max { lhs, rhs in lhs.confidence < rhs.confidence }
    }

    private func cgImage(from image: EmotionImage) throws -> CGImage {
        guard let provider = CGDataProvider(data: image.rgbData as CFData) else {
            throw EmotionSDKStatus.invalidArgument
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        guard let cgImage = CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: image.width * 3,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw EmotionSDKStatus.invalidArgument
        }
        return cgImage
    }
}
