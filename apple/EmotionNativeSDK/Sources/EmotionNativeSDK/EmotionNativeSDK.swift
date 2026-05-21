import Foundation

public enum EmotionSDKStatus: Int, Error, Equatable {
    case ok = 0
    case invalidArgument = 1
    case notInitialized = 2
    case modelNotFound = 3
    case manifestInvalid = 4
    case cryptoFailed = 5
    case licenseInvalid = 6
    case runtimeFailed = 7
    case bufferTooSmall = 8
    case unsupported = 9
    case internalError = 10
}

public struct EmotionSDKConfiguration: Equatable {
    public var cacheDirectory: String?
    public var enableDebugLogging: Bool

    public init(cacheDirectory: String? = nil, enableDebugLogging: Bool = false) {
        self.cacheDirectory = cacheDirectory
        self.enableDebugLogging = enableDebugLogging
    }
}

public struct EmotionModelConfiguration: Equatable {
    public var modelID: String
    public var manifestPath: String
    public var encryptedModelPath: String

    public init(modelID: String, manifestPath: String, encryptedModelPath: String) {
        self.modelID = modelID
        self.manifestPath = manifestPath
        self.encryptedModelPath = encryptedModelPath
    }
}

public struct EmotionImage: Equatable {
    public var width: Int
    public var height: Int
    public var rgbData: Data

    public init(width: Int, height: Int, rgbData: Data) throws {
        guard width > 0, height > 0, rgbData.count == width * height * 3 else {
            throw EmotionSDKStatus.invalidArgument
        }
        self.width = width
        self.height = height
        self.rgbData = rgbData
    }
}

public struct EmotionClassScore: Equatable {
    public var labelIndex: UInt32
    public var probability: Float

    public init(labelIndex: UInt32, probability: Float) {
        self.labelIndex = labelIndex
        self.probability = probability
    }
}

public struct EmotionPrediction: Equatable {
    public var topLabelIndex: UInt32
    public var topProbability: Float
    public var scores: [EmotionClassScore]

    public init(topLabelIndex: UInt32, topProbability: Float, scores: [EmotionClassScore]) {
        self.topLabelIndex = topLabelIndex
        self.topProbability = topProbability
        self.scores = scores
    }
}

public protocol EmotionNativeCoreClient {
    func initialize(configuration: EmotionSDKConfiguration) -> EmotionSDKStatus
    func registerModel(configuration: EmotionModelConfiguration) -> EmotionSDKStatus
    func warmUp(modelID: String) -> EmotionSDKStatus
    func predict(modelID: String, image: EmotionImage) -> Result<EmotionPrediction, EmotionSDKStatus>
    func unload(modelID: String) -> EmotionSDKStatus
    func shutdown() -> EmotionSDKStatus
}

public final class EmotionNativeSDK {
    private let core: EmotionNativeCoreClient
    private var isInitialized = false
    private var registeredModelIDs: Set<String> = []

    public init(core: EmotionNativeCoreClient) {
        self.core = core
    }

    public func initialize(configuration: EmotionSDKConfiguration = EmotionSDKConfiguration()) throws {
        try throwIfNeeded(core.initialize(configuration: configuration))
        isInitialized = true
    }

    public func registerModel(configuration: EmotionModelConfiguration) throws {
        guard isInitialized else { throw EmotionSDKStatus.notInitialized }
        guard !configuration.modelID.isEmpty,
              !configuration.manifestPath.isEmpty,
              !configuration.encryptedModelPath.isEmpty else {
            throw EmotionSDKStatus.invalidArgument
        }
        try throwIfNeeded(core.registerModel(configuration: configuration))
        registeredModelIDs.insert(configuration.modelID)
    }

    public func warmUp(modelID: String) throws {
        try requireRegistered(modelID: modelID)
        try throwIfNeeded(core.warmUp(modelID: modelID))
    }

    public func predict(modelID: String, image: EmotionImage) throws -> EmotionPrediction {
        try requireRegistered(modelID: modelID)
        switch core.predict(modelID: modelID, image: image) {
        case .success(let prediction):
            return prediction
        case .failure(let status):
            throw status
        }
    }

    public func unload(modelID: String) throws {
        try requireRegistered(modelID: modelID)
        try throwIfNeeded(core.unload(modelID: modelID))
        registeredModelIDs.remove(modelID)
    }

    public func shutdown() throws {
        try throwIfNeeded(core.shutdown())
        isInitialized = false
        registeredModelIDs.removeAll()
    }

    private func requireRegistered(modelID: String) throws {
        guard isInitialized else { throw EmotionSDKStatus.notInitialized }
        guard registeredModelIDs.contains(modelID) else { throw EmotionSDKStatus.modelNotFound }
    }

    private func throwIfNeeded(_ status: EmotionSDKStatus) throws {
        guard status == .ok else { throw status }
    }
}
