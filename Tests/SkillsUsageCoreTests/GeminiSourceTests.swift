import Foundation
import Testing

@testable import SkillsUsageCore

@Test func geminiActivationHasExplicitOutcomeAndNeverCountsNameMentions() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent(".gemini/tmp/project/chats")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let content =
    #"{"sessionId":"session","projectHash":"project","directories":["/example/project"],"messages":[{"id":"u","type":"user","timestamp":"2026-10-27T01:00:00Z","content":"activate clean-code"},{"id":"m","type":"gemini","timestamp":"2026-10-27T01:00:00Z","toolCalls":[{"id":"c","name":"activate_skill","args":{"name":"clean-code"},"status":"success","timestamp":"2026-10-27T01:00:00Z","result":[{"functionResponse":{"id":"c","response":{"output":"Loaded instructions"}}}]}]}]}"#
  try content.write(
    to: folder.appendingPathComponent("session-test.json"), atomically: true, encoding: .utf8)
  let result = try GeminiSource.scan(home: root, catalog: [fixtureSkill()])
  #expect(result.events.count == 1)
  #expect(result.events.first?.outcome == .success)
  #expect(result.events.first?.evidence == .invocation)
  #expect(result.events.first?.time == Dates.parse("2026-10-27T01:00:00Z"))
  #expect(result.events.first?.cwd == "/example/project")
}

@Test func geminiJSONLUpdatesAreDeduplicatedAndFailedLoadsAreNotConfirmed() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent(".gemini/tmp/project/chats")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let header = #"{"sessionId":"session","projectHash":"project"}"#
  let record =
    #"{"id":"m","type":"gemini","timestamp":"2026-10-27T01:00:00Z","toolCalls":[{"id":"read","name":"read_file","args":{"file_path":"/skills/clean-code/SKILL.md"},"status":"error","timestamp":"2026-10-27T01:00:00Z","result":[{"functionResponse":{"id":"read","response":{"error":"denied"}}}]}]}"#
  try (header + "\n" + record + "\n" + record + "\n").write(
    to: folder.appendingPathComponent("session-test.jsonl"), atomically: true, encoding: .utf8)
  let result = try GeminiSource.scan(home: root, catalog: [fixtureSkill()])
  #expect(result.events.count == 1)
  #expect(result.events.first?.outcome == .failure)
  #expect(result.events.first?.confirmed == false)
}

@Test func unknownGeminiToolWithStructuredSkillPathsIsIncomplete() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent(".gemini/tmp/project/chats")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let record =
    #"{"sessionId":"session","projectHash":"project","messages":[{"id":"m","type":"gemini","toolCalls":[{"id":"future","name":"read_many_files","args":{"paths":["/skills/clean-code/SKILL.md"]},"status":"success","timestamp":"2026-10-27T01:00:00Z"}]}]}"#
  try record.write(
    to: folder.appendingPathComponent("session-test.json"), atomically: true, encoding: .utf8)
  let scan = try GeminiSource.scan(home: root, catalog: [])
  #expect(scan.events.isEmpty)
  #expect(scan.status.issues > 0)
}
