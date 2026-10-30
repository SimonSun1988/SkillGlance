import Foundation
import Testing

@testable import SkillsUsageCore

@Test func parserUpgradeBackfillsContextLoadsWithoutResettingExistingData() async throws {
  let root = try temporaryDirectory().resolvingSymlinksInPath()
  defer { try? FileManager.default.removeItem(at: root) }
  let skillDir = root.appendingPathComponent(".agents/skills/clean-code")
  let project = root.appendingPathComponent(".claude/projects/p")
  for path in [skillDir, project] {
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
  }
  try "# Instructions".write(
    to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  let writtenLog = project.appendingPathComponent("session.jsonl")
  var bytes = try JSONSerialization.data(withJSONObject: skillContextRecord(skillDir.path))
  bytes.append(0x0a)
  try bytes.write(to: writtenLog)
  let log = try #require(
    ImportCoordinator.files(root.appendingPathComponent(".claude/projects"), extension: "jsonl")
      .first)
  let observed = Date().addingTimeInterval(-100 * 86400)
  var skill = Skill(DiscoveredSkill(path: skillDir.path, aliases: [skillDir.path]), now: observed)
  skill.important = true
  var before = Snapshot()
  before.skills = [skill]
  before.lastScan = Date()
  before.projectRoots = [root.path]
  before.events = [usage(skill, at: observed, group: "retained")]
  var checkpoint = Checkpoint()
  checkpoint.offset = UInt64(bytes.count)
  checkpoint.line = 1
  checkpoint.state = try JSONDecoder().decode(ParseState.self, from: Data("{}".utf8))
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  try await store.save(before, checkpoints: [log.path: checkpoint])
  let importer = ImportCoordinator(home: root, store: store)
  let first = try await importer.scan()
  #expect(first.skills.count == 1)
  #expect(first.events.filter { $0.evidence == .read && $0.confirmed }.count == 1)
  #expect(first.events.contains { $0.id == before.events[0].id })
  #expect(first.skills.first?.important == true)
  #expect(first.skills.first?.observedAt == observed)
  #expect(first.projectRoots == before.projectRoots)
  let savedCheckpoints = try await store.checkpoints()
  #expect(Set(savedCheckpoints.keys) == Set([log.path]))
  let savedCheckpoint = try #require(
    savedCheckpoints[log.path], "Checkpoint paths: \(savedCheckpoints.keys.sorted())")
  #expect(
    savedCheckpoint.state.parserRevision == ParseState.currentRevision,
    "Saved keys/revisions: \(savedCheckpoints.mapValues { $0.state.parserRevision })")
  let second = try await importer.scan()
  #expect(second.events.count == first.events.count)
}

@Test func importIsIncrementalAndKeepsImportantFlag() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let home = root.appendingPathComponent("home")
  let skill = home.appendingPathComponent(".agents/skills/clean-code")
  try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
  try "# Clean code\nInstructions".write(
    to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  let project = home.appendingPathComponent(".claude/projects/project")
  try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
  let log = project.appendingPathComponent("session.jsonl")
  let call =
    #"{"entrypoint":"claude-desktop","sessionId":"s","timestamp":"2026-10-27T01:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Skill","id":"c","input":{"skill":"clean-code"}}]}}"#
  try (call + "\n").write(to: log, atomically: true, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: home, store: store)
  let first = try await importer.scan()
  #expect(first.events.count == 1)
  #expect(first.skills.count == 1)
  guard let id = first.skills.first?.id else { return }
  try await importer.setImportant(id, value: true)
  let second = try await importer.scan()
  #expect(second.events.count == 1)
  #expect(second.skills.first?.important == true)
  let handle = try FileHandle(forWritingTo: log)
  try handle.seekToEnd()
  try handle.write(
    contentsOf: Data(
      (#"{"entrypoint":"claude-desktop","message":{"content":[{"type":"tool_result","tool_use_id":"c","is_error":false,"content":"loaded"}]}}"#
        + "\n").utf8))
  try handle.close()
  let third = try await importer.scan()
  #expect(third.events.count == 1)
  #expect(third.events.first?.outcome == .success)
  #expect(third.skills.first?.observedAt == first.skills.first?.observedAt)
}
@Test func failedRebuildPreservesOldStatistics() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let home = root.appendingPathComponent("home")
  let source = home.appendingPathComponent(".codex/sessions")
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
  try "not json\n".write(
    to: source.appendingPathComponent("broken.jsonl"), atomically: true, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  var before = Snapshot()
  let skill = fixtureSkill()
  before.skills = [skill]
  before.events = [usage(skill, at: Date(), group: "old")]
  before.lastScan = Date()
  try await store.save(before, checkpoints: [:])
  let importer = ImportCoordinator(home: home, store: store)
  do {
    _ = try await importer.scan(rebuild: true)
    Issue.record("failed rebuild should throw")
  } catch {}
  #expect(try await store.load().events.count == 1)
}
@Test func incompleteArchiveCopyCannotDowngradeKnownOutcome() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let home = root.appendingPathComponent("home")
  let source = home.appendingPathComponent(".codex/sessions")
  let archive = home.appendingPathComponent(".codex/archived_sessions")
  for url in [source, archive] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  let meta = #"{"type":"session_meta","payload":{"id":"s"}}"#
  let call =
    #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"c","arguments":"{\"cmd\":\"cat /skills/clean-code/SKILL.md\"}"}}"#
  let result =
    #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"c","output":"Process exited with code 0\nOutput:\ninstructions"}}"#
  try ([meta, call, result].joined(separator: "\n") + "\n").write(
    to: source.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: home, store: store)
  #expect(try await importer.scan().events.first?.confirmed == true)
  try ([meta, call].joined(separator: "\n") + "\n").write(
    to: archive.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
  #expect(try await importer.scan().events.first?.confirmed == true)
}
@Test func lateDesktopMetadataReplaysPreviouslyUnclassifiedFile() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let home = root.appendingPathComponent("home")
  let source = home.appendingPathComponent(".claude/projects/p")
  let metadata = home.appendingPathComponent(
    "Library/Application Support/Claude/claude-code-sessions")
  for url in [source, metadata] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  let call =
    #"{"sessionId":"s","message":{"content":[{"type":"tool_use","id":"c","name":"Skill","input":{"skill":"clean-code"}}]}}"#
  try (call + "\n").write(
    to: source.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: home, store: store)
  #expect(try await importer.scan().events.count == 0)
  try #"{"cliSessionId":"s"}"#.write(
    to: metadata.appendingPathComponent("ui.json"), atomically: true, encoding: .utf8)
  #expect(try await importer.scan().events.count == 1)
}
@Test func removingProjectScopeKeepsEventsAndFiles() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  var snapshot = Snapshot()
  snapshot.projectRoots = [root.path]
  let skill = fixtureSkill()
  snapshot.skills = [skill]
  snapshot.events = [usage(skill, at: Date(), group: "old")]
  try await store.save(snapshot, checkpoints: [:])
  let importer = ImportCoordinator(home: root, store: store)
  try await importer.removeProject(root.path)
  let saved = try await store.load()
  #expect(saved.projectRoots.isEmpty)
  #expect(saved.events.count == 1)
  #expect(FileManager.default.fileExists(atPath: root.path))
}
@Test func sameSizeInPlaceRewriteRereadsOnlyThatFileWithoutResettingObservation() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent(".codex/sessions")
  let skill = root.appendingPathComponent(".agents/skills/clean-code")
  for url in [source, skill] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  try "# Instructions".write(
    to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  let log = source.appendingPathComponent("s.jsonl")
  let first = #"{"type":"session_meta","payload":{"id":"a"}}"# + "\n"
  try first.write(to: log, atomically: false, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: root, store: store)
  let initial = try await importer.scan()
  let handle = try FileHandle(forWritingTo: log)
  try handle.seek(toOffset: 0)
  try handle.write(contentsOf: Data(first.replacingOccurrences(of: "\"a\"", with: "\"b\"").utf8))
  try handle.close()
  let rewritten = try await importer.scan()
  let rotated = { (snapshot: Snapshot) in
    (snapshot.notices ?? []).contains { $0.contains("截斷") || $0.contains("改寫") }
  }
  #expect(rotated(rewritten))
  #expect(rewritten.issues.isEmpty)
  #expect(rewritten.skills.map(\.observedAt) == initial.skills.map(\.observedAt))
  #expect(try await checkpoint(store, "/sessions/s.jsonl")?.state.session == "b")
  let next = try await importer.scan()
  #expect(!rotated(next))
  #expect(next.skills.map(\.observedAt) == initial.skills.map(\.observedAt))
}
private func checkpoint(_ store: UsageStore, _ suffix: String) async throws -> Checkpoint? {
  try await store.checkpoints().first { $0.key.hasSuffix(suffix) }?.value
}
@Test func deletedSourceFileKeepsEventsAndPrunesItsCheckpoint() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent(".codex/sessions")
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
  let meta = #"{"type":"session_meta","payload":{"id":"s"}}"#
  let call =
    #"{"type":"response_item","timestamp":"2026-10-27T01:00:00Z","payload":{"type":"function_call","name":"exec_command","call_id":"c","arguments":"{\"cmd\":\"cat /skills/clean-code/SKILL.md\"}"}}"#
  let old = source.appendingPathComponent("old.jsonl")
  try ([meta, call].joined(separator: "\n") + "\n").write(
    to: old, atomically: true, encoding: .utf8)
  try (#"{"type":"session_meta","payload":{"id":"t"}}"# + "\n").write(
    to: source.appendingPathComponent("kept.jsonl"), atomically: true, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: root, store: store)
  let first = try await importer.scan()
  #expect(first.events.count == 1)
  #expect(try await checkpoint(store, "/sessions/old.jsonl") != nil)
  try FileManager.default.removeItem(at: old)
  let second = try await importer.scan()
  #expect(second.events.map(\.id) == first.events.map(\.id))
  #expect(second.issues.isEmpty)
  #expect(try await checkpoint(store, "/sessions/old.jsonl") == nil)
  #expect(try await checkpoint(store, "/sessions/kept.jsonl") != nil)
  #expect(second.sources.first { $0.platform == .codex }?.issues == 0)
}
@Test func malformedLinesFromAnEarlierScanStillBlockLaterIncrementalScans() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent(".codex/sessions")
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
  let log = source.appendingPathComponent("s.jsonl")
  try "not json\n".write(to: log, atomically: true, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: root, store: store)
  let malformed = { (snapshot: Snapshot) in snapshot.issues.contains { $0.contains("無法解析") } }
  #expect(malformed(try await importer.scan()))
  let handle = try FileHandle(forWritingTo: log)
  try handle.seekToEnd()
  try handle.write(contentsOf: Data((#"{"type":"session_meta","payload":{"id":"s"}}"# + "\n").utf8))
  try handle.close()
  #expect(malformed(try await importer.scan()))
  #expect(malformed(try await importer.scan()))
}
@Test func unparsedCommandsBlockOnlyNamedSkillsAndOtherwiseLeaveANotice() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent(".codex/sessions")
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
  func call(_ id: String, _ command: String) throws -> String {
    let args = String(
      data: try JSONSerialization.data(withJSONObject: ["cmd": command]), encoding: .utf8)!
    return String(
      data: try JSONSerialization.data(withJSONObject: [
        "type": "response_item", "timestamp": "2026-10-27T01:00:00Z",
        "payload": [
          "type": "function_call", "name": "exec_command", "call_id": id, "arguments": args,
        ],
      ]), encoding: .utf8)!
  }
  let lines = [
    #"{"type":"session_meta","payload":{"id":"s"}}"#,
    try call("named", "python3 - <<'EOF'\nprint(open('/skills/clean-code/SKILL.md').read())\nEOF"),
    try call("anonymous", "rg -l SKILL.md ."),
  ]
  try (lines.joined(separator: "\n") + "\n").write(
    to: source.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let snapshot = try await ImportCoordinator(home: root, store: store).scan()
  #expect(snapshot.issues.isEmpty)
  #expect(Set((snapshot.blockedNames ?? [:]).keys) == ["clean-code"])
  #expect((snapshot.notices ?? []).contains { $0.contains("SKILL.md") })
}
@Test func requestBlobsNeverCreateEventsOrOverwriteRealTimes() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent(".claude/projects/p")
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
  let real =
    #"{"entrypoint":"claude-desktop","sessionId":"s","timestamp":"2026-10-27T01:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Skill","id":"c","input":{"skill":"clean-code"}}]}}"#
  let blob =
    #"{"type":"api-request-blob","entrypoint":"claude-desktop","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","id":"c","input":{"skill":"clean-code"}},{"type":"tool_use","name":"Skill","id":"blob-only","input":{"skill":"simplify"}}]}}"#
  try ([real, blob].joined(separator: "\n") + "\n").write(
    to: source.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
  var stored = usage(fixtureSkill(), at: Date(timeIntervalSince1970: 0), group: "s")
  stored.id = stableID("claudeDesktop|s|c|0")
  stored.platform = .claudeDesktop
  var before = Snapshot()
  before.events = [stored]
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  try await store.save(before, checkpoints: [:])
  let snapshot = try await ImportCoordinator(home: root, store: store).scan()
  #expect(snapshot.events.count == 1)
  #expect(snapshot.events.first?.time == Dates.parse("2026-10-27T01:00:00Z"))
  #expect(snapshot.events.first?.outcome == .success)
}
@Test func parserRevisionTwoReplaysOldCheckpointsWithoutRebuildingStatistics() async throws {
  #expect(ParseState.currentRevision == 2)
  let root = try temporaryDirectory().resolvingSymlinksInPath()
  defer { try? FileManager.default.removeItem(at: root) }
  let skillDir = root.appendingPathComponent(".agents/skills/clean-code")
  let project = root.appendingPathComponent(".claude/projects/p")
  for path in [skillDir, project] {
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
  }
  try "# Instructions".write(
    to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  var bytes = try JSONSerialization.data(withJSONObject: skillContextRecord(skillDir.path))
  bytes.append(0x0a)
  try bytes.write(to: project.appendingPathComponent("session.jsonl"))
  let log = try #require(
    ImportCoordinator.files(root.appendingPathComponent(".claude/projects"), extension: "jsonl")
      .first)
  let observed = Date().addingTimeInterval(-100 * 86400)
  let skill = Skill(DiscoveredSkill(path: skillDir.path, aliases: [skillDir.path]), now: observed)
  var before = Snapshot()
  before.skills = [skill]
  before.lastScan = Date()
  before.events = [usage(skill, at: observed, group: "retained")]
  var checkpoint = Checkpoint()
  checkpoint.offset = UInt64(bytes.count)
  checkpoint.line = 1
  checkpoint.state.parserRevision = 1
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  try await store.save(before, checkpoints: [log.path: checkpoint])
  let snapshot = try await ImportCoordinator(home: root, store: store).scan()
  #expect(snapshot.events.contains { $0.id == before.events[0].id })
  #expect(snapshot.events.contains { $0.scope == "上下文載入" && $0.confirmed })
  #expect(snapshot.skills.first?.observedAt == observed)
  #expect(try await store.checkpoints()[log.path]?.state.parserRevision == 2)
}
@Test func newProjectResolvesPreviouslyImportedNameAndProject() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let home = root.appendingPathComponent("home")
  let source = home.appendingPathComponent(".claude/projects/p")
  let project = root.appendingPathComponent("project")
  let skill = project.appendingPathComponent(".agents/skills/clean-code")
  for url in [source, skill] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  try "Instructions".write(
    to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  let object: [String: Any] = [
    "entrypoint": "claude-desktop", "sessionId": "s", "cwd": project.path,
    "message": [
      "content": [
        ["type": "tool_use", "id": "c", "name": "Skill", "input": ["skill": "clean-code"]]
      ]
    ],
  ]
  var data = try JSONSerialization.data(withJSONObject: object)
  data.append(10)
  try data.write(to: source.appendingPathComponent("s.jsonl"))
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: home, store: store)
  #expect(try await importer.scan().events.first?.skillID == nil)
  try await importer.addProject(project.path)
  let updated = try await importer.scan()
  #expect(updated.events.first?.skillID != nil)
  #expect(updated.events.first?.project == project.path)
}
@Test func successfulSettingsWritesCannotBeLostToConcurrentMutators() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try UsageStore(directory: root)
  var snapshot = Snapshot()
  for n in 0..<16 {
    var skill = fixtureSkill()
    skill.id = "skill-\(n)"
    snapshot.skills.append(skill)
  }
  try await store.save(snapshot, checkpoints: [:])
  let importer = ImportCoordinator(home: root, store: store)
  let successes = await withTaskGroup(of: String?.self) { group in
    for n in 0..<16 {
      group.addTask {
        do {
          try await importer.setImportant("skill-\(n)", value: true)
          return "skill-\(n)"
        } catch { return nil }
      }
    }
    var ids: [String] = []
    for await id in group { if let id { ids.append(id) } }
    return ids
  }
  let saved = try await store.load()
  #expect(saved.skills.filter(\.important).count == successes.count)
}
@Test func emptySuccessCopyDoesNotDowngradeConfirmedRead() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let home = root.appendingPathComponent("home")
  let source = home.appendingPathComponent(".codex/sessions")
  let archive = home.appendingPathComponent(".codex/archived_sessions")
  for url in [source, archive] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  let meta = #"{"type":"session_meta","payload":{"id":"s"}}"#
  let call =
    #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"c","arguments":"{\"cmd\":\"cat /skills/clean-code/SKILL.md\"}"}}"#
  let result =
    #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"c","output":"{\"exit_code\":0,\"output\":\"instructions\"}"}}"#
  try ([meta, call, result].joined(separator: "\n") + "\n").write(
    to: source.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: home, store: store)
  #expect(try await importer.scan().events.first?.confirmed == true)
  try
    ([meta, call, result.replacingOccurrences(of: "instructions", with: "")].joined(separator: "\n")
    + "\n").write(to: archive.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
  #expect(try await importer.scan().events.first?.confirmed == true)
}
@Test func knownCLIChildCannotInheritDesktopFromParent() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let home = root.appendingPathComponent("home")
  let project = home.appendingPathComponent(".claude/projects/p")
  let children = project.appendingPathComponent("parent/subagents")
  try FileManager.default.createDirectory(at: children, withIntermediateDirectories: true)
  try (#"{"entrypoint":"claude-desktop","sessionId":"parent"}"# + "\n").write(
    to: project.appendingPathComponent("parent.jsonl"), atomically: true, encoding: .utf8)
  let child = children.appendingPathComponent("child.jsonl")
  try (#"{"entrypoint":"cli","sessionId":"child"}"# + "\n").write(
    to: child, atomically: true, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: home, store: store)
  _ = try await importer.scan()
  let handle = try FileHandle(forWritingTo: child)
  try handle.seekToEnd()
  try handle.write(
    contentsOf: Data(
      (#"{"sessionId":"child","message":{"content":[{"type":"tool_use","name":"Skill","id":"c","input":{"skill":"clean-code"}}]}}"#
        + "\n").utf8))
  try handle.close()
  #expect(try await importer.scan().events.isEmpty)
}
@Test func contradictoryCopiesStayUnknown() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let home = root.appendingPathComponent("home")
  let source = home.appendingPathComponent(".codex/sessions")
  let archive = home.appendingPathComponent(".codex/archived_sessions")
  for url in [source, archive] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  let meta = #"{"type":"session_meta","payload":{"id":"s"}}"#
  let call =
    #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"c","arguments":"{\"cmd\":\"cat /skills/clean-code/SKILL.md\"}"}}"#
  let success =
    #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"c","output":"Process exited with code 0\nOutput:\ninstructions"}}"#
  let failure = success.replacingOccurrences(of: "code 0", with: "code 1")
  try ([meta, call, success].joined(separator: "\n") + "\n").write(
    to: source.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: home, store: store)
  _ = try await importer.scan()
  try ([meta, call, failure].joined(separator: "\n") + "\n").write(
    to: archive.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
  let updated = try await importer.scan()
  #expect(updated.events.first?.outcome == .unknown)
  #expect(updated.events.first?.confirmed == false)
}
