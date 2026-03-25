import Foundation

struct ModelManifest: Decodable {
    let model_name: String?
    let version: String?
    let zip_sha256: String?
    let enc_sha256: String?
    let aad: String
    let algorithm: String?
    let combined_format: String?
    let nonce_len: Int?
    let tag_len: Int?
    let created_at: String?

    // New unified fields (optional)
    let ciphertextLen: Int?
    let gcmIv: String?
    let plainSha256: String?

    private enum CodingKeys: String, CodingKey {
        case model_name
        case version
        case zip_sha256
        case enc_sha256
        case aad
        case algorithm
        case combined_format
        case nonce_len
        case tag_len
        case created_at
        case ciphertextLen
        case gcmIv
        case plainSha256
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model_name = try c.decodeIfPresent(String.self, forKey: .model_name)
        if let v = try? c.decode(String.self, forKey: .version) {
            version = v
        } else if let n = try? c.decode(Int.self, forKey: .version) {
            version = String(n)
        } else {
            version = nil
        }
        zip_sha256 = try c.decodeIfPresent(String.self, forKey: .zip_sha256)
        enc_sha256 = try c.decodeIfPresent(String.self, forKey: .enc_sha256)
        aad = try c.decodeIfPresent(String.self, forKey: .aad) ?? ""
        algorithm = try c.decodeIfPresent(String.self, forKey: .algorithm)
        combined_format = try c.decodeIfPresent(String.self, forKey: .combined_format)
        nonce_len = try c.decodeIfPresent(Int.self, forKey: .nonce_len)
        tag_len = try c.decodeIfPresent(Int.self, forKey: .tag_len)
        created_at = try c.decodeIfPresent(String.self, forKey: .created_at)
        ciphertextLen = try c.decodeIfPresent(Int.self, forKey: .ciphertextLen)
        gcmIv = try c.decodeIfPresent(String.self, forKey: .gcmIv)
        plainSha256 = try c.decodeIfPresent(String.self, forKey: .plainSha256)
    }
}
