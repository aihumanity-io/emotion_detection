//
//  EmotionMobilenetv1.swift
//  Runner
//
//  Created by david Chiu on 11/9/24.
//
//
//  Copyright © 2024 Creata AI. All rights reserved.
// Implementation of Face Expression Prediction  model
//

import Foundation


import Foundation
import CoreGraphics
import Accelerate
import AVFoundation
import CoreImage
import Darwin
import UIKit
import CoreML

import CryptoKit
import os

@available(iOS 15.0, *)
private func frameworkBundle() -> Bundle {
    // This resolves to emotion_detection.framework’s bundle at runtime
    return Bundle(for: EmotionMobilenet.self)
}
@available(iOS 15.0, *)
class EmotionMobilenet: MLBase {
    
    let threadCount: Int32 = 1
    
    // MARK: - Model Parameters

    var coreMLModel: mobilenetv1_fer2024_11_06_08_48_50?  //fer_cnn214?
    //let emotionList: [String] = ["anger", "disgust", "fear", "happiness", "sadness", "surprise", "neutral"]
    let emotionList: [String] = ["Anger", "Disgust", "Fear", "Happiness", "Neutral", "Sadness", "Surprise"]
    var emotionBuffer = [Int]()
    let nAverage = 3
            
    private let userName: String

    init(userName: String) throws {
        self.userName = userName
                
        do
        {
            try super.init()
            //modelConfig = MLModelConfiguration()
            modelConfig.computeUnits = .cpuAndGPU
            let fw = frameworkBundle()
            print("Using bundle: \(fw.bundlePath)")
            
            let currentUserName = UserCodeUtils.sanitize(userName: userName)
            let baseCandidates = ["mobilenetv1_fer2024-11-06-08-48-50", "mobilenetv1_fer"]
            var lastCandidateError: Error?

            for baseName in baseCandidates {
                do {
                    let manifestURL = try FileIO.bundleURL(name: baseName, ext: "manifest.json", in: fw)
                    let manifestData = try Data(contentsOf: manifestURL)
                    let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
                    let modelId = manifest.model_id ?? manifest.modelId ?? manifest.model_name
                    print("Manifest \(baseName): id=\(manifest.model_id ?? manifest.modelId ?? "nil") name=\(manifest.model_name ?? "nil") shard_required=\(manifest.shard_required ?? false)")

                    let cekData = try obtainCEK_UserCodeGateSync(
                        manifest: manifest,
                        userName: currentUserName,
                        modelId: modelId,
                        user32Provider: { try UserCodeUtils.loadUser32(userName: currentUserName, modelId: modelId) }
                    )

                    let model = try EncryptedModelLoader.loadFromBundle(
                        baseName: baseName,
                        configuration: modelConfig,
                        framework: fw
                    ) { SymmetricKey(data: cekData) }

                    let typed = mobilenetv1_fer2024_11_06_08_48_50(model: model)
                    coreMLModel = typed
                    print("model \(baseName) loaded")
                    lastCandidateError = nil
                    break
                } catch {
                    lastCandidateError = error
                    print("Mobilenet candidate \(baseName) failed: \(error.localizedDescription)")
                }
            }

            if coreMLModel == nil {
                throw lastCandidateError ?? MLError.Error("No compatible mobilenet artifact found.")
            }
        }
        catch {
            let ns = error as NSError
            let log = Logger(subsystem: "com.creataai.emotionsdk", category: "model")
            log.logUnknown(ns, context: "mobilenetv1_fer2024 model loading")
            throw MLError.Error("mobilenet load failed (\(ns.domain)#\(ns.code)): \(ns.localizedDescription)")
        }
 
       
    }

    func runModel(faceImage: CGImage) throws ->
    [String:Float] {

        //let grayPixelBuffer = faceImage.pixelBufferGray(width: 48, height: 48, orientation: .up)
        
        let pixelBuffer = faceImage.pixelBuffer(width: 224, height: 224, orientation: .up)
        /// for imon's itracker implementation
        let prediction =  try coreMLModel!.prediction(input_1:pixelBuffer!)

            //let array = prediction.Identity
            //let array = prediction.var_995
        let marray = prediction.Identity
        guard let array = MLBase.toArray(multiArray: marray) else {
            return [:] //"None"
        }
        guard let max = array.firstIndexOfMaxElement() else {
            return [:] //"None"
        }
        var emotions: [String: Float] = [:]
        for i in 0..<7 {
            emotions[emotionList[i]] = array[i]
            
        }
        //print("\(max)")
        //print("\(array[0]), \(array[1])")
        
       /* if max >= 0 && max < emotionList.count {
            return emotionList[applyAverage(index: max)]
        }*/

        //print("emotion: \(array)")
        return emotions
    }
    
    func applyAverage(index: Int) -> Int {
        if emotionBuffer.count >= nAverage {
            emotionBuffer.removeFirst()
        }
        emotionBuffer.append(index)
        print(emotionBuffer)
        let hist = emotionBuffer.histogram
        print(hist)
        var max = 0, mvalue = 0
        for var ele in hist {
            if ele.value > mvalue{
                max = ele.key
                mvalue = ele.value
            }
        }
        print(max)
        return max
    }

}
