import Foundation

@available(iOS 15.0, *)
enum UserCodeUtils {
    static func sanitize(userName: String) -> String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func loadUser32(userName: String) throws -> Data {
        let acct = sanitize(userName: userName)
        if let cached = try? User32Store.load(account: acct) {
            return cached
        }
        return try User32SideLoad.loadUser32Data(bundle: .main)
    }
}
