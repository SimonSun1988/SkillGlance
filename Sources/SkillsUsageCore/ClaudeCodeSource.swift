import Foundation

enum ClaudeCodeSource {
  static func scan(home: URL, catalog: [Skill], desktopIDs: Set<String>) throws -> ProviderScan {
    let root = home.appendingPathComponent(".claude/projects")
    let present = FileManager.default.fileExists(atPath: root.path)
    var result = ProviderScan(platform: .claudeCode, found: present)
    var events: [String: UsageEvent] = [:]
    let files = ImportCoordinator.files(root, extension: "jsonl")
    if present && files.isEmpty { result.issue("找不到可讀紀錄") }
    for file in files {
      try Task.checkCancellation()
      if desktopIDs.contains(file.deletingPathExtension().lastPathComponent) { continue }
      do {
        let data = try ProviderFile.read(file)
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        var records: [(Int, [String: Any])] = []
        var malformed = 0
        for (index, line) in lines.dropLast().enumerated() where !line.isEmpty {
          if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
            records.append((index + 1, object))
          } else {
            malformed += 1
          }
        }
        if records.contains(where: { $0.1["entrypoint"] as? String == "claude-desktop" }) {
          continue
        }
        let child = file.deletingLastPathComponent().lastPathComponent == "subagents"
        let parent = file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        if child && desktopIDs.contains(parent)
          && !records.contains(where: { $0.1["entrypoint"] as? String == "cli" })
        {
          continue
        }
        result.status.files += 1
        result.status.bytes += Int64(data.count)
        result.status.requiredForAssessment = true
        result.status.message = "本機可讀紀錄"
        if malformed > 0 || data.last != 10 { result.issue() }
        var state = ParseState()
        if child {
          state.group = parent
        }
        for (line, record) in records {
          for event in LogParser.consume(
            record, platform: .claudeCode, source: file.path, line: line,
            state: &state, catalog: catalog)
          {
            guard event.time > Date(timeIntervalSince1970: 0) else {
              result.block([SkillIdentity.shortName(event.target)], at: nil)
              continue
            }
            if let old = events[event.id], old.outcome != .unknown && event.outcome == .unknown {
              continue
            }
            if let old = events[event.id], old.outcome != .unknown,
              event.outcome != .unknown, old.outcome != event.outcome
            {
              var conflict = event
              conflict.outcome = .unknown
              conflict.confirmed = false
              conflict.conflicted = true
              events[event.id] = conflict
              result.block([SkillIdentity.shortName(event.target)], at: event.time, "同一事件存在互相衝突的結果")
            } else if events[event.id]?.conflicted != true {
              events[event.id] = event
            }
          }
        }
        for (name, time) in state.blockedNames.merging(state.unconfirmedSource, uniquingKeysWith: max) {
          result.block([name], at: time)
        }
        if state.unparsedReads > 0 { result.note("部分提及 SKILL.md 的紀錄無法解析，且未指出特定 Skill") }
        result.handledFiles.insert(file.path)
      } catch is CancellationError { throw CancellationError() } catch {
        result.issue("部分來源檔案無法讀取")
      }
    }
    result.events = Array(events.values)
    if !files.isEmpty && result.status.files == 0 && result.status.issues == 0 {
      result.status.requiredForAssessment = false
      result.status.message = "尚未偵測到本機紀錄"
    }
    return result
  }
}
