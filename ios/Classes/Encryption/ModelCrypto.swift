import Foundation
import CryptoKit

enum CryptoError: Error { case badCiphertext }

struct ModelCrypto {
    static func decrypt(combined: Data, key: SymmetricKey, aad: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }
    static func symmetricKey(fromBase64 b64: String) throws -> SymmetricKey {
        guard let d = Data(base64Encoded: b64), d.count == 32 else {
            throw NSError(domain: "Key", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid base64 key"])
        }
        return SymmetricKey(data: d)
    }
    static func sha256Hex(_ data: Data) -> String {
        let dig = SHA256.hash(data: data)
        return dig.map { String(format: "%02x", $0) }.joined()
    }
}
