import XCTest
@testable import EmotionNativeSDK

final class EmotionNativeSDKTests: XCTestCase {
    func testLifecycleForwardsCallsInOrder() throws {
        let core = FakeCore()
        let sdk = EmotionNativeSDK(core: core)
        let model = EmotionModelConfiguration(
            modelID: "aih_fer2025",
            manifestPath: "/models/manifest.json",
            encryptedModelPath: "/models/model.enc"
        )
        let image = try EmotionImage(width: 1, height: 1, rgbData: Data([255, 0, 0]))

        try sdk.initialize()
        try sdk.registerModel(configuration: model)
        try sdk.warmUp(modelID: model.modelID)
        let prediction = try sdk.predict(modelID: model.modelID, image: image)
        try sdk.unload(modelID: model.modelID)
        try sdk.shutdown()

        XCTAssertEqual(prediction.topLabelIndex, 4)
        XCTAssertEqual(
            core.events,
            ["initialize", "register:aih_fer2025", "warmUp:aih_fer2025",
             "predict:aih_fer2025", "unload:aih_fer2025", "shutdown"]
        )
    }

    func testPredictRequiresRegisteredModel() throws {
        let sdk = EmotionNativeSDK(core: FakeCore())
        let image = try EmotionImage(width: 1, height: 1, rgbData: Data([0, 0, 0]))

        XCTAssertThrowsError(try sdk.predict(modelID: "missing", image: image)) { error in
            XCTAssertEqual(error as? EmotionSDKStatus, .notInitialized)
        }

        try sdk.initialize()
        XCTAssertThrowsError(try sdk.predict(modelID: "missing", image: image)) { error in
            XCTAssertEqual(error as? EmotionSDKStatus, .modelNotFound)
        }
    }

    func testFailedRegisterDoesNotMarkModelRegistered() throws {
        let core = FakeCore(registerStatus: .manifestInvalid)
        let sdk = EmotionNativeSDK(core: core)
        let model = EmotionModelConfiguration(
            modelID: "aih_fer2025",
            manifestPath: "/models/manifest.json",
            encryptedModelPath: "/models/model.enc"
        )

        try sdk.initialize()
        XCTAssertThrowsError(try sdk.registerModel(configuration: model)) { error in
            XCTAssertEqual(error as? EmotionSDKStatus, .manifestInvalid)
        }
        XCTAssertThrowsError(try sdk.warmUp(modelID: model.modelID)) { error in
            XCTAssertEqual(error as? EmotionSDKStatus, .modelNotFound)
        }
    }
}

private final class FakeCore: EmotionNativeCoreClient {
    var events: [String] = []
    let registerStatus: EmotionSDKStatus

    init(registerStatus: EmotionSDKStatus = .ok) {
        self.registerStatus = registerStatus
    }

    func initialize(configuration: EmotionSDKConfiguration) -> EmotionSDKStatus {
        events.append("initialize")
        return .ok
    }

    func registerModel(configuration: EmotionModelConfiguration) -> EmotionSDKStatus {
        events.append("register:\(configuration.modelID)")
        return registerStatus
    }

    func warmUp(modelID: String) -> EmotionSDKStatus {
        events.append("warmUp:\(modelID)")
        return .ok
    }

    func predict(modelID: String, image: EmotionImage) -> Result<EmotionPrediction, EmotionSDKStatus> {
        events.append("predict:\(modelID)")
        return .success(
            EmotionPrediction(
                topLabelIndex: 4,
                topProbability: 0.9,
                scores: [EmotionClassScore(labelIndex: 4, probability: 0.9)]
            )
        )
    }

    func unload(modelID: String) -> EmotionSDKStatus {
        events.append("unload:\(modelID)")
        return .ok
    }

    func shutdown() -> EmotionSDKStatus {
        events.append("shutdown")
        return .ok
    }
}
