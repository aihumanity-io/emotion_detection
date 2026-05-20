import CoreGraphics
import CoreML
import Foundation

enum CoreMLImageNetEmotionError: LocalizedError {
    case bitmapContextCreationFailed
    case missingInput(String)
    case unsupportedOutput

    var errorDescription: String? {
        switch self {
        case .bitmapContextCreationFailed:
            return "Failed to create bitmap context for Core ML preprocessing."
        case .missingInput(let name):
            return "Core ML model is missing required input '\(name)'."
        case .unsupportedOutput:
            return "Core ML model output is unsupported."
        }
    }
}

enum CoreMLImageNetEmotionModel {
    private static let labels = ["Anger", "Disgust", "Fear", "Happiness", "Neutral", "Sadness", "Surprise"]
    private static let inputName = "pixel_values"
    private static let targetWidth = 224
    private static let targetHeight = 224
    private static let meanRGB: (Float, Float, Float) = (0.485, 0.456, 0.406)
    private static let stdRGB: (Float, Float, Float) = (0.229, 0.224, 0.225)

    static func predict(model: MLModel, faceImage: CGImage) throws -> [String: Double] {
        let start = ProcessInfo.processInfo.systemUptime
        let input = try makeInput(from: faceImage)
        let inputReady = ProcessInfo.processInfo.systemUptime
        let inputFeatureName = model.modelDescription.inputDescriptionsByName[inputName] == nil
            ? firstMultiArrayInputName(model: model)
            : inputName
        guard let inputFeatureName else {
            throw CoreMLImageNetEmotionError.missingInput(inputName)
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputFeatureName: MLFeatureValue(multiArray: input)
        ])
        let output = try model.prediction(from: provider)
        let predictionReady = ProcessInfo.processInfo.systemUptime
        let result = try decode(output: output)
        let decoded = ProcessInfo.processInfo.systemUptime
        NSLog(
            "EmotionDetectionPlugin CoreML timing model=ImageNetEmotion preprocessMs=%.2f inferenceMs=%.2f decodeMs=%.2f totalMs=%.2f",
            (inputReady - start) * 1000.0,
            (predictionReady - inputReady) * 1000.0,
            (decoded - predictionReady) * 1000.0,
            (decoded - start) * 1000.0
        )
        return result
    }

    private static func firstMultiArrayInputName(model: MLModel) -> String? {
        for (name, desc) in model.modelDescription.inputDescriptionsByName {
            if desc.type == .multiArray { return name }
        }
        return nil
    }

    private static func makeInput(from image: CGImage) throws -> MLMultiArray {
        let rgba = try rgbaBytes(image: image, width: targetWidth, height: targetHeight)
        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: targetHeight), NSNumber(value: targetWidth)],
            dataType: .float32
        )
        let ptr = array.dataPointer.assumingMemoryBound(to: Float.self)
        let channelSize = targetWidth * targetHeight
        let (rMean, gMean, bMean) = meanRGB
        let (rStd, gStd, bStd) = stdRGB

        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let pixel = (y * targetWidth + x) * 4
                let r = (Float(rgba[pixel + 0]) / 255.0 - rMean) / rStd
                let g = (Float(rgba[pixel + 1]) / 255.0 - gMean) / gStd
                let b = (Float(rgba[pixel + 2]) / 255.0 - bMean) / bStd
                let base = y * targetWidth + x
                ptr[base] = r
                ptr[channelSize + base] = g
                ptr[(2 * channelSize) + base] = b
            }
        }
        return array
    }

    private static func rgbaBytes(image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw CoreMLImageNetEmotionError.bitmapContextCreationFailed
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private static func decode(output: MLFeatureProvider) throws -> [String: Double] {
        var scores: [Float]?
        for name in ["Identity", "output", "probabilities", "logits"] {
            if let multiArray = output.featureValue(for: name)?.multiArrayValue {
                scores = toFloatArray(multiArray)
                break
            }
        }
        if scores == nil {
            for name in output.featureNames {
                if let dict = output.featureValue(for: name)?.dictionaryValue {
                    var map: [String: Double] = [:]
                    for (key, value) in dict {
                        if let label = key as? String {
                            map[label] = value.doubleValue
                        }
                    }
                    if !map.isEmpty { return map }
                }
                if let multiArray = output.featureValue(for: name)?.multiArrayValue {
                    scores = toFloatArray(multiArray)
                    break
                }
            }
        }
        guard let scores else { throw CoreMLImageNetEmotionError.unsupportedOutput }
        var map: [String: Double] = [:]
        for i in 0..<min(scores.count, labels.count) {
            map[labels[i]] = Double(scores[i])
        }
        return map
    }

    private static func toFloatArray(_ multiArray: MLMultiArray) -> [Float] {
        var result = [Float](repeating: 0, count: multiArray.count)
        switch multiArray.dataType {
        case .float32:
            let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
            for i in 0..<multiArray.count { result[i] = ptr[i] }
        case .double:
            let ptr = multiArray.dataPointer.assumingMemoryBound(to: Double.self)
            for i in 0..<multiArray.count { result[i] = Float(ptr[i]) }
        case .float16:
            let ptr = multiArray.dataPointer.assumingMemoryBound(to: UInt16.self)
            for i in 0..<multiArray.count { result[i] = Float(Float16(bitPattern: ptr[i])) }
        default:
            break
        }
        return result
    }
}
