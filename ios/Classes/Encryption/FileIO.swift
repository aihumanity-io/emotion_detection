import Foundation
import ZIPFoundation
import CryptoKit

enum FileErr: Error { case missing, unzip, notFound, noMLPackage }

private func frameworkBundle() -> Bundle {
    // This resolves to emotion_detection.framework’s bundle at runtime
    if #available(iOS 15.0, *) {
        return Bundle(for: AIHFerModel.self)
    } else {
        // Fallback on earlier versions
        return Bundle.main
    }
}

struct FileIO {
    static func bundleURL(name: String, ext: String, in bundle: Bundle) throws -> URL {
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }

        let targetName = "\(name).\(ext)"
        if let root = bundle.resourcePath,
           let enumerator = FileManager.default.enumerator(atPath: root) {
            while let rel = enumerator.nextObject() as? String {
                if rel == targetName || rel.hasSuffix("/\(targetName)") {
                    return URL(fileURLWithPath: root).appendingPathComponent(rel)
                }
            }
        }

        print("File: \(name).\(ext) not found in \(bundle.bundlePath)")
        throw FileErr.missing
    }
    
    static func bundleURL(name: String, ext: String) throws -> URL {
        guard let u = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw FileErr.missing
        }
        return u
    }
    static func tempDir(_ name: String = UUID().uuidString) throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func unzip0(_ zipURL: URL, to dest: URL) throws {
        try FileManager.default.unzipItem(at: zipURL, to: dest)
    }
    
    static func unzip1(_ zipURL: URL, to dest: URL) throws {
            let fm = FileManager.default
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)

            guard let archive = Archive(url: zipURL, accessMode: .read) else {
                throw FileErr.unzip
            }
            for entry in archive {
                // Ignore AppleDouble / Finder junk
                if entry.path.hasPrefix("__MACOSX/") { continue }

                let outURL = dest.appendingPathComponent(entry.path)
                do {
                    try fm.createDirectory(at: outURL.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    try archive.extract(entry, to: outURL)
                } catch {
                    print("❌ Extract failed: \(entry.path)  method=\(entry) size=\(entry.uncompressedSize)")
                    throw error
                }
            }
        }
    
    static func findMLPackage(in dir: URL) throws -> URL {
        if let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let u as URL in e where u.pathExtension == "mlpackage" { return u }
        }
        throw FileErr.noMLPackage
    }
    static func sha256Hex(of url: URL) throws -> String {
        let d = try Data(contentsOf: url)
        return ModelCrypto.sha256Hex(d)
    }
    
    
    @available(iOS 13.4, *)
    static func unzip(_ zipURL: URL, to dest: URL) throws {
            let fm = FileManager.default
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)

            // Optional: disable file protection on temp dir (rarely needed, but harmless)
            try? fm.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: dest.path)

            guard let archive = Archive(url: zipURL, accessMode: .read) else {
                throw FileErr.unzip
            }

            for entry in archive {
                // Skip AppleDouble/Finder cruft just in case
                if entry.path.hasPrefix("__MACOSX/") || entry.path.hasPrefix("._") { continue }

                let outURL = dest.appendingPathComponent(entry.path)

                do {
                    switch entry.type {
                    case .directory:
                        try fm.createDirectory(at: outURL, withIntermediateDirectories: true)
                    case .file:
                        try fm.createDirectory(at: outURL.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)
                        // Stream the contents to disk (avoids attribute/permission gotchas)
                        if fm.fileExists(atPath: outURL.path) { try fm.removeItem(at: outURL) }
                        fm.createFile(atPath: outURL.path, contents: nil)
                        let handle = try FileHandle(forWritingTo: outURL)
                        defer { try? handle.close() }

                        var wrote: Int64 = 0
                        try archive.extract(entry, bufferSize: 32 * 1024, consumer: { data in
                            try handle.write(contentsOf: data)
                            wrote += Int64(data.count)
                        })
                        // Optional: sanity check sizes
                        if wrote != Int64(entry.uncompressedSize) {
                            throw NSError(domain: "Unzip", code: 1001,
                                          userInfo: [NSLocalizedDescriptionKey:
                                            "Wrote \(wrote) but expected \(entry.uncompressedSize) for \(entry.path)"])
                        }
                    case .symlink: //.zip64EndOfCentralDirectory, .unknown:
                        // Not expected in an .mlpackage — skip
                        continue
                    }
                } catch {
                    let ns = error as NSError
                    print("❌ Extract failed: \(entry.path)  method=\(entry) " +
                          "size=\(entry.uncompressedSize)  error=\(ns.domain)#\(ns.code) \(ns.localizedDescription)")
                    throw error
                }
            }
        }
}
