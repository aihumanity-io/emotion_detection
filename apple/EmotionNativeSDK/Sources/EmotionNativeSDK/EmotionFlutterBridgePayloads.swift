import Foundation

public enum EmotionFlutterBridgeError: Error, Equatable {
    case invalidArguments
    case missingString(String)
    case missingMap(String)
}

public struct EmotionRegisterModelPayload: Equatable {
    public var modelID: String
    public var resourceBase: String
    public var encryptedExtension: String
    public var hkdfInfo: String
    public var masterKeyBase64: String?

    public init(arguments: Any?) throws {
        guard let arguments = arguments as? [String: Any] else {
            throw EmotionFlutterBridgeError.invalidArguments
        }
        modelID = try Self.requiredString("modelId", in: arguments)
        resourceBase = try Self.requiredString("resourceBase", in: arguments)
        encryptedExtension = arguments["encExt"] as? String ?? "onnx.enc"
        hkdfInfo = arguments["hkdfInfo"] as? String ?? "model_runtime"
        masterKeyBase64 = arguments["masterKeyB64"] as? String
    }

    private static func requiredString(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw EmotionFlutterBridgeError.missingString(key)
        }
        return value
    }
}

public struct EmotionPredictPayload: Equatable {
    public var modelID: String
    public var inputs: [String: Any]

    public init(arguments: Any?) throws {
        guard let arguments = arguments as? [String: Any] else {
            throw EmotionFlutterBridgeError.invalidArguments
        }
        guard let modelID = arguments["modelId"] as? String, !modelID.isEmpty else {
            throw EmotionFlutterBridgeError.missingString("modelId")
        }
        guard let inputs = arguments["inputs"] as? [String: Any] else {
            throw EmotionFlutterBridgeError.missingMap("inputs")
        }
        self.modelID = modelID
        self.inputs = inputs
    }

    public static func == (lhs: EmotionPredictPayload, rhs: EmotionPredictPayload) -> Bool {
        lhs.modelID == rhs.modelID && NSDictionary(dictionary: lhs.inputs).isEqual(to: rhs.inputs)
    }
}

public struct EmotionUserCodePayload: Equatable {
    public var userName: String
    public var userCodeBase64: String
    public var modelID: String?
    public var requireBiometrics: Bool

    public init(arguments: Any?) throws {
        guard let arguments = arguments as? [String: Any] else {
            throw EmotionFlutterBridgeError.invalidArguments
        }
        guard let userName = arguments["userName"] as? String, !userName.isEmpty else {
            throw EmotionFlutterBridgeError.missingString("userName")
        }
        guard let userCodeBase64 = arguments["userCodeB64"] as? String, !userCodeBase64.isEmpty else {
            throw EmotionFlutterBridgeError.missingString("userCodeB64")
        }
        self.userName = userName
        self.userCodeBase64 = userCodeBase64
        self.modelID = arguments["modelId"] as? String
        self.requireBiometrics = arguments["requireBiometrics"] as? Bool ?? false
    }
}
