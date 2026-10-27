import CSQLite
import Foundation

public struct StoreError: Error, LocalizedError {
  public let message: String
  public var errorDescription: String? { message }
}
public actor UsageStore {
  private let url: URL
  public init(directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    url = directory.appendingPathComponent("usage.sqlite")
  }
  private func withDatabase<T>(_ action: (OpaquePointer) throws -> T) throws -> T {
    var pointer: OpaquePointer?
    guard sqlite3_open(url.path, &pointer) == SQLITE_OK, let db = pointer else {
      if let pointer { sqlite3_close(pointer) }
      throw StoreError(message: "無法開啟本機資料庫")
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 5000)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    guard
      sqlite3_exec(
        db, "CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value BLOB NOT NULL)", nil,
        nil, nil) == SQLITE_OK
    else { throw StoreError(message: String(cString: sqlite3_errmsg(db))) }
    return try action(db)
  }
  private func read<T: Decodable>(_ key: String, as: T.Type) throws -> T? {
    try withDatabase { db in
      var query: OpaquePointer?
      defer { sqlite3_finalize(query) }
      guard
        sqlite3_prepare_v2(db, "SELECT value FROM state WHERE key = ?", -1, &query, nil)
          == SQLITE_OK
      else { throw StoreError(message: String(cString: sqlite3_errmsg(db))) }
      sqlite3_bind_text(query, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      guard sqlite3_step(query) == SQLITE_ROW else { return nil }
      guard let bytes = sqlite3_column_blob(query, 0) else { return nil }
      return try JSONDecoder().decode(
        T.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0))))
    }
  }
  public func load() throws -> Snapshot { try read("snapshot", as: Snapshot.self) ?? Snapshot() }
  public func checkpoints() throws -> [String: Checkpoint] {
    try read("checkpoints", as: [String: Checkpoint].self) ?? [:]
  }
  public func save(_ snapshot: Snapshot, checkpoints: [String: Checkpoint]) throws {
    let values = [
      ("snapshot", try JSONEncoder().encode(snapshot)),
      ("checkpoints", try JSONEncoder().encode(checkpoints)),
    ]
    try withDatabase { db in
      guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
        throw StoreError(message: String(cString: sqlite3_errmsg(db)))
      }
      do {
        for (key, data) in values {
          var query: OpaquePointer?
          defer { sqlite3_finalize(query) }
          guard
            sqlite3_prepare_v2(
              db, "INSERT OR REPLACE INTO state(key,value) VALUES(?,?)", -1, &query, nil)
              == SQLITE_OK
          else { throw StoreError(message: String(cString: sqlite3_errmsg(db))) }
          let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
          sqlite3_bind_text(query, 1, key, -1, transient)
          _ = data.withUnsafeBytes {
            sqlite3_bind_blob(query, 2, $0.baseAddress, Int32(data.count), transient)
          }
          guard sqlite3_step(query) == SQLITE_DONE else {
            throw StoreError(message: String(cString: sqlite3_errmsg(db)))
          }
        }
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
          throw StoreError(message: String(cString: sqlite3_errmsg(db)))
        }
      } catch {
        sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
        throw error
      }
    }
  }
}
