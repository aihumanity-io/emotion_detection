import Foundation
import XCTest
@testable import EmotionNativeSDK

final class CameraAdapterTests: XCTestCase {
    func testCameraPredictionSkipsFramesWithoutFace() throws {
        let core = CameraCore()
        let sdk = EmotionNativeSDK(core: core)
        let detector = FakeFaceDetector(face: nil)
        let session = EmotionCameraPredictionSession(
            sdk: sdk,
            modelID: "aih_fer2025",
            faceDetector: detector
        )

        try prepare(sdk: sdk)
        let prediction = try session.predict(frame: frame())

        XCTAssertNil(prediction)
        XCTAssertEqual(detector.detectedImages.count, 1)
        XCTAssertEqual(core.predictCount, 0)
    }

    func testCameraPredictionUsesSdkWhenFaceIsDetected() throws {
        let core = CameraCore()
        let sdk = EmotionNativeSDK(core: core)
        let detector = FakeFaceDetector(
            face: EmotionFaceBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4, confidence: 0.95)
        )
        let session = EmotionCameraPredictionSession(
            sdk: sdk,
            modelID: "aih_fer2025",
            faceDetector: detector
        )

        try prepare(sdk: sdk)
        let prediction = try XCTUnwrap(session.predict(frame: frame()))

        XCTAssertEqual(prediction.topLabelIndex, 4)
        XCTAssertEqual(core.predictCount, 1)
        XCTAssertEqual(core.lastImage, detector.detectedImages.first)
    }

    func testFakeFrameSourceSmoke() throws {
        let source = FakeFrameSource(frames: [try frame(), try frame(timestamp: 2)])
        var timestamps: [Double] = []

        try source.start { frame in
            timestamps.append(frame.timestampSeconds)
        }
        source.stop()

        XCTAssertEqual(timestamps, [1, 2])
        XCTAssertTrue(source.didStop)
    }

    private func prepare(sdk: EmotionNativeSDK) throws {
        let model = EmotionModelConfiguration(
            modelID: "aih_fer2025",
            manifestPath: "/models/manifest.json",
            encryptedModelPath: "/models/model.enc"
        )
        try sdk.initialize()
        try sdk.registerModel(configuration: model)
        try sdk.warmUp(modelID: model.modelID)
    }

    private func frame(timestamp: Double = 1) throws -> EmotionCameraFrame {
        EmotionCameraFrame(
            image: try EmotionImage(width: 1, height: 1, rgbData: Data([255, 0, 0])),
            timestampSeconds: timestamp
        )
    }
}

private final class FakeFaceDetector: EmotionFaceDetecting {
    let face: EmotionFaceBox?
    var detectedImages: [EmotionImage] = []

    init(face: EmotionFaceBox?) {
        self.face = face
    }

    func detectFace(in image: EmotionImage) throws -> EmotionFaceBox? {
        detectedImages.append(image)
        return face
    }
}

private final class CameraCore: EmotionNativeCoreClient {
    var predictCount = 0
    var lastImage: EmotionImage?

    func initialize(configuration: EmotionSDKConfiguration) -> EmotionSDKStatus {
        .ok
    }

    func registerModel(configuration: EmotionModelConfiguration) -> EmotionSDKStatus {
        .ok
    }

    func warmUp(modelID: String) -> EmotionSDKStatus {
        .ok
    }

    func predict(modelID: String, image: EmotionImage) -> Result<EmotionPrediction, EmotionSDKStatus> {
        predictCount += 1
        lastImage = image
        return .success(
            EmotionPrediction(
                topLabelIndex: 4,
                topProbability: 0.9,
                scores: [EmotionClassScore(labelIndex: 4, probability: 0.9)]
            )
        )
    }

    func unload(modelID: String) -> EmotionSDKStatus {
        .ok
    }

    func shutdown() -> EmotionSDKStatus {
        .ok
    }
}

private final class FakeFrameSource: EmotionCameraFrameSource {
    let frames: [EmotionCameraFrame]
    var didStop = false

    init(frames: [EmotionCameraFrame]) {
        self.frames = frames
    }

    func start(_ onFrame: @escaping (EmotionCameraFrame) -> Void) throws {
        frames.forEach(onFrame)
    }

    func stop() {
        didStop = true
    }
}
