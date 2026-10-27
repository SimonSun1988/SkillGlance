import CoreFoundation
import Foundation

public struct LogParser {
  public init() {}
  public mutating func consume(
    _ object: [String: Any], platform: Platform, source: String, line: Int, state: inout ParseState,
    catalog: [Skill]
  ) -> [UsageEvent] {
    guard [.codex, .claudeDesktop, .claudeCode].contains(platform) else { return [] }
    let payload = object["payload"] as? [String: Any] ?? object
    if object["type"] as? String == "session_meta" {
      state.session = payload["id"] as? String ?? payload["session_id"] as? String ?? state.session
      state.group = Self.parentSession(payload) ?? state.session
      state.cwd = payload["cwd"] as? String ?? state.cwd
    }
    if object["type"] as? String == "turn_context" {
      state.cwd = payload["cwd"] as? String ?? state.cwd
    }
    state.session = object["sessionId"] as? String ?? state.session
    if state.group.isEmpty {
      state.group = state.session.isEmpty ? stableID(source) : state.session
    }
    state.cwd = object["cwd"] as? String ?? state.cwd
    let time = Dates.parse(object["timestamp"]) ?? Date(timeIntervalSince1970: 0)
    var events: [UsageEvent] = []
    func resolve(_ target: String) -> String? { SkillIdentity.resolve(target, catalog: catalog) }
    func event(
      _ call: String, _ target: PendingRead, _ outcome: Outcome, _ confirmed: Bool, _ index: Int
    ) -> UsageEvent {
      UsageEvent(
        id: stableID(
          "\(platform.rawValue)|\(state.session.isEmpty ? source : state.session)|\(call)|\(index)"),
        platform: platform, session: state.session, group: state.group, skillID: target.skillID,
        target: target.target, time: target.time, cwd: target.cwd, evidence: target.evidence,
        outcome: outcome, confirmed: confirmed, scope: target.scope, source: source,
        line: target.line)
    }
    func remember(
      _ call: String, _ targets: [(String, Evidence, String)], requiresMatch: Bool = false
    ) {
      let targets = targets.filter { target in
        target.0.count <= 4096 && !target.0.contains("\n")
          && (target.1 == .read
            || target.0.range(of: #"^[A-Za-z0-9_./:-]+$"#, options: .regularExpression) != nil)
      }
      let pending = targets.map {
        PendingRead(
          requiresContentMatch: requiresMatch, target: $0.0, skillID: resolve($0.0), evidence: $0.1,
          scope: $0.2, time: time, line: line, cwd: state.cwd)
      }
      guard !pending.isEmpty else { return }
      state.pending[call] = pending
      events += pending.enumerated().map { event(call, $0.element, .unknown, false, $0.offset) }
    }
    func finish(_ call: String, _ content: String, _ outcome: Outcome) {
      guard let targets = state.pending.removeValue(forKey: call) else { return }
      let signatures = targets.map { target -> [String] in
        guard let skill = catalog.first(where: { $0.id == target.skillID }),
          let text = try? String(contentsOfFile: skill.path + "/SKILL.md", encoding: .utf8)
        else { return [] }
        return text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { $0.count > 48 }.prefix(8).map { $0 }
      }
      for (index, originalTarget) in targets.enumerated() {
        var target = originalTarget
        if target.evidence == .read
          && (content.contains("truncated") || content.contains("output truncated"))
        {
          target.scope = "部分"
        } else if target.requiresContentMatch == true && target.scope == "完整" {
          target.scope = "未知"
        }
        let unique = signatures[index].filter { snippet in
          !signatures.enumerated().contains { $0.offset != index && $0.element.contains(snippet) }
        }
        let matched = unique.filter { content.contains($0) }.count >= 2
        let effective = outcome == .failure ? Outcome.failure : matched ? .success : outcome
        let confirmed =
          target.evidence == .read && effective == .success
          && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && ((targets.count == 1 && target.requiresContentMatch != true) || matched)
        events.append(event(call, target, effective, confirmed, index))
      }
    }
    if platform == .claudeDesktop || platform == .claudeCode {
      if let entry = object["entrypoint"] as? String {
        state.desktop = entry == "claude-desktop"
        state.explicitCLI = entry != "claude-desktop"
      }
      guard platform == .claudeDesktop ? state.desktop : !state.desktop else {
        if state.explicitCLI != true {
          let blocks = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
          if object["attributionSkill"] != nil
            || blocks.contains(where: { block in
              block["name"] as? String == "Skill"
                || ((block["input"] as? [String: Any])?["file_path"] as? String ?? "").hasSuffix(
                  "/SKILL.md")
            })
          {
            state.coverageIssues.insert("Claude 紀錄來源未確認")
          }
        }
        return []
      }
      let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
      if object["type"] as? String == "user", object["isMeta"] as? Bool == true,
        let rawID = object["uuid"] as? String, let uuid = UUID(uuidString: rawID),
        let message = object["message"] as? [String: Any], message["role"] as? String == "user",
        let path = Self.contextSkillPath(Self.text(message["content"]))
      {
        let target = PendingRead(
          target: path, skillID: resolve(path), evidence: .read, scope: "上下文載入",
          time: time, line: line, cwd: state.cwd)
        events.append(
          event("skill-context:\(uuid.uuidString.lowercased())", target, .success, true, 0))
      }
      for block in content {
        if block["type"] as? String == "tool_use", let call = block["id"] as? String,
          let input = block["input"] as? [String: Any]
        {
          switch block["name"] as? String {
          case "Skill":
            if let target = input["skill"] as? String {
              remember(call, [(target, .invocation, "不適用")])
            }
          case "Read":
            if let path = input["file_path"] as? String, path.hasSuffix("/SKILL.md") {
              remember(
                call, [(path, .read, input["limit"] == nil && input["offset"] == nil ? "完整" : "部分")]
              )
            }
          case "Bash":
            let command = input["command"] as? String ?? ""
            let targets = Self.readTargets(command)
            remember(call, targets.map { ($0.0, .read, $0.1) })
            if command.contains("SKILL.md") && targets.isEmpty {
              state.coverageIssues.insert("無法解析部分讀取指令")
            }
          default: break
          }
        } else if block["type"] as? String == "tool_result",
          let call = block["tool_use_id"] as? String
        {
          let text = Self.text(block["content"])
          let error = block["is_error"] as? Bool
          finish(call, text, error == true ? .failure : .success)
        }
      }
      if let skill = object["attributionSkill"] as? String, skill.count <= 256,
        skill.range(of: #"^[A-Za-z0-9_./:-]+$"#, options: .regularExpression) != nil
      {
        let target = PendingRead(
          target: skill, skillID: resolve(skill), evidence: .context, scope: "歸屬訊號", time: time,
          line: line, cwd: state.cwd)
        events.append(event("context:\(line)", target, .unknown, false, 0))
      }
    } else {
      let type = payload["type"] as? String ?? ""
      if type == "function_call" || type == "custom_tool_call",
        let call = payload["call_id"] as? String
      {
        let name = payload["name"] as? String ?? ""
        if name == "write_stdin" || name == "wait", let raw = payload["arguments"] as? String,
          let args = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        {
          if let key = Self.continuationKey(args), let original = state.continuations[key] {
            state.polls[call] = original
          }
        }
        var targets: [(String, String)] = []
        var wrapped = false
        if name == "exec_command" || name == "shell_command" {
          if let raw = payload["arguments"] as? String,
            let args = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
          {
            let command = args["cmd"] as? String ?? args["command"] as? String ?? ""
            targets = Self.readTargets(command)
            if command.contains("SKILL.md") && targets.isEmpty {
              state.coverageIssues.insert("無法解析部分讀取指令")
            }
          }
        } else if name == "exec" {
          wrapped = true
          let rawPoll = payload["input"] as? String ?? ""
          if let key = Self.wrappedPollKey(rawPoll), let original = state.continuations[key] {
            state.polls[call] = original
          }
          let raw = payload["input"] as? String ?? payload["arguments"] as? String ?? ""
          for command in Self.wrappedCommands(raw) {
            let reads = Self.readTargets(command)
            targets += reads
            if command.contains("SKILL.md") && reads.isEmpty {
              state.coverageIssues.insert("無法解析部分讀取指令")
            }
          }
          if raw.contains("SKILL.md") && targets.isEmpty {
            state.coverageIssues.insert("部分工具封裝不在支援範圍")
          }
        }
        if !["exec_command", "shell_command", "exec", "write_stdin", "wait"].contains(name),
          (payload["arguments"] as? String ?? "").contains("SKILL.md")
        {
          state.coverageIssues.insert("未支援的相關讀取工具")
        }
        remember(call, targets.map { ($0.0, .read, $0.1) }, requiresMatch: wrapped)
      } else if type == "function_call_output" || type == "custom_tool_call_output",
        let call = payload["call_id"] as? String
      {
        let output = Self.text(payload["output"])
        let original = state.polls.removeValue(forKey: call) ?? call
        if let running = Self.runningKey(output), state.pending[original] != nil {
          state.continuations[running] = original
        } else {
          let result = Self.commandResult(output)
          finish(original, result.0, result.1)
          state.continuations = state.continuations.filter { $0.value != original }
        }
      }
    }
    return events
  }
  static func contextSkillPath(_ text: String) -> String? {
    let prefix = "Base directory for this skill: "
    let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].hasPrefix(prefix),
      !parts[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    let directory = parts[0].dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    guard directory.hasPrefix("/"), directory.count <= 4096, !directory.contains("\0") else {
      return nil
    }
    return URL(fileURLWithPath: directory).appendingPathComponent("SKILL.md").path
  }
  static func text(_ value: Any?) -> String {
    if let value = value as? String { return value }
    if let values = value as? [[String: Any]] {
      return values.compactMap { $0["text"] as? String ?? $0["content"] as? String }.joined(
        separator: "\n")
    }
    return ""
  }
  static func parentSession(_ object: [String: Any]) -> String? {
    if let parent = object["parent_thread_id"] as? String { return parent }
    for key in ["source", "subagent", "thread_spawn"] {
      if let child = object[key] as? [String: Any], let parent = parentSession(child) {
        return parent
      }
    }
    return nil
  }
  static func continuationKey(_ object: [String: Any]) -> String? {
    if let cell = object["cell_id"] as? String,
      cell.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil
    {
      return "cell:" + cell
    }
    if let number = object["session_id"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      number.doubleValue > 0, number.doubleValue == Double(number.int64Value)
    {
      return "session:\(number.int64Value)"
    }
    if let text = object["session_id"] as? String, text.count <= 18, let number = Int64(text),
      number > 0
    {
      return "session:\(number)"
    }
    return nil
  }
  static func runningKey(_ output: String) -> String? {
    for (pattern, prefix) in [
      (#"Script running with cell ID ([A-Za-z0-9_-]+)"#, "cell:"),
      (#"Process running with session ID (\d+)"#, "session:"),
    ] {
      if let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
        let range = Range(match.range(at: 1), in: output)
      {
        return continuationKey(
          prefix == "cell:"
            ? ["cell_id": String(output[range])] : ["session_id": String(output[range])])
      }
    }
    if let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
      object["exit_code"] == nil
    {
      return continuationKey(object)
    }
    return nil
  }
  static func wrappedPollKey(_ source: String) -> String? {
    let pattern =
      #"^\s*(?:text\(await\s+|(?:const|let|var)\s+\w+\s*=\s*await\s+|await\s+)tools\.(?:write_stdin|wait)\(\{\s*(session_id|cell_id)\s*:\s*(\d+|"[A-Za-z0-9_-]+")"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
      let keyRange = Range(match.range(at: 1), in: source),
      let valueRange = Range(match.range(at: 2), in: source)
    else { return nil }
    return continuationKey([
      String(source[keyRange]): source[valueRange].trimmingCharacters(
        in: CharacterSet(charactersIn: "\""))
    ])
  }
  static func commandResult(_ output: String) -> (String, Outcome) {
    var body = output
    var outcome = Outcome.unknown
    if let regex = try? NSRegularExpression(pattern: #"(?m)^Process exited with code (\d+)\s*$"#),
      let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
      let range = Range(match.range(at: 1), in: output)
    {
      outcome = output[range] == "0" ? .success : .failure
    }
    if let range = output.range(of: "Output:\n") { body = String(output[range.upperBound...]) }
    if let data = body.data(using: .utf8),
      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let code = value["exit_code"] as? Int
    {
      return (value["output"] as? String ?? "", code == 0 ? .success : .failure)
    }
    if body.localizedCaseInsensitiveContains("no such file")
      || body.localizedCaseInsensitiveContains("permission denied")
    {
      outcome = .failure
    }
    return (body, outcome)
  }
  static func wrappedCommands(_ source: String) -> [String] {
    // Inspect literal tool calls outside JS strings/comments; never execute recorded JavaScript.
    let chars = Array(source)
    var i = 0
    var commands: [String] = []
    func skipString(_ start: Int) -> Int {
      let quote = chars[start]
      var cursor = start + 1
      while cursor < chars.count {
        if chars[cursor] == "\\" {
          cursor += 2
          continue
        }
        if chars[cursor] == quote { return cursor + 1 }
        cursor += 1
      }
      return chars.count
    }
    while i < chars.count {
      if chars[i] == "\"" || chars[i] == "'" || chars[i] == "`" {
        i = skipString(i)
        continue
      }
      if i + 1 < chars.count && chars[i] == "/" && chars[i + 1] == "/" {
        while i < chars.count && chars[i] != "\n" { i += 1 }
        continue
      }
      if i + 1 < chars.count && chars[i] == "/" && chars[i + 1] == "*" {
        i += 2
        while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
        i += 2
        continue
      }
      let prefix = String(chars[i..<min(i + 21, chars.count)])
      if prefix.hasPrefix("tools.exec_command(") || prefix.hasPrefix("tools.shell_command(") {
        let tail = String(chars[i...])
        guard let brace = tail.firstIndex(of: "{") else {
          i += 1
          continue
        }
        let object = String(tail[brace...])
        let pattern = #"^\{\s*(?:cmd|command)\s*:\s*("(?:\\.|[^"\\])*")"#
        if let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(
            in: object, range: NSRange(object.startIndex..., in: object)),
          let range = Range(match.range(at: 1), in: object),
          let command = try? JSONSerialization.jsonObject(
            with: Data(object[range].utf8), options: [.fragmentsAllowed]) as? String
        {
          commands.append(command)
        }
      }
      i += 1
    }
    return commands
  }
  static func readTargets(_ command: String) -> [(String, String)] {
    guard !command.contains("<<"), !command.contains("`"), !command.contains("$") else { return [] }
    var segments: [[String]] = []
    var tokens: [String] = []
    var token = ""
    var quote: Character?
    var escaped = false
    for char in command {
      if escaped {
        token.append(char)
        escaped = false
        continue
      }
      if char == "\\" && quote != "'" {
        escaped = true
        continue
      }
      if let active = quote {
        if char == active { quote = nil } else { token.append(char) }
        continue
      }
      if char == "'" || char == "\"" {
        quote = char
        continue
      }
      if char == "|" || char == ">" || char == "<" { return [] }
      if char == ";" || char == "&" || char == "\n" {
        if !token.isEmpty {
          tokens.append(token)
          token = ""
        }
        if !tokens.isEmpty {
          segments.append(tokens)
          tokens = []
        }
        continue
      }
      if char.isWhitespace {
        if !token.isEmpty {
          tokens.append(token)
          token = ""
        }
      } else {
        token.append(char)
      }
    }
    guard quote == nil, !escaped else { return [] }
    if !token.isEmpty { tokens.append(token) }
    if !tokens.isEmpty { segments.append(tokens) }
    var result: [(String, String)] = []
    for words in segments {
      guard let program = words.first, ["cat", "head", "sed"].contains(program) else { return [] }
      var files = Array(words.dropFirst())
      var scope = "完整"
      if program == "sed" {
        guard files.count == 3, files[0] == "-n", files[1].hasSuffix("p") else { return [] }
        files = [files[2]]
        scope = "部分"
      }
      if program == "head" {
        scope = "部分"
        if files.count == 3 && files[0] == "-n" && Int(files[1]) != nil { files = [files[2]] }
      }
      // Single literal file only: a combined cat could return unrelated content from another file.
      guard files.count == 1, let path = files.first, path.hasPrefix("/"),
        path.hasSuffix("/SKILL.md")
      else { return [] }
      result.append((path, scope))
    }
    return result
  }
}
