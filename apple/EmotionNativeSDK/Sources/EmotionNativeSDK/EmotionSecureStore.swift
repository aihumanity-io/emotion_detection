import Foundation
import Security

public protocol EmotionSecureStore {
    func set(namespace: String, key: String, value: Data) -> EmotionSDKStatus
    func get(namespace: String, key: String) -> Result<Data, EmotionSDKStatus>
    func delete(namespace: String, key: String) -> EmotionSDKStatus
}

protocol KeychainClient {
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?)
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychainClient: KeychainClient {
    func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

public final class KeychainSecureStore: EmotionSecureStore {
    private let servicePrefix: String
    private let client: KeychainClient

    public convenience init(servicePrefix: String = "com.tartalabs.emotion.native") {
        self.init(servicePrefix: servicePrefix, client: SystemKeychainClient())
    }

    init(servicePrefix: String, client: KeychainClient) {
        self.servicePrefix = servicePrefix
        self.client = client
    }

    public func set(namespace: String, key: String, value: Data) -> EmotionSDKStatus {
        guard valid(namespace: namespace, key: key), !value.isEmpty else {
            return .invalidArgument
        }

        let query = baseQuery(namespace: namespace, key: key)
        var addQuery = query
        addQuery[kSecValueData as String] = value

        let addStatus = client.add(addQuery)
        if addStatus == errSecSuccess {
            return .ok
        }
        if addStatus == errSecDuplicateItem {
            let updateStatus = client.update(query, attributes: [kSecValueData as String: value])
            return status(for: updateStatus, missingAs: .modelNotFound)
        }
        return status(for: addStatus, missingAs: .modelNotFound)
    }

    public func get(namespace: String, key: String) -> Result<Data, EmotionSDKStatus> {
        guard valid(namespace: namespace, key: key) else {
            return .failure(.invalidArgument)
        }

        var query = baseQuery(namespace: namespace, key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (copyStatus, data) = client.copyMatching(query)
        if copyStatus == errSecSuccess, let data {
            return .success(data)
        }
        return .failure(status(for: copyStatus, missingAs: .modelNotFound))
    }

    public func delete(namespace: String, key: String) -> EmotionSDKStatus {
        guard valid(namespace: namespace, key: key) else {
            return .invalidArgument
        }

        let deleteStatus = client.delete(baseQuery(namespace: namespace, key: key))
        if deleteStatus == errSecItemNotFound {
            return .ok
        }
        return status(for: deleteStatus, missingAs: .ok)
    }

    private func valid(namespace: String, key: String) -> Bool {
        !namespace.isEmpty && !key.isEmpty
    }

    private func baseQuery(namespace: String, key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(servicePrefix).\(namespace)",
            kSecAttrAccount as String: key
        ]
    }

    private func status(for osStatus: OSStatus, missingAs missingStatus: EmotionSDKStatus) -> EmotionSDKStatus {
        switch osStatus {
        case errSecSuccess:
            return .ok
        case errSecItemNotFound:
            return missingStatus
        case errSecParam:
            return .invalidArgument
        default:
            return .internalError
        }
    }
}
