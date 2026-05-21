import Foundation
import Security
import XCTest
@testable import EmotionNativeSDK

final class KeychainSecureStoreTests: XCTestCase {
    func testSetGetUpdateAndDelete() throws {
        let client = FakeKeychainClient()
        let store = KeychainSecureStore(servicePrefix: "test.emotion", client: client)

        XCTAssertEqual(store.set(namespace: "models", key: "user32", value: Data([1, 2, 3])), .ok)
        XCTAssertEqual(try store.get(namespace: "models", key: "user32").get(), Data([1, 2, 3]))
        XCTAssertEqual(store.set(namespace: "models", key: "user32", value: Data([4, 5])), .ok)
        XCTAssertEqual(try store.get(namespace: "models", key: "user32").get(), Data([4, 5]))
        XCTAssertEqual(store.delete(namespace: "models", key: "user32"), .ok)

        XCTAssertThrowsError(try store.get(namespace: "models", key: "user32").get()) { error in
            XCTAssertEqual(error as? EmotionSDKStatus, .modelNotFound)
        }
    }

    func testNamespacesAreIsolated() throws {
        let client = FakeKeychainClient()
        let store = KeychainSecureStore(servicePrefix: "test.emotion", client: client)

        XCTAssertEqual(store.set(namespace: "a", key: "shared", value: Data([1])), .ok)
        XCTAssertEqual(store.set(namespace: "b", key: "shared", value: Data([2])), .ok)

        XCTAssertEqual(try store.get(namespace: "a", key: "shared").get(), Data([1]))
        XCTAssertEqual(try store.get(namespace: "b", key: "shared").get(), Data([2]))
    }

    func testInvalidInputsFailClosed() {
        let store = KeychainSecureStore(servicePrefix: "test.emotion", client: FakeKeychainClient())

        XCTAssertEqual(store.set(namespace: "", key: "k", value: Data([1])), .invalidArgument)
        XCTAssertEqual(store.set(namespace: "n", key: "", value: Data([1])), .invalidArgument)
        XCTAssertEqual(store.set(namespace: "n", key: "k", value: Data()), .invalidArgument)
        XCTAssertEqual(store.delete(namespace: "", key: "k"), .invalidArgument)

        XCTAssertThrowsError(try store.get(namespace: "", key: "k").get()) { error in
            XCTAssertEqual(error as? EmotionSDKStatus, .invalidArgument)
        }
    }
}

private final class FakeKeychainClient: KeychainClient {
    private var values: [String: Data] = [:]

    func add(_ query: [String: Any]) -> OSStatus {
        guard let id = id(from: query), let value = query[kSecValueData as String] as? Data else {
            return errSecParam
        }
        if values[id] != nil {
            return errSecDuplicateItem
        }
        values[id] = value
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        guard let id = id(from: query), let value = attributes[kSecValueData as String] as? Data else {
            return errSecParam
        }
        guard values[id] != nil else {
            return errSecItemNotFound
        }
        values[id] = value
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        guard let id = id(from: query) else {
            return (errSecParam, nil)
        }
        guard let value = values[id] else {
            return (errSecItemNotFound, nil)
        }
        return (errSecSuccess, value)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        guard let id = id(from: query) else {
            return errSecParam
        }
        values.removeValue(forKey: id)
        return errSecSuccess
    }

    private func id(from query: [String: Any]) -> String? {
        guard let service = query[kSecAttrService as String] as? String,
              let account = query[kSecAttrAccount as String] as? String else {
            return nil
        }
        return "\(service)|\(account)"
    }
}
