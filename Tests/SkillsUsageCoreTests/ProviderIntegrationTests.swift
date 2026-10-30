import Foundation
import Testing

@testable import SkillsUsageCore

@Test func declaredSkillNameCanDifferFromItsDirectory() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent("directory-name")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  try "---\nname: manifest-name\ndescription: Synthetic instructions\n---\n# Example".write(
    to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  let catalog = SkillInventory.scan(roots: [root]).map { Skill($0, now: Date()) }
  #expect(SkillIdentity.resolve("manifest-name", catalog: catalog) == catalog.first?.id)
  #expect(catalog.count == 1)
}

@Test func absentOptionalToolsDoNotBlockButMissingCoverageOrPartialEvidenceDoes() {
  let now = Date()
  var skill = fixtureSkill()
  skill.observedAt = now.addingTimeInterval(-100 * 86400)
  var snapshot = Snapshot()
  snapshot.skills = [skill]
  snapshot.lastScan = now
  snapshot.sourceCoverageRevision = 1
  snapshot.sources = Platform.allCases.map { platform in
    SourceStatus(
      id: platform.rawValue, platform: platform, files: platform == .codex ? 1 : 0,
      bytes: 0, issues: 0, message: "fixture", requiredForAssessment: platform == .codex)
  }
  #expect(UsageMetrics.rows(snapshot, now: now).first?.candidate == true)
  snapshot.sources.removeLast()
  #expect(UsageMetrics.rows(snapshot, now: now).first?.candidate == false)
  snapshot.sources.append(
    SourceStatus(
      id: "cursor", platform: .cursor, files: 1, bytes: 10,
      issues: 1, message: "partial", requiredForAssessment: true))
  #expect(UsageMetrics.rows(snapshot, now: now).first?.candidate == false)
}

@Test func importerSeparatesClaudeDesktopAndCodeAndRetainsStableEvents() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent(".claude/projects/project")
  let skills = root.appendingPathComponent(".agents/skills/clean-code")
  for path in [folder, skills] {
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
  }
  try "# Instructions".write(
    to: skills.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  for entrypoint in ["cli", "claude-desktop"] {
    var record = skillContextRecord(skills.path)
    record["entrypoint"] = entrypoint
    let data = try JSONSerialization.data(withJSONObject: record) + Data([10])
    try data.write(to: folder.appendingPathComponent(entrypoint + ".jsonl"))
  }
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: root, store: store)
  let first = try await importer.scan()
  #expect(first.events.count == 2)
  #expect(Set(first.events.map(\.platform)) == Set([.claudeDesktop, .claudeCode]))
  #expect(first.events.allSatisfy { $0.confirmed })
  #expect(UsageMetrics.summary(first.events).conversations == 2)
  #expect(Set(first.sources.map(\.platform)) == Set(Platform.allCases))
  #expect(first.sources.first { $0.platform == .claudeDesktop }?.files == 1)
  #expect(first.sources.first { $0.platform == .claudeCode }?.files == 1)
  let second = try await importer.scan()
  #expect(Set(second.events.map(\.id)) == Set(first.events.map(\.id)))
}

@Test func legacySnapshotStillDecodesWithoutNewProviderMetadata() throws {
  let json =
    #"{"skills":[],"events":[],"sources":[{"id":"codex","platform":"codex","files":1,"bytes":10,"issues":0,"message":"ready"}],"issues":[],"projectRoots":[]}"#
  let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
  #expect(snapshot.sourceCoverageRevision == nil)
  #expect(snapshot.sources.first?.requiredForAssessment == nil)
}

@Test func entrypointProvenDesktopSubagentIsNotCountedAgainAsCLI() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent(".claude/projects/project")
  let children = folder.appendingPathComponent("parent/subagents")
  try FileManager.default.createDirectory(at: children, withIntermediateDirectories: true)
  var parent = skillContextRecord("/skills/clean-code")
  parent["sessionId"] = "parent"
  var child = skillContextRecord("/skills/clean-code", id: "77777777-7777-4777-8777-777777777777")
  child["sessionId"] = "child"
  child.removeValue(forKey: "entrypoint")
  for (file, record) in [
    (folder.appendingPathComponent("parent.jsonl"), parent),
    (children.appendingPathComponent("child.jsonl"), child),
  ] {
    try (JSONSerialization.data(withJSONObject: record) + Data([10])).write(to: file)
  }
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let snapshot = try await ImportCoordinator(home: root, store: store).scan()
  #expect(snapshot.events.filter { $0.platform == .claudeDesktop }.count == 2)
  #expect(snapshot.events.filter { $0.platform == .claudeCode }.isEmpty)
}

@Test func providerRescanCannotEraseAnAlreadyConfirmedRead() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent(".gemini/tmp/project/chats")
  let skill = root.appendingPathComponent(".agents/skills/clean-code")
  for path in [folder, skill] {
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
  }
  try "# Instructions".write(
    to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  let file = folder.appendingPathComponent("session-test.json")
  func write(output: Bool) throws {
    let call: [String: Any] = [
      "id": "read", "name": "read_file",
      "args": ["file_path": skill.appendingPathComponent("SKILL.md").path], "status": "success",
      "timestamp": "2026-10-27T01:00:00Z",
      "result": output
        ? [["functionResponse": ["id": "read", "response": ["output": "Instructions"]]]] : [],
    ]
    let session: [String: Any] = [
      "sessionId": "session", "projectHash": "project",
      "messages": [["id": "m", "type": "gemini", "toolCalls": [call]]],
    ]
    try JSONSerialization.data(withJSONObject: session).write(to: file)
  }
  try write(output: true)
  let store = try UsageStore(directory: root.appendingPathComponent("db"))
  let importer = ImportCoordinator(home: root, store: store)
  let first = try await importer.scan()
  #expect(first.events.first?.confirmed == true)
  try write(output: false)
  let second = try await importer.scan()
  #expect(second.events.first?.confirmed == true)
  #expect(UsageMetrics.summary(second.events).reads == 1)
  #expect(second.sources.first { $0.platform == .gemini }!.issues == 0)
  #expect(second.blockedNames?["clean-code"] != nil)
  #expect(second.issues.isEmpty)
}

@Test func identityIndexMatchesTheCatalogScanForEveryKindOfTarget() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let real = root.appendingPathComponent("real/linked")
  try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
  try FileManager.default.createSymbolicLink(
    at: root.appendingPathComponent("link"), withDestinationURL: real)
  func skill(_ path: String, aliases: [String], declared: String? = nil) -> Skill {
    Skill(DiscoveredSkill(path: path, aliases: aliases, declaredName: declared), now: Date())
  }
  let catalog = [
    skill(real.path, aliases: [root.appendingPathComponent("link").path]),
    skill("/a/unique", aliases: ["/a/unique"], declared: "pretty-name"),
    skill("/a/twin", aliases: ["/a/twin"]), skill("/b/twin", aliases: ["/b/twin"]),
    skill("/c/plain", aliases: ["/c/alias-dir"]),
  ]
  // The original rule: exactly one catalog entry may match the target.
  func scanned(_ target: String) -> String? {
    let path = URL(fileURLWithPath: target).deletingLastPathComponent().path
    let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    let name = target.split(separator: ":").last.map(String.init) ?? target
    let matches = catalog.filter { skill in
      if target.hasSuffix("/SKILL.md") {
        return skill.path == canonical || skill.aliases.contains(path)
      }
      return skill.name == target || skill.name == name || skill.declaredName == target
        || skill.declaredName == name
        || skill.aliases.contains { URL(fileURLWithPath: $0).lastPathComponent == name }
    }
    return matches.count == 1 ? matches[0].id : nil
  }
  let targets = [
    real.appendingPathComponent("SKILL.md").path,
    root.appendingPathComponent("link/SKILL.md").path, "/a/unique/SKILL.md", "/a/twin/SKILL.md",
    "/nowhere/SKILL.md", "unique", "pretty-name", "plugin:pretty-name", "twin", "plugin:twin",
    "alias-dir", "plain", "missing", "a:b:unique", "",
  ]
  let index = SkillIdentity.Index(catalog)
  for target in targets { #expect(index.resolve(target) == scanned(target), "\(target)") }
  #expect(index.resolve("twin") == nil)
  #expect(index.resolve("pretty-name") == catalog[1].id)
}
