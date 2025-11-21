import Foundation

struct ModelManifest: Decodable {
    let model_name: String
    let version: String
    let zip_sha256: String
    let enc_sha256: String
    let aad: String
    let algorithm: String
    let combined_format: String
    let nonce_len: Int
    let tag_len: Int
    let created_at: String
}
