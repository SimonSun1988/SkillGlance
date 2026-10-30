import CSQLite
import CoreFoundation
import Foundation

enum CursorSource {
  private static let maximumRows = 100_000
  private static let maximumScanBytes = ProviderFile.maximumBytes * 4

  static func scan(home: URL, catalog: [Skill]) throws -> ProviderScan {
    let url = home.appendingPathComponent(
      "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    var scan = ProviderScan(platform: .cursor, found: true)
    do {
      let values = try url.resourceValues(forKeys: [
        .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
      ])
      guard values.isRegularFile == true, values.isSymbolicLink != true else {
        scan.issue("Cursor 資料庫類型不受支援")
        return scan
      }
      scan.status.files = 1
      scan.status.bytes = Int64(values.fileSize ?? 0)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return ProviderScan(platform: .cursor, found: false)
    } catch {
      scan.issue("無法讀取 Cursor 資料庫")
      return scan
    }
    do {
      let database = try ReadDatabase(url)
      try database.verifySchema()
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          database.db,
          "SELECT key,value FROM cursorDiskKV WHERE key LIKE 'bubbleId:%' ORDER BY key LIMIT 100001",
          -1, &statement, nil) == SQLITE_OK
      else { throw StoreError(message: "Cursor 資料庫格式不受支援") }
      defer { sqlite3_finalize(statement) }
      var count = 0
      var bytes = 0
      var workspaces: [String: String] = [:]
      var events: [String: UsageEvent] = [:]
      while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { break }
        guard step == SQLITE_ROW else { throw StoreError(message: "Cursor 資料庫讀取未完成") }
        count += 1
        guard count <= maximumRows else {
          scan.issue("Cursor 紀錄超過本次掃描上限")
          break
        }
        guard let key = ReadDatabase.string(statement, column: 0),
          let data = ReadDatabase.data(statement, column: 1)
        else {
          scan.issue()
          continue
        }
        bytes += data.count
        guard bytes <= maximumScanBytes else {
          scan.issue("Cursor 紀錄超過本次掃描上限")
          break
        }
        // Only a record that names a SKILL.md can carry Skill evidence; skip decoding the rest.
        guard mentionsSkillFile(data) else { continue }
        guard let bubble = dictionary(data) else {
          scan.issue()
          continue
        }
        guard let rawTool = bubble["toolFormerData"] else { continue }
        let recorded = Dates.parse(bubble["createdAt"])
        guard let tool = rawTool as? [String: Any], let name = tool["name"] as? String else {
          scan.unresolved(rawTool, at: recorded)
          continue
        }
        guard name == "read_file_v2" else {
          scan.unresolved([tool["params"], tool["rawArgs"]], at: recorded)
          continue
        }
        let params = dictionary(tool["params"])
        let args = dictionary(tool["rawArgs"])
        guard let path = params?["targetFile"] as? String ?? args?["path"] as? String else {
          scan.unresolved([tool["params"], tool["rawArgs"]], at: recorded)
          continue
        }
        guard URL(fileURLWithPath: path).lastPathComponent == "SKILL.md" else { continue }
        let target = SkillIdentity.shortName(path)
        guard path.hasPrefix("/"), path.count <= 4096, !path.contains("\n"),
          !path.contains("\0")
        else {
          scan.unresolved(path, at: recorded, "部分 Skill 紀錄尚無法確認")
          continue
        }
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].isEmpty,
          let call = tool["toolCallId"] as? String, !call.isEmpty, call.count <= 4096,
          let time = recorded
        else {
          scan.block([target], at: recorded, "Cursor 技能紀錄缺少有效時間或識別碼")
          continue
        }
        let composer = String(parts[1])
        let cwd: String
        if let cached = workspaces[composer] {
          cwd = cached
        } else {
          cwd = try database.workspace(composer: composer, bytes: &bytes)
          workspaces[composer] = cwd
          if cwd.isEmpty { scan.note("Cursor 紀錄缺少專案歸屬") }
        }
        guard bytes <= maximumScanBytes else {
          scan.issue("Cursor 紀錄超過本次掃描上限")
          break
        }
        let result = dictionary(tool["result"])
        let outcome: Outcome
        if bubble["_v"] as? Int != 3 {
          outcome = .unknown
          scan.block([target], at: time, "Cursor 技能紀錄版本不受支援")
        } else {
          switch tool["status"] as? String {
          case "error", "cancelled": outcome = .failure
          case "completed" where positiveInteger(result?["totalLinesInFile"]): outcome = .success
          default:
            outcome = .unknown
            scan.block([target], at: time, "Cursor 技能讀取結果尚無法確認")
          }
        }
        let id = stableID("cursor|\(composer)|\(call)|0")
        var event = UsageEvent(
          id: id, platform: .cursor, session: composer, group: composer,
          skillID: SkillIdentity.resolve(path, catalog: catalog), target: path, time: time,
          cwd: cwd, evidence: .read, outcome: outcome, confirmed: outcome == .success,
          scope: params?["limit"] != nil || params?["offset"] != nil ? "部分" : "完整",
          source: url.path, line: 0)
        if let previous = events[id] {
          if previous != event {
            event = previous
            event.outcome = .unknown
            event.confirmed = false
            event.conflicted = true
            if previous.target != path { event.skillID = nil }
            scan.block(
              [target, SkillIdentity.shortName(previous.target)], at: time,
              "Cursor 相同工具識別碼的紀錄互相衝突")
          } else {
            continue
          }
        }
        events[id] = event
      }
      scan.events = events.values.sorted { $0.id < $1.id }
    } catch {
      scan.issue("Cursor 資料庫無法讀取或格式不受支援")
    }
    return scan
  }

  private static func positiveInteger(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return false }
    let value = number.doubleValue
    return value.isFinite && value > 0 && value.rounded(.down) == value
  }

  static func mentionsSkillFile(_ data: Data) -> Bool {
    let needle = Array("SKILL.md".utf8)
    return data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return false }
      return memmem(base, raw.count, needle, needle.count) != nil
    }
  }

  private static func dictionary(_ value: Any?) -> [String: Any]? {
    if let value = value as? [String: Any] { return value }
    if let value = value as? String { return dictionary(Data(value.utf8)) }
    if let value = value as? Data {
      return (try? JSONSerialization.jsonObject(with: value)) as? [String: Any]
    }
    return nil
  }

  private final class ReadDatabase {
    let db: OpaquePointer
    private var hasHeaders = false

    init(_ url: URL) throws {
      var pointer: OpaquePointer?
      let result = sqlite3_open_v2(
        // READONLY protects records; SQLite may still update its WAL shared-memory coordination file.
        url.path, &pointer, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
      guard result == SQLITE_OK, let pointer else {
        if let pointer { sqlite3_close(pointer) }
        throw StoreError(message: "無法開啟 Cursor 資料庫")
      }
      db = pointer
      guard sqlite3_db_readonly(db, "main") == 1 else {
        sqlite3_close(db)
        throw StoreError(message: "Cursor 資料庫不是唯讀連線")
      }
      sqlite3_busy_timeout(db, 1000)
      sqlite3_limit(db, SQLITE_LIMIT_LENGTH, Int32(ProviderFile.maximumBytes))
    }

    deinit { sqlite3_close(db) }

    func verifySchema() throws {
      guard supports("SELECT key,value FROM cursorDiskKV LIMIT 0") else {
        throw StoreError(message: "Cursor 資料庫格式不受支援")
      }
      hasHeaders = supports("SELECT composerId,value FROM composerHeaders LIMIT 0")
    }

    private func supports(_ sql: String) -> Bool {
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }
      return sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK
    }

    func workspace(composer: String, bytes: inout Int) throws -> String {
      let metadata = try object(
        "SELECT value FROM cursorDiskKV WHERE key=? LIMIT 1",
        argument: "composerData:" + composer, bytes: &bytes)
      if let path = Self.workspacePath(metadata) { return path }
      if hasHeaders {
        let header = try object(
          "SELECT value FROM composerHeaders WHERE composerId=? LIMIT 1",
          argument: composer, bytes: &bytes)
        if let path = Self.workspacePath(header) { return path }
      }
      return ""
    }

    private static func workspacePath(_ object: [String: Any]?) -> String? {
      guard let workspace = object?["workspaceIdentifier"] as? [String: Any],
        let uri = workspace["uri"] as? String, let url = URL(string: uri),
        url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
        url.path.hasPrefix("/"), url.path.count <= 4096, !url.path.contains("\n")
      else { return nil }
      return url.path
    }

    private func object(_ sql: String, argument: String, bytes: inout Int) throws -> [String: Any]?
    {
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw StoreError(message: "Cursor 專案資料格式不受支援")
      }
      sqlite3_bind_text(
        statement, 1, argument, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      let result = sqlite3_step(statement)
      if result == SQLITE_DONE { return nil }
      guard result == SQLITE_ROW, let data = Self.data(statement, column: 0) else {
        throw StoreError(message: "Cursor 專案資料無法讀取")
      }
      bytes += data.count
      guard bytes <= maximumScanBytes else { throw StoreError(message: "Cursor 掃描超過上限") }
      return dictionary(data)
    }

    static func data(_ statement: OpaquePointer?, column: Int32) -> Data? {
      let size = Int(sqlite3_column_bytes(statement, column))
      guard size > 0, size <= ProviderFile.maximumBytes,
        let pointer = sqlite3_column_blob(statement, column)
      else { return nil }
      return Data(bytes: pointer, count: size)
    }

    static func string(_ statement: OpaquePointer?, column: Int32) -> String? {
      guard let data = data(statement, column: column) else { return nil }
      return String(data: data, encoding: .utf8)
    }
  }
}
