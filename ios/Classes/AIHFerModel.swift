//
//  AIHFerModel.swift
//  Runner
//
//  Created by david Chiu on 1/11/25.
//
//
//  Copyright © 2025 Creata AI. All rights reserved.
// Implementation of Face Expression Prediction  model
//

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
    return Bundle(for: AIHFerModel.self)
}


@available(iOS 15.0, *)
class AIHFerModel: MLBase {
    
    let threadCount: Int32 = 1
    
    // MARK: - Model Parameters

    var coreMLModel: aih_fer20250115? //MLModel?  //aih_fer20250115? //aih_fer20250115? //aih_fer20250110?  //fer_cnn214?
    let emotionList: [String] = ["Anger", "Disgust", "Fear", "Happiness", "Neutral", "Sadness", "Surprise"]
    var emotionBuffer = [Int]()
    let nAverage = 3
            
    private let userName: String

    init(userName: String)  throws {
        self.userName = userName
                
        do
        {
            try super.init()

            /*guard let modelURL = Bundle.main.url(forResource: "AIHFerModel", withExtension: "mlpackage") else {
                print("url no found for model")
            }
            
            else {
                result(FlutterError(code: "MODEL_NOT_FOUND", message: "Could not find model", details: nil))
                return
            }*/


            modelConfig.computeUnits = .cpuAndGPU
            let fw = frameworkBundle()
            print("Using bundle: \(fw.bundlePath)")
            
            let acct = "dev@tartalabs.io".lowercased()

            /*
             one time code
            // 1) Delete any old item (even if it was biometrics-protected)
            try? User32Store.delete(account: acct)

            // 2) Save again WITHOUT biometrics
            let user32 = try User32SideLoad.loadUser32Data(bundle: .main /* plugin bundle or .main */)
            try User32Store.save(user32, account: acct, requireBiometrics: false)

            // 3) Sanity: ensure it won’t prompt
            do {
                _ = try User32Store.loadNoUI(account: acct) // should NOT be errSecInteractionNotAllowed
            } catch {
                print("No-UI load failed:", error) // if interactionNotAllowed → you still have a protected item
            }
*/
            
            // One-time reset (dev) – deletes old wrapped CEK + KEK for the old tag
           /*try? SecItemDelete([
              kSecClass as String: kSecClassGenericPassword,
              kSecAttrService as String: "com.creataai.emotionsdk.model.ceks",
              kSecAttrAccount as String: "aih_fer20250115_v2025-01-15"
            ] as CFDictionary)

            let oldTagData = "com.creataai.emotionsdk.DemoModel.kek.v1".data(using: .utf8)!
            try? SecItemDelete([
              kSecClass as String: kSecClassKey,
              kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
              kSecAttrApplicationTag as String: oldTagData
            ] as CFDictionary)*/
                                       
            /// clear the code cache
            /*try! User32Store.delete(account: "dev@tartalabs.io")
            print("user code deleted")
            //throw NSError()*/
            
            do {
                let user32 = try User32SideLoad.loadUser32Data(bundle: .main/* .main or plugin bundle */)
                assert(user32.count == 32)
                print("user32 ok (b64 len=\(user32.base64EncodedString().count))")
            } catch {
                print("Failed to load user32:", error)
            }

            let currentUserName = UserCodeUtils.sanitize(userName: userName)
            let baseCandidates = ["aih_fer", "aih_fer20250115"]
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
                    ) {
                        SymmetricKey(data: cekData)
                    }
                    let typed = aih_fer20250115(model: model)
                    coreMLModel = typed
                    print("model \(baseName) loaded")
                    lastCandidateError = nil
                    break
                } catch {
                    lastCandidateError = error
                    print("AIH candidate \(baseName) failed: \(error.localizedDescription)")
                }
            }

            if coreMLModel == nil {
                throw lastCandidateError ?? MLError.Error("No compatible AIH model artifact found.")
            }
            //coreMLModel = try aih_fer20250115(configuration: modelConfig) // model358(configuration: myModelConfig)
            //coreMLModel = try MLModel(contentsOf: modelURL, configuration: modelConfig)

        }
        catch {
            let ns = error as NSError
            let log = Logger(subsystem: "com.creataai.emotionsdk", category: "model")
            log.logUnknown(ns, context: "aih_fer model loading")
            throw MLError.Error("aih_fer load failed (\(ns.domain)#\(ns.code)): \(ns.localizedDescription)")
        }
    }

    func runModel(faceImage: CGImage, leftEyeImage: CGImage, rightEyeImage: CGImage, mouthImage: CGImage) throws ->
    [String:Float] {
        
        let pixelBufferFace = faceImage.pixelBuffer(width: 224, height: 224, orientation: .up)
        let pixelBufferLEye = leftEyeImage.pixelBuffer(width: 224, height: 224, orientation: .up)
        let pixelBufferREye = rightEyeImage.pixelBuffer(width: 224, height: 224, orientation: .up)
        let pixelBufferMouth = mouthImage.pixelBuffer(width: 224, height: 224, orientation: .up)

        /// for imon's itracker implementation
        let prediction =  try coreMLModel!.prediction(input_leye:pixelBufferLEye!, input_reye:pixelBufferREye!, input_face:pixelBufferFace!,
                                                      input_mouth:pixelBufferMouth!)

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

        //print("emotion: \(emotions)")
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
