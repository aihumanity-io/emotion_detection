import XCTest
@testable import EmotionNativeSDK

final class FlutterBridgePayloadTests: XCTestCase {
    func testRegisterModelPayloadUsesFlutterDefaults() throws {
        let payload = try EmotionRegisterModelPayload(arguments: [
            "modelId": "aih_fer2025",
            "resourceBase": "face_v1"
        ])

        XCTAssertEqual(payload.modelID, "aih_fer2025")
        XCTAssertEqual(payload.resourceBase, "face_v1")
        XCTAssertEqual(payload.encryptedExtension, "onnx.enc")
        XCTAssertEqual(payload.hkdfInfo, "model_runtime")
        XCTAssertNil(payload.masterKeyBase64)
    }

    func testRegisterModelPayloadReadsOptionalFields() throws {
        let payload = try EmotionRegisterModelPayload(arguments: [
            "modelId": "aih_fer2025",
            "resourceBase": "face_v1",
            "encExt": "bin.enc",
            "hkdfInfo": "custom",
            "masterKeyB64": "abc"
        ])

        XCTAssertEqual(payload.encryptedExtension, "bin.enc")
        XCTAssertEqual(payload.hkdfInfo, "custom")
        XCTAssertEqual(payload.masterKeyBase64, "abc")
    }

    func testPredictPayloadRequiresInputsMap() throws {
        let payload = try EmotionPredictPayload(arguments: [
            "modelId": "aih_fer2025",
            "inputs": ["width": 1, "height": 1]
        ])

        XCTAssertEqual(payload.modelID, "aih_fer2025")
        XCTAssertEqual(payload.inputs["width"] as? Int, 1)
        XCTAssertThrowsError(try EmotionPredictPayload(arguments: ["modelId": "aih_fer2025"])) { error in
            XCTAssertEqual(error as? EmotionFlutterBridgeError, .missingMap("inputs"))
        }
    }

    func testUserCodePayloadValidatesRequiredFields() throws {
        let payload = try EmotionUserCodePayload(arguments: [
            "userName": "david",
            "userCodeB64": "abc",
            "requireBiometrics": true,
            "modelId": "aih_fer2025"
        ])

        XCTAssertEqual(payload.userName, "david")
        XCTAssertEqual(payload.userCodeBase64, "abc")
        XCTAssertEqual(payload.modelID, "aih_fer2025")
        XCTAssertTrue(payload.requireBiometrics)
        XCTAssertThrowsError(try EmotionUserCodePayload(arguments: ["userName": "david"])) { error in
            XCTAssertEqual(error as? EmotionFlutterBridgeError, .missingString("userCodeB64"))
        }
    }
}
