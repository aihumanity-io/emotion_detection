import Foundation
import CoreGraphics
import CryptoKit
import CoreML
import os
import onnxruntime_objc

@available(iOS 15.0, *)
enum OnnxModelError: LocalizedError {
    case emptyInputNames
    case emptyOutputNames
    case unsupportedOutputType
    case invalidTensorData
    case bitmapContextCreationFailed
    case invalidManifest(String)

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
        case .invalidManifest(let reason):
            return "Invalid ONNX manifest: \(reason)"
        }
    }
}

@available(iOS 15.0, *)
private func onnxFrameworkBundle() -> Bundle {
    Bundle(for: OnnxEmotionModel.self)
}

@available(iOS 15.0, *)
final class OnnxEmotionModel {
    private static let labels = ["Anger", "Disgust", "Fear", "Happiness", "Neutral", "Sadness", "Surprise"]
    private static let targetWidth = 224
    private static let targetHeight = 224
    private static let meanRGB: (Float, Float, Float) = (103.939, 116.779, 123.68)

    private let env: ORTEnv
    private let session: ORTSession
    private let inputName: String
    private let outputNames: [String]
    private let modelURL: URL

    init(userName: String) throws {
        let normalizedUserName = UserCodeUtils.sanitize(userName: userName)
        let fw = onnxFrameworkBundle()
        let baseCandidates = ["aih_emotion_pretrained1573_converted_2025-03-13-16-43-21_onnx"]
        var lastCandidateError: Error?
        var selectedEnv: ORTEnv?
        var selectedSession: ORTSession?
        var selectedInputName: String?
        var selectedOutputNames: [String]?
        var selectedModelURL: URL?

        for baseName in baseCandidates {
            do {
                let manifestURL = try FileIO.bundleURL(name: baseName, ext: "manifest.json", in: fw)
                let manifestData = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
                let modelId = manifest.model_id ?? manifest.modelId ?? manifest.model_name
                print("Manifest \(baseName): id=\(manifest.model_id ?? manifest.modelId ?? "nil") name=\(manifest.model_name ?? "nil") shard_required=\(manifest.shard_required ?? false)")

                let cekData = try obtainCEK_UserCodeGateSync(
                    manifest: manifest,
                    userName: normalizedUserName,
                    modelId: modelId,
                    user32Provider: {
                        try UserCodeUtils.loadUser32(userName: normalizedUserName, modelId: modelId)
                    }
                )

                let modelURL = try Self.decryptOnnxFile(
                    baseName: baseName,
                    manifest: manifest,
                    framework: fw,
                    cekData: cekData
                )

                let env = try ORTEnv(loggingLevel: .warning)
                let sessionOptions = try ORTSessionOptions()
                _ = try? sessionOptions.setGraphOptimizationLevel(.all)
                _ = try? sessionOptions.setIntraOpNumThreads(2)
                let session = try ORTSession(
                    env: env,
                    modelPath: modelURL.path,
                    sessionOptions: sessionOptions
                )
                let inputNames = try session.inputNames()
                guard let firstInput = inputNames.first else { throw OnnxModelError.emptyInputNames }
                let outputNames = try session.outputNames()
                guard !outputNames.isEmpty else { throw OnnxModelError.emptyOutputNames }

                selectedEnv = env
                selectedSession = session
                selectedInputName = firstInput
                selectedOutputNames = outputNames
                selectedModelURL = modelURL
                print("onnx model \(baseName) loaded")
                lastCandidateError = nil
                break
            } catch {
                lastCandidateError = error
                print("ONNX candidate \(baseName) failed: \(error.localizedDescription)")
            }
        }

        guard let env = selectedEnv,
              let session = selectedSession,
              let inputName = selectedInputName,
              let outputNames = selectedOutputNames,
              let modelURL = selectedModelURL else {
            throw lastCandidateError ?? MLError.Error("No compatible ONNX model artifact found.")
        }

        self.env = env
        self.session = session
        self.inputName = inputName
        self.outputNames = outputNames
        self.modelURL = modelURL
    }

    func runModel(faceImage: CGImage) throws -> [String: Float] {
        _ = env
        _ = modelURL
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
            }
        }
        if let lastError {
            throw lastError
        }
        return [:]
    }

    private static func decryptOnnxFile(
        baseName: String,
        manifest: Manifest,
        framework: Bundle,
        cekData: Data
    ) throws -> URL {
        let sourceKind = manifest.sourceKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let sourceKind, !sourceKind.isEmpty, sourceKind != "file" {
            throw OnnxModelError.invalidManifest("sourceKind=\(sourceKind)")
        }

        let encURL = try FileIO.bundleURL(name: baseName, ext: "enc", in: framework)
        let encData = try Data(contentsOf: encURL)

        if let encHex = manifest.enc_sha256, !encHex.isEmpty {
            let encHash = ModelCrypto.sha256Hex(encData)
            guard encHash == encHex else {
                throw EncryptedLoadError.integrityFailed
            }
        }

        let key = SymmetricKey(data: cekData)
        let aad = Data(manifest.aad.utf8)
        let modelData: Data
        if let ivRaw = manifest.gcmIv, !ivRaw.isEmpty {
            guard let iv = Data(base64Encoded: Self.normalizeB64(ivRaw)) else {
                throw EncryptedLoadError.manifestMissing
            }
            modelData = try ModelCrypto.decrypt(iv: iv, combinedCtTag: encData, key: key, aad: aad)
        } else {
            modelData = try ModelCrypto.decrypt(combined: encData, key: key, aad: aad)
        }

        if let plainB64URL = manifest.plainSha256, !plainB64URL.isEmpty {
            let calc = Self.sha256Base64URL(modelData)
            guard calc == plainB64URL else {
                throw EncryptedLoadError.integrityFailed
            }
        } else if let zipHex = manifest.zip_sha256, !zipHex.isEmpty {
            let zipHash = ModelCrypto.sha256Hex(modelData)
            guard zipHash == zipHex else {
                throw EncryptedLoadError.integrityFailed
            }
        }

        let work = try FileIO.tempDir("model_dec_file_\(baseName)")
        let modelURL = work.appendingPathComponent("model_\(baseName).onnx")
        try modelData.write(to: modelURL, options: .atomic)
        return modelURL
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

    private func decodeOutput(outputs: [String: ORTValue]) throws -> [String: Float]? {
        let candidateName = outputNames.first(where: { outputs[$0] != nil }) ?? outputs.keys.first
        guard let name = candidateName, let value = outputs[name] else { return nil }

        let typeInfo = try value.tensorTypeAndShapeInfo()
        guard typeInfo.elementType == .float else {
            throw OnnxModelError.unsupportedOutputType
        }

        let tensorData = try value.tensorData()
        let count = tensorData.length / MemoryLayout<Float>.size
        guard count > 0 else { throw OnnxModelError.invalidTensorData }

        var raw = [Float](repeating: 0, count: count)
        tensorData.getBytes(&raw, length: tensorData.length)

        if raw.count >= Self.labels.count {
            var map: [String: Float] = [:]
            for i in 0..<Self.labels.count {
                map[Self.labels[i]] = raw[i]
            }
            return map
        }

        var map: [String: Float] = [:]
        for (idx, value) in raw.enumerated() {
            map["output_\(idx)"] = value
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
            throw OnnxModelError.bitmapContextCreationFailed
        }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private static func normalizeB64(_ value: String) -> String {
        var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let missing = (4 - s.count % 4) % 4
        if missing > 0 {
            s = s.padding(toLength: s.count + missing, withPad: "=", startingAt: 0)
        }
        return s
    }

    private static func sha256Base64URL(_ data: Data) -> String {
        let digest = Data(SHA256.hash(data: data))
        return digest
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
