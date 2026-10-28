import Foundation
import Testing

@testable import SkillsUsageCore

func fixtureSkill() -> Skill {
  Skill(
    DiscoveredSkill(path: "/skills/clean-code", aliases: ["/skills/clean-code"]),
    now: Date(timeIntervalSince1970: 0))
}
func parse(_ json: String) throws -> [String: Any] {
  try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

func skillContextRecord(_ path: String, id: String = "66666666-6666-4666-8666-666666666666")
  -> [String: Any]
{
  [
    "type": "user", "entrypoint": "claude-desktop", "sessionId": "context-session",
    "timestamp": "2026-10-27T01:00:00.000Z", "uuid": id, "isMeta": true,
    "message": [
      "role": "user",
      "content": [
        [
          "type": "text",
          "text":
            "Base directory for this skill: \(path)\n\n# Instructions\nUse these instructions for the task.",
        ]
      ],
    ],
  ]
}

@Test func userRequestedAndAIToolLoadedSkillsBothContributeUsage() throws {
  var state = ParseState()
  let skill = fixtureSkill()
  let command: [String: Any] = [
    "type": "user", "entrypoint": "claude-desktop", "sessionId": "context-session",
    "message": ["role": "user", "content": "<command-name>/clean-code</command-name>"],
  ]
  #expect(
    LogParser.consume(
      command, platform: .claudeDesktop, source: "f", line: 1,
      state: &state, catalog: [skill]
    ).isEmpty)
  var events = LogParser.consume(
    skillContextRecord(skill.path), platform: .claudeDesktop,
    source: "f", line: 2, state: &state, catalog: [skill])
  let call = try parse(
    #"{"entrypoint":"claude-desktop","message":{"content":[{"type":"tool_use","name":"Skill","id":"auto","input":{"skill":"clean-code"}}]}}"#
  )
  events += LogParser.consume(
    call, platform: .claudeDesktop, source: "f", line: 3, state: &state, catalog: [skill])
  let result = try parse(
    #"{"entrypoint":"claude-desktop","message":{"content":[{"type":"tool_result","tool_use_id":"auto","is_error":false,"content":"loaded"}]}}"#
  )
  events += LogParser.consume(
    result, platform: .claudeDesktop, source: "f", line: 4, state: &state, catalog: [skill])
  var automaticBody = skillContextRecord(skill.path, id: "77777777-7777-4777-8777-777777777777")
  automaticBody["sourceToolUseID"] = "auto"
  events += LogParser.consume(
    automaticBody, platform: .claudeDesktop, source: "f", line: 5,
    state: &state, catalog: [skill])
  let unique = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
  let summary = UsageMetrics.summary(Array(unique.values))
  #expect(summary.invocations == 1)
  #expect(summary.reads == 2)
  #expect(summary.conversations == 1)
  #expect(unique.values.filter { $0.scope == "上下文載入" }.allSatisfy { $0.skillID == skill.id })
}

@Test func skillContextRequiresProviderMetadataValidIDAndNonemptyInstructions() {
  let skill = fixtureSkill()
  let valid = skillContextRecord(skill.path)
  var typed = valid
  typed["isMeta"] = false
  var cli = valid
  cli["entrypoint"] = "cli"
  var invalidID = valid
  invalidID["uuid"] = "invalid"
  var empty = valid
  empty["message"] = [
    "role": "user",
    "content": [["type": "text", "text": "Base directory for this skill: \(skill.path)\n\n"]],
  ]
  var relative = valid
  relative["message"] = [
    "role": "user",
    "content": [
      ["type": "text", "text": "Base directory for this skill: relative/path\n\nInstructions"]
    ],
  ]
  for object in [typed, cli, invalidID, empty, relative] {
    var state = ParseState()
    #expect(
      LogParser.consume(
        object, platform: .claudeDesktop, source: "f", line: 1,
        state: &state, catalog: [skill]
      ).isEmpty)
  }
}

@Test func codexCountsReadsWithOrWithoutAUserSkillRequest() throws {
  for userRequested in [false, true] {
    var state = ParseState()
    if userRequested {
      let request = try parse(
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"$clean-code"}]}}"#
      )
      #expect(
        LogParser.consume(
          request, platform: .codex, source: "f", line: 1,
          state: &state, catalog: [fixtureSkill()]
        ).isEmpty)
    }
    let call = try parse(
      #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"read","arguments":"{\"cmd\":\"cat /skills/clean-code/SKILL.md\"}"}}"#
    )
    _ = LogParser.consume(
      call, platform: .codex, source: "f", line: 2, state: &state, catalog: [fixtureSkill()])
    let result = try parse(
      #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"read","output":"Process exited with code 0\nOutput:\n# Skill instructions"}}"#
    )
    let events = LogParser.consume(
      result, platform: .codex, source: "f", line: 3, state: &state, catalog: [fixtureSkill()])
    #expect(UsageMetrics.summary(events).reads == 1)
  }
}
@Test func desktopSkillCorrelatesFailureAndExcludesCLI() throws {
  var state = ParseState()
  let call = try parse(
    #"{"type":"assistant","sessionId":"s","entrypoint":"claude-desktop","timestamp":"2026-10-27T01:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Skill","id":"c","input":{"skill":"clean-code"}}]}}"#
  )
  let attempts = LogParser.consume(
    call, platform: .claudeDesktop, source: "file", line: 1, state: &state,
    catalog: [fixtureSkill()])
  #expect(attempts.count == 1)
  #expect(attempts.first?.outcome == .unknown)
  let result = try parse(
    #"{"type":"user","entrypoint":"claude-desktop","message":{"content":[{"type":"tool_result","tool_use_id":"c","is_error":true,"content":"failed"}]}}"#
  )
  let events = LogParser.consume(
    result, platform: .claudeDesktop, source: "file", line: 2, state: &state,
    catalog: [fixtureSkill()])
  #expect(events.first?.outcome == .failure)
  #expect(events.first?.id == attempts.first?.id)
  var cli = call
  cli["entrypoint"] = "cli"
  #expect(
    LogParser.consume(
      cli, platform: .claudeDesktop, source: "file", line: 3, state: &state,
      catalog: [fixtureSkill()]
    ).isEmpty)
}
@Test func codexReadNeedsReturnedContentAndMentionsDoNotCount() throws {
  var state = ParseState()
  let call: [String: Any] = [
    "timestamp": "2026-10-27T01:00:00.000Z", "type": "response_item",
    "payload": [
      "type": "function_call", "name": "exec_command", "call_id": "c",
      "arguments": #"{"cmd":"cat /skills/clean-code/SKILL.md"}"#,
    ],
  ]
  let attempt = LogParser.consume(
    call, platform: .codex, source: "file", line: 1, state: &state, catalog: [fixtureSkill()])
  #expect(attempt.count == 1)
  #expect(attempt.first?.confirmed == false)
  let result: [String: Any] = [
    "type": "response_item",
    "payload": [
      "type": "custom_tool_call_output", "call_id": "c",
      "output": "Process exited with code 0\nOutput:\n# Clean code\nUseful instructions",
    ],
  ]
  let loaded = LogParser.consume(
    result, platform: .codex, source: "file", line: 2, state: &state, catalog: [fixtureSkill()])
  #expect(loaded.first?.confirmed == true)
  let mention: [String: Any] = [
    "type": "response_item",
    "payload": [
      "type": "function_call", "name": "exec_command", "call_id": "m",
      "arguments": #"{"cmd":"rg SKILL.md /skills"}"#,
    ],
  ]
  #expect(
    LogParser.consume(
      mention, platform: .codex, source: "file", line: 3, state: &state, catalog: [fixtureSkill()]
    ).isEmpty)
}
@Test func desktopMetadataAloneDoesNotOverrideExplicitCLI() throws {
  var state = ParseState()
  state.desktop = true
  let call = try parse(
    #"{"entrypoint":"cli","message":{"content":[{"type":"tool_use","name":"Skill","id":"x","input":{"skill":"clean-code"}}]}}"#
  )
  #expect(
    LogParser.consume(
      call, platform: .claudeDesktop, source: "file", line: 1, state: &state,
      catalog: [fixtureSkill()]
    ).isEmpty)
}
@Test func completedWrapperWithEmptyOutputIsNotLoaded() throws {
  var state = ParseState()
  let call: [String: Any] = [
    "type": "response_item",
    "payload": [
      "type": "function_call", "name": "exec_command", "call_id": "empty",
      "arguments": #"{"cmd":"cat /skills/clean-code/SKILL.md"}"#,
    ],
  ]
  _ = LogParser.consume(
    call, platform: .codex, source: "file", line: 1, state: &state, catalog: [fixtureSkill()])
  let result: [String: Any] = [
    "type": "response_item",
    "payload": [
      "type": "function_call_output", "call_id": "empty", "output": #"{"exit_code":0,"output":""}"#,
    ],
  ]
  let events = LogParser.consume(
    result, platform: .codex, source: "file", line: 2, state: &state, catalog: [fixtureSkill()])
  #expect(events.first?.confirmed == false)
}
@Test func batchedReadCanConfirmEachReturnedInstructionAndMarksPartial() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let a = root.appendingPathComponent("a")
  let b = root.appendingPathComponent("b")
  for url in [a, b] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try
      ("# " + url.lastPathComponent + "\nA very long unique instruction for "
      + url.lastPathComponent
      + " that has enough characters for matching.\nAnother unique instruction for "
      + url.lastPathComponent + " that has enough characters for matching.").write(
        to: url.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
  }
  let skills = SkillInventory.scan(roots: [root]).map { Skill($0, now: Date()) }
  var state = ParseState()
  let command = "cat \(a.path)/SKILL.md && sed -n '1,4p' \(b.path)/SKILL.md"
  let args = String(
    data: try JSONSerialization.data(withJSONObject: ["cmd": command]), encoding: .utf8)!
  let call: [String: Any] = [
    "type": "response_item",
    "payload": [
      "type": "function_call", "name": "exec_command", "call_id": "batch", "arguments": args,
    ],
  ]
  let attempt = LogParser.consume(
    call, platform: .codex, source: "file", line: 1, state: &state, catalog: skills)
  #expect(attempt.count == 2)
  let output =
    try String(contentsOf: a.appendingPathComponent("SKILL.md"), encoding: .utf8)
    + String(contentsOf: b.appendingPathComponent("SKILL.md"), encoding: .utf8)
  let result: [String: Any] = [
    "type": "response_item",
    "payload": ["type": "function_call_output", "call_id": "batch", "output": output],
  ]
  let events = LogParser.consume(
    result, platform: .codex, source: "file", line: 2, state: &state, catalog: skills)
  #expect(events.filter(\.confirmed).count == 2)
  #expect(events.first { $0.target.contains("/b/") }?.scope == "部分")
}
@Test func unrelatedTrailingOutputDoesNotConfirmEmptySkill() throws {
  var state = ParseState()
  let args = #"{"cmd":"cat /skills/clean-code/SKILL.md; echo unrelated"}"#
  let call: [String: Any] = [
    "type": "response_item",
    "payload": [
      "type": "function_call", "name": "exec_command", "call_id": "unsafe", "arguments": args,
    ],
  ]
  _ = LogParser.consume(
    call, platform: .codex, source: "file", line: 1, state: &state, catalog: [fixtureSkill()])
  let result: [String: Any] = [
    "type": "response_item",
    "payload": [
      "type": "function_call_output", "call_id": "unsafe",
      "output": "Process exited with code 0\nOutput:\nunrelated",
    ],
  ]
  #expect(
    LogParser.consume(
      result, platform: .codex, source: "file", line: 2, state: &state, catalog: [fixtureSkill()]
    ).allSatisfy { !$0.confirmed })
}
@Test func delayedProcessResultUpdatesOriginalRead() throws {
  var state = ParseState()
  let call = try parse(
    #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"original","arguments":"{\"cmd\":\"cat /skills/clean-code/SKILL.md\"}"}}"#
  )
  let initial = LogParser.consume(
    call, platform: .codex, source: "file", line: 1, state: &state, catalog: [fixtureSkill()])
  _ = LogParser.consume(
    try parse(
      #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"original","output":"Process running with session ID 42"}}"#
    ), platform: .codex, source: "file", line: 2, state: &state, catalog: [fixtureSkill()])
  _ = LogParser.consume(
    try parse(
      #"{"type":"response_item","payload":{"type":"function_call","name":"write_stdin","call_id":"poll","arguments":"{\"session_id\":42,\"chars\":\"\"}"}}"#
    ), platform: .codex, source: "file", line: 3, state: &state, catalog: [fixtureSkill()])
  let final = LogParser.consume(
    try parse(
      #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"poll","output":"Process exited with code 0\nOutput:\n# Actual instructions"}}"#
    ), platform: .codex, source: "file", line: 4, state: &state, catalog: [fixtureSkill()])
  #expect(final.first?.id == initial.first?.id)
  #expect(final.first?.confirmed == true)
}
@Test func codexChildUsesKnownParentAndTurnContextCwd() throws {
  var state = ParseState()
  _ = LogParser.consume(
    try parse(
      #"{"type":"session_meta","payload":{"id":"child","cwd":"/old","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}"#
    ), platform: .codex, source: "file", line: 1, state: &state, catalog: [fixtureSkill()])
  _ = LogParser.consume(
    try parse(#"{"type":"turn_context","payload":{"cwd":"/new"}}"#), platform: .codex,
    source: "file", line: 2, state: &state, catalog: [fixtureSkill()])
  let call = try parse(
    #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"c","arguments":"{\"cmd\":\"cat /skills/clean-code/SKILL.md\"}"}}"#
  )
  let events = LogParser.consume(
    call, platform: .codex, source: "file", line: 3, state: &state, catalog: [fixtureSkill()])
  #expect(events.first?.group == "parent")
  #expect(events.first?.cwd == "/new")
}
@Test func literalMentionDoesNotBecomeUsage() throws {
  var state = ParseState()
  for command in [
    #"text({cmd:"cat /skills/clean-code/SKILL.md"})"#,
    #"text('tools.exec_command({cmd:"cat /skills/clean-code/SKILL.md"})')"#,
  ] {
    let call: [String: Any] = [
      "type": "response_item",
      "payload": [
        "type": "custom_tool_call", "name": "exec", "call_id": UUID().uuidString, "input": command,
      ],
    ]
    #expect(
      LogParser.consume(
        call, platform: .codex, source: "file", line: 1, state: &state, catalog: [fixtureSkill()]
      ).isEmpty)
  }
}
@Test func continuationRejectsArbitraryRecordedContent() throws {
  #expect(LogParser.continuationKey(["session_id": "PRIVATE_SENTINEL"]) == nil)
  #expect(LogParser.continuationKey(["session_id": ["private": "text"]]) == nil)
  #expect(LogParser.continuationKey(["cell_id": String(repeating: "x", count: 200)]) == nil)
  #expect(LogParser.continuationKey(["session_id": 42]) == "session:42")
}
@Test func unclassifiedClaudeSkillRaisesCoverageIssue() throws {
  var state = ParseState()
  let call = try parse(
    #"{"sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","id":"c","input":{"skill":"clean-code"}}]}}"#
  )
  #expect(
    LogParser.consume(
      call, platform: .claudeDesktop, source: "file", line: 1, state: &state,
      catalog: [fixtureSkill()]
    ).isEmpty)
  #expect(!state.coverageIssues.isEmpty)
}
@Test func isoDatesWithAndWithoutFractionsShareInstant() {
  #expect(Dates.parse("2026-10-27T01:00:00.000Z") == Dates.parse("2026-10-27T01:00:00Z"))
  #expect(Dates.parse("2026-10-27T01:00:00Z") != nil)
}
