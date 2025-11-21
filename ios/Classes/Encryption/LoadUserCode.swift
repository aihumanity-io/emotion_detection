import Foundation
import MobileCoreServices

enum User32SideLoadError: Error {
    case notFound
    case badFormat(String)
}

struct User32SideLoad {
    /// Returns URL to a side-loaded user32 file if found.
    /// Search order: env var → App Group → Documents → Application Support → bundle resources.
    static func sideLoadedURL(
    fileNames: [String] = ["user32.b64", "user_code.b64", "user32.bin", "user_code.bin", "user32.txt", "user_code.txt"],
    bundle: Bundle = .main,
    appGroupID: String? = nil
    ) throws -> URL {
        let fm = FileManager.default

        // 0) Explicit override via env var (handy in DEBUG)
        if let path = ProcessInfo.processInfo.environment["EMO_USER32_PATH"], !path.isEmpty {
            let u = URL(fileURLWithPath: path)
            if fm.fileExists(atPath: u.path) { return u }
        }

        // 1) App Group (if you pass an ID)
        if let group = appGroupID,
        let container = fm.containerURL(forSecurityApplicationGroupIdentifier: group) {
            for name in fileNames {
                let u = container.appendingPathComponent(name, isDirectory: false)
                if fm.fileExists(atPath: u.path) { return u }
            }
        }

        // 2) Documents (via Files app / iTunes File Sharing)
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            for name in fileNames {
                let u = docs.appendingPathComponent(name, isDirectory: false)
                if fm.fileExists(atPath: u.path) { return u }
            }
        }

        // 3) Library/Application Support
        if let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            for name in fileNames {
                let u = appSup.appendingPathComponent(name, isDirectory: false)
                if fm.fileExists(atPath: u.path) { return u }
            }
        }

        // 4) Bundle resources (ship a test file in Copy Bundle Resources)
        for name in fileNames {
            if let u = bundle.url(forResource: name, withExtension: nil) { return u }
            // Try split name/ext variants
            let ns = name as NSString
            let base = ns.deletingPathExtension
            let ext  = ns.pathExtension.isEmpty ? "b64" : ns.pathExtension
            if let u = bundle.url(forResource: base, withExtension: ext) { return u }
        }

        throw User32SideLoadError.notFound
    }

    /// Load and normalize to exactly 32 bytes.
    /// Accepts base64, raw 32-byte file, or 64-hex (ASCII).
    static func loadUser32Data(
    fileNames: [String] = ["user32.b64", "user_code.b64", "user32.bin", "user_code.bin", "user32.txt", "user_code.txt"],
    bundle: Bundle = .main,
    appGroupID: String? = nil
    ) throws -> Data {
        let url = try sideLoadedURL(fileNames: fileNames, bundle: bundle, appGroupID: appGroupID)
        let raw = try Data(contentsOf: url)

        // 1) Try base64 (trim whitespace/newlines)
        if let s = String(data: raw, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        let b64 = Data(base64Encoded: s), b64.count == 32 {
            return b64
        }

        // 2) Try raw 32 bytes
        if raw.count == 32 { return raw }

        // 3) Try 64-hex ASCII
        if let s = String(data: raw, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        let hex = Data(hexString: s), hex.count == 32 {
            return hex
        }

        throw User32SideLoadError.badFormat("Expected base64(32B) or raw 32 bytes or 64-hex")
    }
}

// MARK: - Small hex helper

private extension Data {
    init?(hexString: String) {
        let s = hexString.lowercased().replacingOccurrences(of: "0x", with: "")
        .replacingOccurrences(of: " ", with: "")
        guard s.count % 2 == 0 else { return nil }
        var out = Data(capacity: s.count/2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            let byteStr = s[idx..<next]
            guard let b = UInt8(byteStr, radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        self = out
    }
}
