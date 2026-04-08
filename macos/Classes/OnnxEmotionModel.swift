import Foundation
import CoreGraphics
import onnxruntime_objc

enum OnnxEmotionError: LocalizedError {
  case emptyInputNames
  case emptyOutputNames
  case unsupportedOutputType
  case invalidTensorData
  case bitmapContextCreationFailed
  case imageDrawFailed

  var errorDescription: String? {
    switch self {
    case .emptyInputNames:
      return "ONNX model has no declared inputs."
    case .emptyOutputNames:
      return "ONNX model has no declared outputs."
    case .unsupportedOutputType:
      return "ONNX output tensor type is unsupported."
    case .invalidTensorData:
      return "ONNX output tensor data is invalid."
    case .bitmapContextCreationFailed:
      return "Failed to create bitmap context for ONNX preprocessing."
    case .imageDrawFailed:
      return "Failed to draw image for ONNX preprocessing."
    }
  }
}

final class OnnxEmotionModel {
  private static let labels = ["Anger", "Disgust", "Fear", "Happiness", "Neutral", "Sadness", "Surprise"]
  private static let targetWidth = 224
  private static let targetHeight = 224
  private static let meanRGB: (Float, Float, Float) = (103.939, 116.779, 123.68)

  private let session: ORTSession
  private let inputName: String
  private let outputNames: [String]

  init(modelURL: URL) throws {
    let env = try ORTEnv(loggingLevel: .warning)
    let sessionOptions = try ORTSessionOptions()
    _ = try? sessionOptions.setGraphOptimizationLevel(.all)
    _ = try? sessionOptions.setIntraOpNumThreads(2)
    let session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: sessionOptions)
    let inputNames = try session.inputNames()
    guard let firstInput = inputNames.first else { throw OnnxEmotionError.emptyInputNames }
    let outputNames = try session.outputNames()
    guard !outputNames.isEmpty else { throw OnnxEmotionError.emptyOutputNames }
    self.session = session
    self.inputName = firstInput
    self.outputNames = outputNames
  }

  func predict(faceImage: CGImage) throws -> [String: Double] {
    var lastError: Error?
    let tensors = try makeCandidateInputTensors(faceImage: faceImage)
    for (tensorData, shape) in tensors {
      do {
        let input = try ORTValue(
          tensorData: tensorData,
          elementType: .float,
          shape: shape
        )
        let outputs = try session.run(
          withInputs: [inputName: input],
          outputNames: Set(outputNames),
          runOptions: nil
        )
        if let decoded = try decodeOutput(outputs: outputs) {
          return decoded
        }
      } catch {
        lastError = error
        continue
      }
    }

    if let lastError {
      throw lastError
    }
    return [:]
  }

  private func makeCandidateInputTensors(faceImage: CGImage) throws -> [(NSMutableData, [NSNumber])] {
    let rgba = try rgbaBytes(
      image: faceImage,
      width: Self.targetWidth,
      height: Self.targetHeight
    )

    let w = Self.targetWidth
    let h = Self.targetHeight
    let channelSize = w * h
    let (rMean, gMean, bMean) = Self.meanRGB

    // Candidate A: NCHW float32 [1, 3, 224, 224]
    var nchw = [Float](repeating: 0, count: 1 * 3 * channelSize)
    for y in 0..<h {
      for x in 0..<w {
        let pixel = (y * w + x) * 4
        let r = Float(rgba[pixel + 0]) - rMean
        let g = Float(rgba[pixel + 1]) - gMean
        let b = Float(rgba[pixel + 2]) - bMean
        let base = y * w + x
        nchw[base] = r
        nchw[channelSize + base] = g
        nchw[(2 * channelSize) + base] = b
      }
    }

    // Candidate B: NHWC float32 [1, 224, 224, 3]
    var nhwc = [Float](repeating: 0, count: 1 * channelSize * 3)
    for y in 0..<h {
      for x in 0..<w {
        let pixel = (y * w + x) * 4
        let r = Float(rgba[pixel + 0]) - rMean
        let g = Float(rgba[pixel + 1]) - gMean
        let b = Float(rgba[pixel + 2]) - bMean
        let base = (y * w + x) * 3
        nhwc[base + 0] = r
        nhwc[base + 1] = g
        nhwc[base + 2] = b
      }
    }

    return [
      (toMutableData(nchw), [1, 3, NSNumber(value: h), NSNumber(value: w)]),
      (toMutableData(nhwc), [1, NSNumber(value: h), NSNumber(value: w), 3]),
    ]
  }

  private func decodeOutput(outputs: [String: ORTValue]) throws -> [String: Double]? {
    let candidateName = outputNames.first(where: { outputs[$0] != nil }) ?? outputs.keys.first
    guard let name = candidateName, let value = outputs[name] else { return nil }

    let typeInfo = try value.tensorTypeAndShapeInfo()
    guard typeInfo.elementType == .float else {
      throw OnnxEmotionError.unsupportedOutputType
    }

    let tensorData = try value.tensorData()
    let count = tensorData.length / MemoryLayout<Float>.size
    guard count > 0 else { throw OnnxEmotionError.invalidTensorData }

    var raw = [Float](repeating: 0, count: count)
    tensorData.getBytes(&raw, length: tensorData.length)

    if raw.count >= Self.labels.count {
      var map: [String: Double] = [:]
      for i in 0..<Self.labels.count {
        map[Self.labels[i]] = Double(raw[i])
      }
      return map
    }

    var map: [String: Double] = [:]
    for (idx, value) in raw.enumerated() {
      map["output_\(idx)"] = Double(value)
    }
    return map
  }

  private func toMutableData(_ values: [Float]) -> NSMutableData {
    let data = NSMutableData(length: values.count * MemoryLayout<Float>.size) ?? NSMutableData()
    values.withUnsafeBytes { bytes in
      guard let src = bytes.baseAddress else { return }
      data.mutableBytes.copyMemory(from: src, byteCount: bytes.count)
    }
    return data
  }

  private func rgbaBytes(image: CGImage, width: Int, height: Int) throws -> [UInt8] {
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
      throw OnnxEmotionError.bitmapContextCreationFailed
    }

    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
  }
}
