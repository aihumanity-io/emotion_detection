//
// mobilenetv1_fer2024_11_06_08_48_50.swift
//
// This file was automatically generated and should not be edited.
//

import CoreML


/// Model Prediction Input Type
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
class mobilenetv1_fer2024_11_06_08_48_50Input : MLFeatureProvider {

    /// input_1 as color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high
    var input_1: CVPixelBuffer

    var featureNames: Set<String> { ["input_1"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "input_1" {
            return MLFeatureValue(pixelBuffer: input_1)
        }
        return nil
    }

    init(input_1: CVPixelBuffer) {
        self.input_1 = input_1
    }

    convenience init(input_1With input_1: CGImage) throws {
        self.init(input_1: try MLFeatureValue(cgImage: input_1, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!)
    }

    convenience init(input_1At input_1: URL) throws {
        self.init(input_1: try MLFeatureValue(imageAt: input_1, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!)
    }

    func setInput_1(with input_1: CGImage) throws  {
        self.input_1 = try MLFeatureValue(cgImage: input_1, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setInput_1(with input_1: URL) throws  {
        self.input_1 = try MLFeatureValue(imageAt: input_1, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

}


/// Model Prediction Output Type
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
class mobilenetv1_fer2024_11_06_08_48_50Output : MLFeatureProvider {

    /// Source provided by CoreML
    private let provider : MLFeatureProvider

    /// Identity as multidimensional array of floats
    var Identity: MLMultiArray {
        provider.featureValue(for: "Identity")!.multiArrayValue!
    }

    /// Identity as multidimensional array of floats
    var IdentityShapedArray: MLShapedArray<Float> {
        MLShapedArray<Float>(Identity)
    }

    var featureNames: Set<String> {
        provider.featureNames
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        provider.featureValue(for: featureName)
    }

    init(Identity: MLMultiArray) {
        self.provider = try! MLDictionaryFeatureProvider(dictionary: ["Identity" : MLFeatureValue(multiArray: Identity)])
    }

    init(features: MLFeatureProvider) {
        self.provider = features
    }
}


/// Class for model loading and prediction
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
class mobilenetv1_fer2024_11_06_08_48_50 {
    let model: MLModel

    /// URL of model assuming it was installed in the same bundle as this class
    class var urlOfModelInThisBundle : URL {
        let bundle = Bundle(for: self)
        return bundle.url(forResource: "mobilenetv1_fer2024-11-06-08-48-50", withExtension:"mlmodelc")!
    }

    /**
        Construct mobilenetv1_fer2024_11_06_08_48_50 instance with an existing MLModel object.

        Usually the application does not use this initializer unless it makes a subclass of mobilenetv1_fer2024_11_06_08_48_50.
        Such application may want to use `MLModel(contentsOfURL:configuration:)` and `mobilenetv1_fer2024_11_06_08_48_50.urlOfModelInThisBundle` to create a MLModel object to pass-in.

        - parameters:
          - model: MLModel object
    */
    init(model: MLModel) {
        self.model = model
    }

    /**
        Construct a model with configuration

        - parameters:
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    convenience init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        try self.init(contentsOf: type(of:self).urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct mobilenetv1_fer2024_11_06_08_48_50 instance with explicit path to mlmodelc file
        - parameters:
           - modelURL: the file url of the model

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL) throws {
        try self.init(model: MLModel(contentsOf: modelURL))
    }

    /**
        Construct a model with URL of the .mlmodelc directory and configuration

        - parameters:
           - modelURL: the file url of the model
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL, configuration: MLModelConfiguration) throws {
        try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
    }

    /**
        Construct mobilenetv1_fer2024_11_06_08_48_50 instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<mobilenetv1_fer2024_11_06_08_48_50, Error>) -> Void) {
        load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration, completionHandler: handler)
    }

    /**
        Construct mobilenetv1_fer2024_11_06_08_48_50 instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> mobilenetv1_fer2024_11_06_08_48_50 {
        try await load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct mobilenetv1_fer2024_11_06_08_48_50 instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<mobilenetv1_fer2024_11_06_08_48_50, Error>) -> Void) {
        MLModel.load(contentsOf: modelURL, configuration: configuration) { result in
            switch result {
            case .failure(let error):
                handler(.failure(error))
            case .success(let model):
                handler(.success(mobilenetv1_fer2024_11_06_08_48_50(model: model)))
            }
        }
    }

    /**
        Construct mobilenetv1_fer2024_11_06_08_48_50 instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> mobilenetv1_fer2024_11_06_08_48_50 {
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        return mobilenetv1_fer2024_11_06_08_48_50(model: model)
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as mobilenetv1_fer2024_11_06_08_48_50Input

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as mobilenetv1_fer2024_11_06_08_48_50Output
    */
    func prediction(input: mobilenetv1_fer2024_11_06_08_48_50Input) throws -> mobilenetv1_fer2024_11_06_08_48_50Output {
        try prediction(input: input, options: MLPredictionOptions())
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as mobilenetv1_fer2024_11_06_08_48_50Input
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as mobilenetv1_fer2024_11_06_08_48_50Output
    */
    func prediction(input: mobilenetv1_fer2024_11_06_08_48_50Input, options: MLPredictionOptions) throws -> mobilenetv1_fer2024_11_06_08_48_50Output {
        let outFeatures = try model.prediction(from: input, options: options)
        return mobilenetv1_fer2024_11_06_08_48_50Output(features: outFeatures)
    }

    /**
        Make an asynchronous prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as mobilenetv1_fer2024_11_06_08_48_50Input
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as mobilenetv1_fer2024_11_06_08_48_50Output
    */
    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
    func prediction(input: mobilenetv1_fer2024_11_06_08_48_50Input, options: MLPredictionOptions = MLPredictionOptions()) async throws -> mobilenetv1_fer2024_11_06_08_48_50Output {
        let outFeatures = try await model.prediction(from: input, options: options)
        return mobilenetv1_fer2024_11_06_08_48_50Output(features: outFeatures)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - input_1: color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as mobilenetv1_fer2024_11_06_08_48_50Output
    */
    func prediction(input_1: CVPixelBuffer) throws -> mobilenetv1_fer2024_11_06_08_48_50Output {
        let input_ = mobilenetv1_fer2024_11_06_08_48_50Input(input_1: input_1)
        return try prediction(input: input_)
    }

    /**
        Make a batch prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - inputs: the inputs to the prediction as [mobilenetv1_fer2024_11_06_08_48_50Input]
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as [mobilenetv1_fer2024_11_06_08_48_50Output]
    */
    func predictions(inputs: [mobilenetv1_fer2024_11_06_08_48_50Input], options: MLPredictionOptions = MLPredictionOptions()) throws -> [mobilenetv1_fer2024_11_06_08_48_50Output] {
        let batchIn = MLArrayBatchProvider(array: inputs)
        let batchOut = try model.predictions(from: batchIn, options: options)
        var results : [mobilenetv1_fer2024_11_06_08_48_50Output] = []
        results.reserveCapacity(inputs.count)
        for i in 0..<batchOut.count {
            let outProvider = batchOut.features(at: i)
            let result =  mobilenetv1_fer2024_11_06_08_48_50Output(features: outProvider)
            results.append(result)
        }
        return results
    }
}
