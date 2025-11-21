//
// aih_fer20250110.swift
//
// This file was automatically generated and should not be edited.
//

import CoreML


/// Model Prediction Input Type
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
class aih_fer20250110Input : MLFeatureProvider {

    /// input_leye as color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high
    var input_leye: CVPixelBuffer

    /// input_reye as color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high
    var input_reye: CVPixelBuffer

    /// input_face as color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high
    var input_face: CVPixelBuffer

    /// input_mouth as color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high
    var input_mouth: CVPixelBuffer

    var featureNames: Set<String> { ["input_leye", "input_reye", "input_face", "input_mouth"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "input_leye" {
            return MLFeatureValue(pixelBuffer: input_leye)
        }
        if featureName == "input_reye" {
            return MLFeatureValue(pixelBuffer: input_reye)
        }
        if featureName == "input_face" {
            return MLFeatureValue(pixelBuffer: input_face)
        }
        if featureName == "input_mouth" {
            return MLFeatureValue(pixelBuffer: input_mouth)
        }
        return nil
    }

    init(input_leye: CVPixelBuffer, input_reye: CVPixelBuffer, input_face: CVPixelBuffer, input_mouth: CVPixelBuffer) {
        self.input_leye = input_leye
        self.input_reye = input_reye
        self.input_face = input_face
        self.input_mouth = input_mouth
    }

    convenience init(input_leyeWith input_leye: CGImage, input_reyeWith input_reye: CGImage, input_faceWith input_face: CGImage, input_mouthWith input_mouth: CGImage) throws {
        self.init(input_leye: try MLFeatureValue(cgImage: input_leye, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!, input_reye: try MLFeatureValue(cgImage: input_reye, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!, input_face: try MLFeatureValue(cgImage: input_face, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!, input_mouth: try MLFeatureValue(cgImage: input_mouth, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!)
    }

    convenience init(input_leyeAt input_leye: URL, input_reyeAt input_reye: URL, input_faceAt input_face: URL, input_mouthAt input_mouth: URL) throws {
        self.init(input_leye: try MLFeatureValue(imageAt: input_leye, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!, input_reye: try MLFeatureValue(imageAt: input_reye, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!, input_face: try MLFeatureValue(imageAt: input_face, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!, input_mouth: try MLFeatureValue(imageAt: input_mouth, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!)
    }

    func setInput_leye(with input_leye: CGImage) throws  {
        self.input_leye = try MLFeatureValue(cgImage: input_leye, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setInput_reye(with input_reye: CGImage) throws  {
        self.input_reye = try MLFeatureValue(cgImage: input_reye, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setInput_face(with input_face: CGImage) throws  {
        self.input_face = try MLFeatureValue(cgImage: input_face, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setInput_mouth(with input_mouth: CGImage) throws  {
        self.input_mouth = try MLFeatureValue(cgImage: input_mouth, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setInput_leye(with input_leye: URL) throws  {
        self.input_leye = try MLFeatureValue(imageAt: input_leye, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setInput_reye(with input_reye: URL) throws  {
        self.input_reye = try MLFeatureValue(imageAt: input_reye, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setInput_face(with input_face: URL) throws  {
        self.input_face = try MLFeatureValue(imageAt: input_face, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setInput_mouth(with input_mouth: URL) throws  {
        self.input_mouth = try MLFeatureValue(imageAt: input_mouth, pixelsWide: 224, pixelsHigh: 224, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

}


/// Model Prediction Output Type
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)
class aih_fer20250110Output : MLFeatureProvider {

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
class aih_fer20250110 {
    let model: MLModel

    /// URL of model assuming it was installed in the same bundle as this class
    class var urlOfModelInThisBundle : URL {
        let bundle = Bundle(for: self)
        return bundle.url(forResource: "aih_fer20250110", withExtension:"mlmodelc")!
    }

    /**
        Construct aih_fer20250110 instance with an existing MLModel object.

        Usually the application does not use this initializer unless it makes a subclass of aih_fer20250110.
        Such application may want to use `MLModel(contentsOfURL:configuration:)` and `aih_fer20250110.urlOfModelInThisBundle` to create a MLModel object to pass-in.

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
        Construct aih_fer20250110 instance with explicit path to mlmodelc file
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
        Construct aih_fer20250110 instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<aih_fer20250110, Error>) -> Void) {
        load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration, completionHandler: handler)
    }

    /**
        Construct aih_fer20250110 instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> aih_fer20250110 {
        try await load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct aih_fer20250110 instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<aih_fer20250110, Error>) -> Void) {
        MLModel.load(contentsOf: modelURL, configuration: configuration) { result in
            switch result {
            case .failure(let error):
                handler(.failure(error))
            case .success(let model):
                handler(.success(aih_fer20250110(model: model)))
            }
        }
    }

    /**
        Construct aih_fer20250110 instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> aih_fer20250110 {
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        return aih_fer20250110(model: model)
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as aih_fer20250110Input

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as aih_fer20250110Output
    */
    func prediction(input: aih_fer20250110Input) throws -> aih_fer20250110Output {
        try prediction(input: input, options: MLPredictionOptions())
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as aih_fer20250110Input
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as aih_fer20250110Output
    */
    func prediction(input: aih_fer20250110Input, options: MLPredictionOptions) throws -> aih_fer20250110Output {
        let outFeatures = try model.prediction(from: input, options: options)
        return aih_fer20250110Output(features: outFeatures)
    }

    /**
        Make an asynchronous prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as aih_fer20250110Input
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as aih_fer20250110Output
    */
    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
    func prediction(input: aih_fer20250110Input, options: MLPredictionOptions = MLPredictionOptions()) async throws -> aih_fer20250110Output {
        let outFeatures = try await model.prediction(from: input, options: options)
        return aih_fer20250110Output(features: outFeatures)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - input_leye: color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high
            - input_reye: color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high
            - input_face: color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high
            - input_mouth: color (kCVPixelFormatType_32BGRA) image buffer, 224 pixels wide by 224 pixels high

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as aih_fer20250110Output
    */
    func prediction(input_leye: CVPixelBuffer, input_reye: CVPixelBuffer, input_face: CVPixelBuffer, input_mouth: CVPixelBuffer) throws -> aih_fer20250110Output {
        let input_ = aih_fer20250110Input(input_leye: input_leye, input_reye: input_reye, input_face: input_face, input_mouth: input_mouth)
        return try prediction(input: input_)
    }

    /**
        Make a batch prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - inputs: the inputs to the prediction as [aih_fer20250110Input]
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as [aih_fer20250110Output]
    */
    func predictions(inputs: [aih_fer20250110Input], options: MLPredictionOptions = MLPredictionOptions()) throws -> [aih_fer20250110Output] {
        let batchIn = MLArrayBatchProvider(array: inputs)
        let batchOut = try model.predictions(from: batchIn, options: options)
        var results : [aih_fer20250110Output] = []
        results.reserveCapacity(inputs.count)
        for i in 0..<batchOut.count {
            let outProvider = batchOut.features(at: i)
            let result =  aih_fer20250110Output(features: outProvider)
            results.append(result)
        }
        return results
    }
}
