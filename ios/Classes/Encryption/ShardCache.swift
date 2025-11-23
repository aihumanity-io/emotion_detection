import Foundation

struct CekShardLease {
  let shard: Data
  let expiresAt: Date?

  func isExpired(now: Date = Date()) -> Bool {
    guard let exp = expiresAt else { return false }
    return now >= exp
  }
}

enum ShardCacheError: Error { case invalidBase64, emptyShard }

enum ShardCache {
  private static var shards: [String: CekShardLease] = [:]
  private static let lock = NSLock()

  static func setShard(modelId rawModelId: String, base64: String, expiresAtMs: Int64?) throws {
    let modelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !modelId.isEmpty else { throw ShardCacheError.invalidBase64 }
    guard let data = Data(base64Encoded: base64) else { throw ShardCacheError.invalidBase64 }
    guard !data.isEmpty else { throw ShardCacheError.emptyShard }

    let expiry: Date?
    if let ms = expiresAtMs { expiry = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0) }
    else { expiry = nil }

    let lease = CekShardLease(shard: data, expiresAt: expiry)
    lock.lock(); defer { lock.unlock() }
    shards[modelId] = lease
  }

  static func clearShard(modelId rawModelId: String) {
    let modelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !modelId.isEmpty else { return }
    lock.lock(); defer { lock.unlock() }
    shards.removeValue(forKey: modelId)
  }

  static func activeShard(for identifiers: [String], now: Date = Date()) -> CekShardLease? {
    lock.lock(); defer { lock.unlock() }
    for id in identifiers {
      let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, let lease = shards[trimmed] else { continue }
      if lease.isExpired(now: now) {
        shards.removeValue(forKey: trimmed)
        continue
      }
      return lease
    }
    return nil
  }
}
