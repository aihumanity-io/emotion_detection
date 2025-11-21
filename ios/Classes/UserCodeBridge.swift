import Foundation

enum UserCodeBridgeError: LocalizedError {
    case emptyAccount
    case invalidBase64
    case invalidLength

    var errorDescription: String? {
        switch self {
        case .emptyAccount:
            return "userName must not be empty"
        case .invalidBase64:
            return "userCodeB64 must be valid base64"
        case .invalidLength:
            return "user code must decode to exactly 32 bytes"
        }
    }
}

enum UserCodeBridge {
    static func saveUserCode(b64: String, userName: String, requireBiometrics: Bool) throws {
        let account = sanitize(userName: userName)
        guard !account.isEmpty else { throw UserCodeBridgeError.emptyAccount }
        let trimmed = b64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: trimmed) else {
            throw UserCodeBridgeError.invalidBase64
        }
        guard decoded.count == 32 else { throw UserCodeBridgeError.invalidLength }
        try User32Store.save(decoded, account: account, requireBiometrics: requireBiometrics)
    }

    static func clearUserCode(userName: String) throws {
        let account = sanitize(userName: userName)
        guard !account.isEmpty else { throw UserCodeBridgeError.emptyAccount }
        try User32Store.delete(account: account)
    }

    private static func sanitize(userName: String) -> String {
        return userName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
