import Foundation
import Testing

@testable import SkillsUsageCore

@Test func cliSkillCallsReadsAndContextLoadsAreRecognized() throws {
  var parser = LogParser()
  var state = ParseState()
  let skill = fixtureSkill()
  let call = try parse(
    #"{"type":"assistant","sessionId":"cli-session","entrypoint":"cli","timestamp":"2026-10-27T01:00:00Z","message":{"content":[{"type":"tool_use","id":"c","name":"Skill","input":{"skill":"clean-code"}}]}}"#
  )
  let pending = parser.consume(
    call, platform: .claudeCode, source: "fixture", line: 1, state: &state, catalog: [skill])
  #expect(pending.count == 1)
  #expect(pending.first?.platform == .claudeCode)
  let result = try parse(
    #"{"type":"user","sessionId":"cli-session","message":{"content":[{"type":"tool_result","tool_use_id":"c","content":"Loaded"}]}}"#
  )
  let finished = parser.consume(
    result, platform: .claudeCode, source: "fixture", line: 2, state: &state, catalog: [skill])
  #expect(finished.first?.outcome == .success)
  var context = skillContextRecord(skill.path)
  context["entrypoint"] = "cli"
  #expect(
    parser.consume(
      context, platform: .claudeCode, source: "fixture", line: 3, state: &state, catalog: [skill]
    ).first?.confirmed == true)
}

@Test func desktopSessionsNeverCountAsCLI() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent(".claude/projects/project")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let data = try JSONSerialization.data(withJSONObject: skillContextRecord("/skills/clean-code"))
  try (data + Data([10])).write(to: folder.appendingPathComponent("session.jsonl"))
  let result = try ClaudeCodeSource.scan(home: root, catalog: [fixtureSkill()], desktopIDs: [])
  #expect(result.events.isEmpty)
}

@Test func anEmptyClaudeHistoryRootIsIncompleteRatherThanZeroUse() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(
    at: root.appendingPathComponent(".claude/projects"), withIntermediateDirectories: true)
  let scan = try ClaudeCodeSource.scan(home: root, catalog: [], desktopIDs: [])
  #expect(scan.status.requiredForAssessment == true)
  #expect(scan.status.issues > 0)
}
