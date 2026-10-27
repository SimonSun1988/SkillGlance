import Foundation
import Testing

@testable import SkillsUsageCore

@Suite struct AntigravitySourceTests {
  @discardableResult
  private func transcript(
    _ home: URL, surface: String = "antigravity", conversation: String = "conversation-a",
    full: Bool = true, records: [[String: Any]], tail: String = ""
  ) throws -> URL {
    let logs = home.appendingPathComponent(
      ".gemini/\(surface)/brain/\(conversation)/.system_generated/logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    let file = logs.appendingPathComponent(full ? "transcript_full.jsonl" : "transcript.jsonl")
    var data = Data()
    for record in records {
      data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
      data.append(10)
    }
    data.append(contentsOf: tail.utf8)
    try data.write(to: file)
    return file
  }

  private func request(_ home: URL, index: Int = 10) -> [String: Any] {
    [
      "step_index": index, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
      "created_at": "2026-10-01T01:02:03Z",
      "tool_calls": [
        [
          "name": "view_file",
          "args": [
            "AbsolutePath": home.appendingPathComponent(
              ".gemini/config/skills/example/SKILL.md"
            ).path,
            "IsSkillFile": true, "toolSummary": "PRIVATE-SUMMARY",
          ],
        ]
      ],
    ]
  }

  @Test func explicitRequestStaysUnknownEvenWithAdjacentDoneResult() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try transcript(
      home,
      records: [
        request(home),
        [
          "step_index": 11, "source": "MODEL", "type": "GENERIC", "status": "DONE",
          "created_at": "2026-10-01T01:02:04Z", "content": "PRIVATE-CONTENT",
          "thinking": "PRIVATE-THINKING",
        ],
      ])
    let scan = try AntigravitySource.scan(home: home, catalog: [])
    let event = try #require(scan.events.first)
    #expect(scan.events.count == 1)
    #expect(event.evidence == .read)
    #expect(event.outcome == .unknown)
    #expect(!event.confirmed)
    #expect(event.skillID == nil)
    #expect(scan.status.issues > 0)
    #expect(scan.status.requiredForAssessment == true)
    let persisted = String(decoding: try JSONEncoder().encode(scan.events), as: UTF8.self)
    #expect(!persisted.contains("PRIVATE-"))
  }

  @Test func mentionsAndUnmarkedReadsAreNotSkillActivations() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    var unmarked = request(home)
    unmarked["tool_calls"] = [
      [
        "name": "view_file",
        "args": [
          "AbsolutePath": "/project/.agents/skills/example/SKILL.md"
        ],
      ]
    ]
    try transcript(
      home,
      records: [
        unmarked,
        [
          "step_index": 11, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
          "created_at": "2026-10-01T01:02:03Z", "content": "I used example SKILL.md",
        ],
      ])
    let scan = try AntigravitySource.scan(home: home, catalog: [])
    #expect(scan.events.isEmpty)
    #expect(scan.status.issues == 0)
    #expect(scan.status.files == 1)
  }

  @Test func fullTranscriptWinsAndSurfaceIsPartOfEventIdentity() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try transcript(home, full: false, records: [request(home), request(home, index: 20)])
    for surface in ["antigravity", "antigravity-ide", "antigravity-cli"] {
      try transcript(home, surface: surface, records: [request(home)])
    }
    let first = try AntigravitySource.scan(home: home, catalog: [])
    let second = try AntigravitySource.scan(home: home, catalog: [])
    #expect(first.events.count == 3)
    #expect(Set(first.events.map(\.id)).count == 3)
    #expect(Set(first.events.map(\.group)).count == 3)
    #expect(first.events.map(\.id) == second.events.map(\.id))
    #expect(first.status.files == 3)
  }

  @Test func missingTimestampOrStepDoesNotInventEventMetadata() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    var noTime = request(home)
    noTime.removeValue(forKey: "created_at")
    var noIndex = request(home)
    noIndex.removeValue(forKey: "step_index")
    var invalidTime = request(home)
    invalidTime["created_at"] = "2026-10-01"
    try transcript(home, records: [noTime, noIndex, invalidTime])
    let scan = try AntigravitySource.scan(home: home, catalog: [])
    #expect(scan.events.isEmpty)
    #expect(scan.status.issues >= 3)
  }

  @Test func shortOnlyAndTruncatedOrMalformedFullRemainIncomplete() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try transcript(home, conversation: "short", full: false, records: [request(home)])
    var truncated = request(home)
    truncated["truncated_fields"] = ["tool_calls"]
    try transcript(home, conversation: "truncated", records: [truncated])
    try transcript(home, conversation: "tail", records: [], tail: "{\"step_index\":")
    let scan = try AntigravitySource.scan(home: home, catalog: [])
    #expect(scan.events.isEmpty)
    #expect(scan.status.issues >= 3)
  }

  @Test func rejectsSymlinkAndNonRegularTranscripts() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let file = try transcript(home, records: [request(home)])
    let outside = home.appendingPathComponent("outside.jsonl")
    try FileManager.default.moveItem(at: file, to: outside)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
    let directory = try transcript(home, conversation: "directory", records: [])
    try FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let scan = try AntigravitySource.scan(home: home, catalog: [])
    #expect(scan.events.isEmpty)
    #expect(scan.status.issues >= 2)
  }

  @Test func requiresTrustedSkillPathAndTypedSkillFlag() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    var record = request(home)
    record["tool_calls"] = [
      ["name": "view_file", "args": ["AbsolutePath": "/tmp/SKILL.md", "IsSkillFile": true]],
      [
        "name": "view_file",
        "args": [
          "AbsolutePath": "/project/.agents/skills/example/SKILL.md", "IsSkillFile": "true",
        ],
      ],
      [
        "name": "view_file",
        "args": [
          "AbsolutePath": "relative/.agents/skills/example/SKILL.md", "IsSkillFile": true,
        ],
      ],
    ]
    try transcript(home, records: [record])
    let scan = try AntigravitySource.scan(home: home, catalog: [])
    #expect(scan.events.isEmpty)
    #expect(scan.status.issues > 0)
  }

  @Test func resolvesCatalogWithoutCreatingAnInstalledSkill() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let skill = Skill(
      DiscoveredSkill(path: home.appendingPathComponent("custom/example").path, aliases: []),
      now: Date(timeIntervalSince1970: 0))
    var record = request(home)
    record["tool_calls"] = [
      [
        "name": "view_file",
        "args": [
          "AbsolutePath": skill.path + "/SKILL.md", "IsSkillFile": true,
        ],
      ]
    ]
    try transcript(home, records: [record])
    let scan = try AntigravitySource.scan(home: home, catalog: [skill])
    #expect(scan.events.count == 1)
    #expect(scan.events.first?.skillID == skill.id)
  }

  @Test func emptyFullTranscriptCannotEstablishCompleteCoverage() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    try transcript(home, records: [])
    let scan = try AntigravitySource.scan(home: home, catalog: [])
    #expect(scan.events.isEmpty)
    #expect(scan.status.issues > 0)
  }

  @Test func directoryPathCannotMasqueradeAsSkillFile() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    var record = request(home)
    record["tool_calls"] = [
      [
        "name": "view_file",
        "args": [
          "AbsolutePath": "/project/.agents/skills/example/SKILL.md/", "IsSkillFile": true,
        ],
      ]
    ]
    try transcript(home, records: [record])
    let scan = try AntigravitySource.scan(home: home, catalog: [])
    #expect(scan.events.isEmpty)
    #expect(scan.status.issues > 0)
  }

}
