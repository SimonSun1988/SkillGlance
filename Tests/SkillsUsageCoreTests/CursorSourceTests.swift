import CSQLite
import Foundation
import Testing

@testable import SkillsUsageCore

@Test func cursorCountsOnlyCompletedSuccessfulSkillReads() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  try fixture.composer()
  try fixture.bubble("a", call: "success", status: "completed")
  try fixture.bubble("b", call: "error", status: "error", lines: 0)
  try fixture.bubble("c", call: "cancelled", status: "cancelled")
  try fixture.bubble("d", call: "unknown", status: "future-status")
  try fixture.bubble("e", call: "empty", status: "completed", lines: 0)
  let scan = try CursorSource.scan(home: fixture.home, catalog: [])
  #expect(scan.events.count == 5)
  #expect(scan.events.filter(\.confirmed).count == 1)
  #expect(scan.events.filter { $0.outcome == .failure }.count == 2)
  #expect(scan.events.filter { $0.outcome == .unknown }.count == 2)
  #expect(scan.status.issues == 0)
  #expect(Set(scan.blockedNames.keys) == ["example"])
  #expect(scan.events.first?.cwd == "/example/project")
  #expect(scan.events.first?.group == "composer")
  #expect(scan.events.allSatisfy { $0.source == fixture.database.path && $0.line == 0 })
}

@Test func cursorSkipsMissingTimeAndCallIDWithoutFabricatingEvidence() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  try fixture.composer()
  try fixture.bubble("a", call: "no-time", time: nil)
  try fixture.bubble("b", call: nil)
  try fixture.bubble("c", call: "bad-time", time: "not-a-date")
  let scan = try CursorSource.scan(home: fixture.home, catalog: [])
  #expect(scan.events.isEmpty)
  #expect(scan.status.issues == 0)
  #expect(Set(scan.blockedNames.keys) == ["example"])
}

@Test func cursorDeduplicatesCallIDsAndMarksConflictingCopiesUnknown() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  try fixture.composer()
  try fixture.bubble("a", call: "same")
  try fixture.bubble("b", call: "same")
  #expect(try CursorSource.scan(home: fixture.home, catalog: []).events.count == 1)
  try fixture.bubble("c", call: "same", status: "error", lines: 0)
  let scan = try CursorSource.scan(home: fixture.home, catalog: [])
  #expect(scan.events.count == 1)
  #expect(scan.events.first?.outcome == .unknown)
  #expect(scan.events.first?.confirmed == false)
  #expect(scan.events.first?.conflicted == true)
  #expect(scan.status.issues == 0)
  #expect(Set(scan.blockedNames.keys) == ["example"])
}

@Test func cursorUsesHeaderWorkspaceFallbackAndLeavesDatabaseUnchanged() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  try fixture.composer(uri: nil)
  try fixture.insert(
    "INSERT INTO composerHeaders(composerId,value) VALUES(?,?)",
    values: [
      "composer", CursorFixture.json(["workspaceIdentifier": ["uri": "file:///example/fallback"]]),
    ])
  try fixture.bubble("a", call: "one")
  let before = try Data(contentsOf: fixture.database)
  let scan = try CursorSource.scan(home: fixture.home, catalog: [])
  #expect(scan.events.first?.cwd == "/example/fallback")
  #expect(scan.events.first?.confirmed == true)
  #expect(scan.status.issues == 0)
  #expect(try Data(contentsOf: fixture.database) == before)
  #expect(!FileManager.default.fileExists(atPath: fixture.database.path + "-journal"))
}

@Test func cursorReadsCommittedWALWithoutCopyingOrCheckpointing() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  try fixture.execute("PRAGMA journal_mode=WAL")
  try fixture.execute("PRAGMA wal_autocheckpoint=0")
  try fixture.composer()
  try fixture.bubble("a", call: "wal")
  let wal = URL(fileURLWithPath: fixture.database.path + "-wal")
  let before = try Data(contentsOf: wal)
  #expect(try CursorSource.scan(home: fixture.home, catalog: []).events.first?.confirmed == true)
  #expect(try Data(contentsOf: wal) == before)
}

@Test func cursorReportsMissingUnsupportedAndMalformedDatabases() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  let missing = try CursorSource.scan(
    home: fixture.home.appendingPathComponent("missing"), catalog: [])
  #expect(missing.status.requiredForAssessment == false)
  try fixture.execute("DROP TABLE cursorDiskKV")
  #expect(try CursorSource.scan(home: fixture.home, catalog: []).status.issues > 0)
}

@Test func cursorDoesNotCountOtherFilesAndFlagsMalformedRelevantResults() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  try fixture.composer()
  try fixture.bubble("a", call: "other", path: "/example/README.md")
  try fixture.bubble("b", call: "malformed", result: "not-json")
  let scan = try CursorSource.scan(home: fixture.home, catalog: [])
  #expect(scan.events.count == 1)
  #expect(scan.events.first?.outcome == .unknown)
  #expect(scan.status.issues == 0)
  #expect(Set(scan.blockedNames.keys) == ["example"])
}

@Test func cursorRejectsUnknownSchemaAndNonDatabaseFiles() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  try fixture.composer()
  try fixture.bubble("a", call: "version", version: 99)
  let scan = try CursorSource.scan(home: fixture.home, catalog: [])
  #expect(scan.events.first?.outcome == .unknown)
  #expect(scan.events.first?.confirmed == false)
  #expect(scan.status.issues == 0)
  #expect(Set(scan.blockedNames.keys) == ["example"])
  try Data("not sqlite".utf8).write(to: fixture.database)
  #expect(try CursorSource.scan(home: fixture.home, catalog: []).status.issues > 0)
}

@Test func cursorResolvesCatalogIdentityWithoutPersistingToolContent() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  try fixture.composer()
  try fixture.bubble("a", call: "catalog")
  let skill = Skill(DiscoveredSkill(path: "/example/skills/example", aliases: []), now: Date())
  let scan = try CursorSource.scan(home: fixture.home, catalog: [skill])
  #expect(scan.events.first?.skillID == skill.id)
  let encoded = try JSONEncoder().encode(scan.events)
  #expect(!String(decoding: encoded, as: UTF8.self).contains("private fixture body"))
}

@Test func cursorRejectsSymbolicLinkDatabaseSources() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  let home = fixture.home.appendingPathComponent("linked")
  let link = home.appendingPathComponent(
    "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
  try FileManager.default.createDirectory(
    at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.database)
  let scan = try CursorSource.scan(home: home, catalog: [])
  #expect(scan.events.isEmpty)
  #expect(scan.status.issues > 0)
  #expect(scan.status.requiredForAssessment == true)
}

private final class CursorFixture {
  let home: URL
  let database: URL
  private var db: OpaquePointer?

  init() throws {
    home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    database = home.appendingPathComponent(
      "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    try FileManager.default.createDirectory(
      at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard sqlite3_open(database.path, &db) == SQLITE_OK else {
      throw StoreError(message: "fixture open")
    }
    try execute("CREATE TABLE cursorDiskKV(key TEXT UNIQUE, value BLOB)")
    try execute("CREATE TABLE composerHeaders(composerId TEXT PRIMARY KEY, value TEXT)")
  }

  func remove() {
    sqlite3_close(db)
    db = nil
    try? FileManager.default.removeItem(at: home)
  }

  func execute(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw StoreError(message: "fixture SQL")
    }
  }

  func insert(_ sql: String, values: [String]) throws {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StoreError(message: "fixture prepare")
    }
    for (index, value) in values.enumerated() {
      sqlite3_bind_text(
        statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw StoreError(message: "fixture insert")
    }
  }

  static func json(_ object: [String: Any]) -> String {
    String(
      data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      encoding: .utf8)!
  }

  func composer(uri: String? = "file:///example/project") throws {
    let workspace: [String: String] =
      uri.map { ["id": "workspace", "uri": $0] } ?? ["id": "workspace"]
    try insert(
      "INSERT INTO cursorDiskKV VALUES(?,?)",
      values: [
        "composerData:composer",
        Self.json(["composerId": "composer", "workspaceIdentifier": workspace]),
      ])
  }

  func bubble(
    _ bubble: String, call: String?, status: String = "completed", lines: Int = 12,
    time: String? = "2026-10-27T00:00:00.000Z", path: String = "/example/skills/example/SKILL.md",
    result: String? = nil, version: Int = 3
  ) throws {
    var tool: [String: Any] = [
      "name": "read_file_v2", "status": status,
      "params": Self.json([
        "targetFile": path, "effectiveUri": "file://" + path, "charsLimit": 100000,
      ]),
      "rawArgs": Self.json(["path": path]),
      "result": result
        ?? Self.json(["totalLinesInFile": lines, "contents": "private fixture body"]),
    ]
    if let call { tool["toolCallId"] = call }
    var object: [String: Any] = ["_v": version, "bubbleId": bubble, "toolFormerData": tool]
    if let time { object["createdAt"] = time }
    try insert(
      "INSERT INTO cursorDiskKV VALUES(?,?)",
      values: ["bubbleId:composer:" + bubble, Self.json(object)])
  }
}

@Test func cursorUnknownStructuredReadArgumentsAreNotTreatedAsCompleteCoverage() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  try fixture.composer()
  let bubble: [String: Any] = [
    "_v": 3, "createdAt": "2026-10-27T01:00:00Z",
    "toolFormerData": [
      "name": "future_read", "params": ["paths": ["/skills/clean-code/SKILL.md"]],
    ],
  ]
  try fixture.insert(
    "INSERT INTO cursorDiskKV(key,value) VALUES(?,?)",
    values: ["bubbleId:composer:future", CursorFixture.json(bubble)])
  let scan = try CursorSource.scan(home: fixture.home, catalog: [])
  #expect(scan.events.isEmpty)
  #expect(scan.status.issues == 0)
  #expect(Set(scan.blockedNames.keys) == ["clean-code"])
}

@Test func cursorMissingProjectOrUnknownOutcomeDoesNotBlockOtherSkills() throws {
  let fixture = try CursorFixture()
  defer { fixture.remove() }
  try fixture.composer(uri: nil)
  try fixture.bubble("a", call: "unattributed")
  try fixture.bubble("b", call: "pending", status: "running")
  try fixture.insert(
    "INSERT INTO cursorDiskKV(key,value) VALUES(?,?)",
    values: [
      "bubbleId:composer:other",
      CursorFixture.json([
        "_v": 3, "toolFormerData": ["name": "run_terminal_cmd", "params": ["command": "ls"]],
      ]),
    ])
  let scan = try CursorSource.scan(home: fixture.home, catalog: [])
  #expect(scan.status.issues == 0)
  #expect(Set(scan.blockedNames.keys) == ["example"])
  #expect(scan.notices.contains("Cursor 紀錄缺少專案歸屬"))
  let now = Date()
  var snapshot = Snapshot()
  snapshot.skills = ["example", "other"].map {
    Skill(DiscoveredSkill(path: "/skills/\($0)", aliases: []), now: now.addingTimeInterval(-100 * 86400))
  }
  snapshot.lastScan = now
  snapshot.blockedNames = scan.blockedNames.mapValues { _ in now }
  snapshot.sources = [
    SourceStatus(id: "c", platform: .codex, files: 1, bytes: 1, issues: 0, message: ""),
    SourceStatus(id: "d", platform: .claudeDesktop, files: 1, bytes: 1, issues: 0, message: ""),
  ]
  let rows = UsageMetrics.rows(snapshot, now: now)
  #expect(rows.first { $0.skill.name == "other" }?.candidate == true)
  #expect(rows.first { $0.skill.name == "example" }?.candidate == false)
}
