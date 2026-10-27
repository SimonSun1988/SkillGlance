import Foundation

enum GeminiSource {
  static func scan(home: URL, catalog: [Skill]) throws -> ProviderScan {
    let root = home.appendingPathComponent(".gemini/tmp")
    var scan = ProviderScan(
      platform: .gemini, found: FileManager.default.fileExists(atPath: root.path))
    guard scan.status.requiredForAssessment == true else { return scan }
    let files = ["json", "jsonl"].flatMap { ImportCoordinator.files(root, extension: $0) }
      .filter {
        $0.deletingLastPathComponent().lastPathComponent == "chats"
          && $0.lastPathComponent.hasPrefix("session-")
      }
    var events: [String: UsageEvent] = [:]
    for file in files.sorted(by: { $0.path < $1.path }) {
      try Task.checkCancellation()
      do {
        let data = try ProviderFile.read(file)
        scan.status.files += 1
        scan.status.bytes += Int64(data.count)
        var metadata: [String: Any] = [:]
        var messages: [String: [String: Any]] = [:]
        var messageLines: [String: Int] = [:]
        func remember(_ record: [String: Any], line: Int) {
          guard let id = record["id"] as? String else {
            scan.issue()
            return
          }
          messages[id] = record
          messageLines[id] = line
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let records = object["messages"] as? [[String: Any]]
        {
          metadata = object
          for record in records { remember(record, line: 0) }
        } else {
          if data.last != 10 { scan.issue() }
          for (index, line) in data.split(separator: 10, omittingEmptySubsequences: false)
            .dropLast().enumerated() where !line.isEmpty
          {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else {
              scan.issue()
              continue
            }
            if let session = record["sessionId"] as? String {
              metadata["sessionId"] = session
              metadata["projectHash"] = record["projectHash"]
              if let directories = record["directories"] { metadata["directories"] = directories }
              if let records = record["messages"] as? [[String: Any]] {
                for message in records { remember(message, line: index + 1) }
              }
            } else if let values = record["$set"] as? [String: Any] {
              metadata.merge(values, uniquingKeysWith: { _, new in new })
              if let records = values["messages"] as? [[String: Any]] {
                for message in records { remember(message, line: index + 1) }
              }
            } else if let patch = record["$patch"] as? [String: Any] {
              var updates = patch["updates"] as? [[String: Any]] ?? []
              if patch["id"] != nil { updates.append(patch) }
              for update in updates {
                guard let id = update["id"] as? String, var message = messages[id] else {
                  scan.issue()
                  continue
                }
                if let changes = update["toolCalls"] as? [[String: Any]],
                  var calls = message["toolCalls"] as? [[String: Any]]
                {
                  for change in changes {
                    guard let callID = change["id"] as? String,
                      let position = calls.firstIndex(where: { $0["id"] as? String == callID })
                    else {
                      scan.issue()
                      continue
                    }
                    calls[position].merge(change, uniquingKeysWith: { _, new in new })
                  }
                  message["toolCalls"] = calls
                }
                messages[id] = message
              }
              // Rewinds/removals change the visible conversation, not the fact a tool ran.
            } else if record["$rewindTo"] != nil {
              continue
            } else if record["id"] != nil {
              remember(record, line: index + 1)
            } else {
              scan.issue()
            }
          }
        }
        guard let session = metadata["sessionId"] as? String, !session.isEmpty,
          let project = metadata["projectHash"] as? String, !project.isEmpty
        else {
          scan.issue()
          continue
        }
        let directories = metadata["directories"] as? [String] ?? []
        let cwd = directories.count == 1 && directories[0].hasPrefix("/") ? directories[0] : ""
        // The filename survives Gemini's sessionId updates on resume and JSON→JSONL migration.
        let identity = project + "|" + file.deletingPathExtension().lastPathComponent
        for (messageID, message) in messages where message["type"] as? String == "gemini" {
          for call in message["toolCalls"] as? [[String: Any]] ?? [] {
            guard let name = call["name"] as? String, let args = call["args"] as? [String: Any]
            else {
              scan.issue()
              continue
            }
            let target: String
            let evidence: Evidence
            if name == "activate_skill", let skill = args["name"] as? String {
              guard skill.count <= 256,
                skill.range(of: #"^[A-Za-z0-9_.:-]+$"#, options: .regularExpression) != nil
              else {
                scan.issue()
                continue
              }
              target = skill
              evidence = .invocation
            } else if name == "read_file", let path = args["file_path"] as? String,
              path.hasSuffix("/SKILL.md")
            {
              guard path.hasPrefix("/"), path.count <= 4096, !path.contains("\0"),
                !path.contains("\n")
              else {
                scan.issue()
                continue
              }
              target = path
              evidence = .read
            } else if name == "run_shell_command",
              (args["command"] as? String ?? "").contains("SKILL.md")
            {
              scan.issue("部分 Skill 讀取工具尚未支援")
              continue
            } else {
              if ProviderFile.referencesSkillFile(args) { scan.issue("部分 Skill 讀取工具尚未支援") }
              continue
            }
            guard let callID = call["id"] as? String, !callID.isEmpty,
              let time = Dates.parse(call["timestamp"] ?? message["timestamp"])
            else {
              scan.issue()
              continue
            }
            let state = call["status"] as? String
            let response = call["result"] as? [[String: Any]] ?? []
            let matching = response.compactMap { $0["functionResponse"] as? [String: Any] }
              .filter { $0["id"] as? String == callID }
              .compactMap { $0["response"] as? [String: Any] }
            let failed =
              state == "error" || state == "cancelled" || matching.contains { $0["error"] != nil }
            let outcome: Outcome = failed ? .failure : state == "success" ? .success : .unknown
            let nonempty = matching.contains { value in
              guard let output = value["output"] as? String else { return false }
              return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let confirmed = evidence == .read && outcome == .success && nonempty
            if outcome == .unknown || (evidence == .read && !confirmed && outcome != .failure) {
              scan.issue()
            }
            let id = stableID("gemini|\(identity)|\(callID)")
            let event = UsageEvent(
              id: id, platform: .gemini, session: session, group: identity,
              skillID: SkillIdentity.resolve(target, catalog: catalog), target: target, time: time,
              cwd: cwd, evidence: evidence, outcome: outcome, confirmed: confirmed,
              scope: evidence == .invocation
                ? "不適用" : args["limit"] == nil && args["offset"] == nil ? "完整" : "部分",
              source: file.path, line: messageLines[messageID] ?? 0)
            if let previous = events[id], previous.outcome != .unknown,
              event.outcome != .unknown, previous.outcome != event.outcome
            {
              var conflict = event
              conflict.outcome = .unknown
              conflict.confirmed = false
              conflict.conflicted = true
              events[id] = conflict
              scan.issue()
            } else if events[id]?.conflicted != true {
              if let previous = events[id],
                previous.outcome != .unknown
                  && (event.outcome == .unknown
                    || (previous.confirmed && !event.confirmed && previous.outcome == event.outcome))
              {
                continue
              }
              events[id] = event
            }
          }
        }
      } catch is CancellationError { throw CancellationError() } catch { scan.issue("部分來源檔案無法讀取") }
    }
    if scan.status.files == 0 { scan.issue("找不到可讀紀錄") }
    scan.events = Array(events.values)
    return scan
  }
}
