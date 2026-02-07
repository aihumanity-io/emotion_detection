import Foundation
import CoreML
import CryptoKit

enum EncryptedLoadError: Error { case integrityFailed, manifestMissing }


struct EncryptedModelLoader {
    
    // New: return compiled URL so caller can use the typed wrapper’s initializer
       static func compiledURLFromBundle(baseName: String,
                                         obtainKey: () throws -> SymmetricKey) throws -> URL {
           // …verify manifest → decrypt to zip → unzip to temp…
           let workDir = try FileIO.tempDir("baseline")
           let pkg = try FileIO.findMLPackage(in: workDir)
           return try MLModel.compileModel(at: pkg) // caller owns lifetime
       }


    /// Loads <Base>.enc + <Base>.manifest.json from bundle, verifies, decrypts, unzips, compiles, returns MLModel.
    static func loadFromBundle(baseName: String,
                               configuration: MLModelConfiguration,
                               framework: Bundle,
    obtainKey: () throws -> SymmetricKey) throws -> MLModel {

        // 1) Read manifest + enc bytes
        let manifestURL = try FileIO.bundleURL(name: baseName, ext: "manifest.json", in: framework)
        let encURL      = try FileIO.bundleURL(name: baseName, ext: "enc", in: framework)
        print("loadFromBundle: \(manifestURL.path) \(encURL.path)")

        let manifest = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: manifestURL))
        let encData  = try Data(contentsOf: encURL)
        print("\(manifest)")

        // (Optional) quick enc file integrity check
        let encHash = ModelCrypto.sha256Hex(encData)
        if let encHex = manifest.enc_sha256 {
            guard encHash == encHex else { throw EncryptedLoadError.integrityFailed }
        }

        // 2) Obtain CEK, decrypt to zip bytes with same AAD used at build time
        let key = try obtainKey()
        let aad = Data(manifest.aad.utf8)
        
        // New manifest style: separate IV + (ciphertext||tag)
        if let ivB64u = manifest.gcmIv, !ivB64u.isEmpty, let ctLen = manifest.ciphertextLen {
            func b64urlDecode(_ s: String) -> Data? {
                let std = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                let pad = (4 - std.count % 4) % 4
                return Data(base64Encoded: std + String(repeating: "=", count: pad))
            }
            guard let iv = b64urlDecode(ivB64u) else { throw EncryptedLoadError.manifestMissing }
            let zipData = try ModelCrypto.decrypt(iv: iv, combinedCtTag: encData, key: key, aad: aad)
            // Replace enc_sha256/zip_sha256 checks with plainSha256 if present
            if let plain = manifest.plainSha256, let plainHashData = Data(base64Encoded: plain.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - plain.count % 4) % 4)) {
                // optional: we will verify later after unzip; keep old flow for compatibility
            }
            // Continue with unzip using zipData
            // (code below remains the same)
        }
        // Compute zipData compatible with both manifest styles
        func b64urlDecode(_ s: String) -> Data? {
            let std = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            let pad = (4 - std.count % 4) % 4
            return Data(base64Encoded: std + String(repeating: "=", count: pad))
        }
        let zipData: Data
        if let ivB64u = manifest.gcmIv, !ivB64u.isEmpty, let iv = b64urlDecode(ivB64u) {
            zipData = try ModelCrypto.decrypt(iv: iv, combinedCtTag: encData, key: key, aad: aad)
        } else {
            zipData = try ModelCrypto.decrypt(combined: encData, key: key, aad: aad)
        }


        // 3) Verify zip hash matches manifest
        let zipHash = ModelCrypto.sha256Hex(zipData)
        if let zipHex = manifest.zip_sha256 {
            guard zipHash == zipHex else { throw EncryptedLoadError.integrityFailed }
        } else if let plainB64u = manifest.plainSha256 {
            func b64u(_ d: Data) -> String { return d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
            let calc = b64u(Data(SHA256.hash(data: zipData)))
            guard calc == plainB64u else { throw EncryptedLoadError.integrityFailed }
        }

        // 4) Unzip → find .mlpackage → compile & load
        let work = try FileIO.tempDir("model_dec\(baseName)")
        print("work dir: \(work.path)")
        let zipOut = work.appendingPathComponent("model\(baseName).zip")
        try zipData.write(to: zipOut, options: .atomic)
        if #available(iOS 13.4, *) {
            try FileIO.unzip(zipOut, to: work)
        } else {
            // Fallback on earlier versions
        }
        print("finished unzip to: \(work.path)")
        let pkg = try FileIO.findMLPackage(in: work)
        let compiled = try MLModel.compileModel(at: pkg)
        let model = try MLModel(contentsOf: compiled, configuration: configuration)

        // 5) Cleanup (optional)
        // try? FileManager.default.removeItem(at: work)
        return model
    }
}
import os
import OSLog

@available(iOS 14.0, *)
extension Logger {
    func logUnknown(_ error: Error, context: String = "Operation failed") {
        let ns = error as NSError
        let typeName = String(reflecting: type(of: error))
        let userInfo = (ns.userInfo as NSDictionary).description
        self.error("\(context, privacy: .public) type=\(typeName, privacy: .public) domain=\(ns.domain, privacy: .public) code=\(ns.code) desc=\(ns.localizedDescription, privacy: .public) userInfo=\(userInfo, privacy: .public)")
    }
}
