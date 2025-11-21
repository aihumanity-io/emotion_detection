import Foundation

enum ManifestLoadError: Error { case notFound, readFailed, decodeFailed(Error) }

/// Load a Manifest JSON that was added to your app/framework bundle.
/// Examples:
///   try loadManifestJSON(fromBundle: "aih_fer20250115.manifest")
///   try loadManifestJSON(fromBundle: "aih_fer20250115.manifest.json")
///   try loadManifestJSON(fromBundle: "aih_fer20250115", in: .main)
func loadManifestJSON(fromBundle name: String,
in bundle: Bundle = .main) throws -> Manifest {
    // Try exact (when you pass a full filename with extension)
    if let url = bundle.url(forResource: name, withExtension: nil) {
        return try decodeManifest(at: url)
    }

    // Decompose (handle ".manifest" → ".manifest.json")
    let ns = name as NSString
    let base = ns.deletingPathExtension
    let ext  = ns.pathExtension

    // Candidate (name, extension) pairs to try in order
    var candidates: [(String, String?)] = []

    // If you passed "foo.manifest", prefer "foo" + "manifest.json"
    if ext == "manifest" {
        candidates.append((base, "manifest.json"))
    }

    // Common variants
    candidates += [
        (name, "json"),
        (base, "manifest.json"),
        (base, "json"),
        (name, nil) // last resort
    ]

    // Search given bundle, then any loaded bundles/frameworks as a fallback
    let searchBundles: [Bundle] = [bundle] + Bundle.allBundles + Bundle.allFrameworks

    for b in searchBundles {
        for (n, e) in candidates {
            if let url = b.url(forResource: n, withExtension: e) {
                return try decodeManifest(at: url)
            }
        }
    }
    throw ManifestLoadError.notFound
}

private func decodeManifest(at url: URL) throws -> Manifest {
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    } catch let err as DecodingError {
        throw ManifestLoadError.decodeFailed(err)
    } catch {
        throw ManifestLoadError.readFailed
    }
}
