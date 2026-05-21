import Foundation
import XCTest
@testable import EmotionNativeSDK

final class StillImageInferenceTests: XCTestCase {
    func testPPMFixtureCanDriveStillImagePrediction() throws {
        let imageURL = try XCTUnwrap(Bundle.module.url(forResource: "sample_rgb", withExtension: "ppm"))
        let image = try EmotionStillImageLoader.loadPPM(at: imageURL)
        let core = StillImageCore()
        let sdk = EmotionNativeSDK(core: core)
        let model = EmotionModelConfiguration(
            modelID: "aih_fer2025",
            manifestPath: "/models/manifest.json",
            encryptedModelPath: "/models/model.enc"
        )

        try sdk.initialize()
        try sdk.registerModel(configuration: model)
        try sdk.warmUp(modelID: model.modelID)
        let prediction = try sdk.predict(modelID: model.modelID, image: image)

        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
        XCTAssertEqual(image.rgbData, Data([255, 0, 0]))
        XCTAssertEqual(prediction.topLabelIndex, 4)
        XCTAssertEqual(core.predictedImage, image)
    }

    func testPPMRejectsInvalidPixelData() {
        XCTAssertThrowsError(
            try EmotionStillImageLoader.loadPPM(text: "P3\n1 1\n255\n255 0")
        ) { error in
            XCTAssertEqual(error as? EmotionStillImageError, .invalidPixelData)
        }
    }
}

private final class StillImageCore: EmotionNativeCoreClient {
    var predictedImage: EmotionImage?

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
        predictedImage = image
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
