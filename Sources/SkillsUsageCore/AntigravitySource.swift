import Foundation

enum AntigravitySource {
  private struct Record: Decodable {
    var stepIndex: Int?
    var type: String
    var status: String
    var createdAt: String?
    var toolCalls: [ToolCall]?
    var truncatedFields: [String]?

    enum CodingKeys: String, CodingKey {
      case type, status
      case stepIndex = "step_index"
      case createdAt = "created_at"
      case toolCalls = "tool_calls"
      case truncatedFields = "truncated_fields"
    }
  }

  private struct ToolCall: Decodable {
    var name: String
    var args: Arguments
  }

  private struct Arguments: Decodable {
    var absolutePath: String?
    var isSkillFile: Bool?

    enum CodingKeys: String, CodingKey {
      case absolutePath = "AbsolutePath"
      case isSkillFile = "IsSkillFile"
    }
  }

  static func scan(home: URL, catalog: [Skill]) throws -> ProviderScan {
    let manager = FileManager.default
    let surfaces = ["antigravity", "antigravity-ide", "antigravity-cli"]
    let gemini = home.appendingPathComponent(".gemini")
    let found = surfaces.contains {
      exists(gemini.appendingPathComponent("\($0)/brain"))
    }
    var scan = ProviderScan(platform: .antigravity, found: found)
    guard found else { return scan }
    guard directory(gemini) else {
      scan.issue()
      return scan
    }
    var eventIDs: Set<String> = []
    for surface in surfaces {
      let dataRoot = gemini.appendingPathComponent(surface)
      let brain = dataRoot.appendingPathComponent("brain")
      guard exists(brain) else { continue }
      guard directory(dataRoot), directory(brain) else {
        scan.issue()
        continue
      }
      let conversations: [URL]
      do {
        conversations = try manager.contentsOfDirectory(
          at: brain, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
      } catch {
        scan.issue()
        continue
      }
      for conversation in conversations {
        guard directory(conversation) else {
          scan.issue()
          continue
        }
        let system = conversation.appendingPathComponent(".system_generated")
        let logs = system.appendingPathComponent("logs")
        guard exists(system), exists(logs) else {
          scan.issue()
          continue
        }
        guard directory(system), directory(logs) else {
          scan.issue()
          continue
        }
        let full = logs.appendingPathComponent("transcript_full.jsonl")
        guard exists(full) else {
          if exists(logs.appendingPathComponent("transcript.jsonl")) {
            scan.issue("僅有截短紀錄，無法確認 Skill 讀取證據")
          } else {
            scan.issue()
          }
          continue
        }
        let data: Data
        do { data = try ProviderFile.read(full) } catch {
          scan.issue()
          continue
        }
        scan.status.files += 1
        scan.status.bytes += Int64(data.count)
        guard let text = String(data: data, encoding: .utf8),
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          scan.issue()
          continue
        }
        // A writer may still be appending the last record; never consume an unterminated tail.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if !data.isEmpty && data.last != 10 { scan.issue() }
        for (offset, line) in lines.dropLast().enumerated() {
          guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
          let record: Record
          do { record = try JSONDecoder().decode(Record.self, from: Data(line.utf8)) } catch {
            scan.issue()
            continue
          }
          if let truncated = record.truncatedFields, !truncated.isEmpty {
            scan.issue()
            if truncated.contains("tool_calls") { continue }
          }
          if record.status != "DONE" { scan.issue() }
          guard record.type == "PLANNER_RESPONSE", let calls = record.toolCalls else { continue }
          for (ordinal, call) in calls.enumerated() {
            guard call.name == "view_file", call.args.isSkillFile == true else { continue }
            guard let path = call.args.absolutePath, path.hasPrefix("/"),
              path.hasSuffix("/SKILL.md"),
              URL(fileURLWithPath: path).lastPathComponent == "SKILL.md",
              let step = record.stepIndex, step >= 0,
              let time = Dates.parse(record.createdAt)
            else {
              scan.issue()
              continue
            }
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            let skillID = SkillIdentity.resolve(normalized, catalog: catalog)
            guard skillID != nil || trusted(normalized, home: home) else {
              scan.issue()
              continue
            }
            let session = "\(surface):\(conversation.lastPathComponent)"
            let id = stableID("antigravity:\(session):\(step):\(ordinal)")
            guard eventIDs.insert(id).inserted else {
              scan.issue()
              continue
            }
            scan.events.append(
              UsageEvent(
                id: id, platform: .antigravity, session: session, group: session,
                skillID: skillID, target: normalized, time: time, cwd: "", project: nil,
                worktree: nil, evidence: .read, outcome: .unknown, confirmed: false,
                scope: "讀取請求，結果未能配對", source: full.path, line: offset + 1))
            // Transcript results have no tool-call ID; neighboring DONE records prove no pairing.
            scan.issue("已找到 Skill 讀取請求，結果未能配對")
          }
        }
      }
    }
    return scan
  }

  private static func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
      || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
  }

  private static func directory(_ url: URL) -> Bool {
    guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    else { return false }
    return values.isDirectory == true && values.isSymbolicLink != true
  }

  private static func trusted(_ path: String, home: URL) -> Bool {
    let roots = [
      ".gemini/config/skills", ".gemini/antigravity/skills", ".gemini/antigravity-cli/skills",
    ]
    for root in roots {
      let prefix = home.appendingPathComponent(root).standardizedFileURL.path + "/"
      if path.hasPrefix(prefix), path.dropFirst(prefix.count).split(separator: "/").count == 2 {
        return true
      }
    }
    let components = URL(fileURLWithPath: path).pathComponents
    if components.count >= 5 {
      let suffix = Array(components.suffix(4))
      if [".agents", ".agent"].contains(suffix[0]), suffix[1] == "skills" { return true }
    }
    let plugins =
      home.appendingPathComponent(".gemini/antigravity-cli/plugins")
      .standardizedFileURL.path + "/"
    if path.hasPrefix(plugins) {
      let suffix = path.dropFirst(plugins.count).split(separator: "/")
      return suffix.count == 4 && suffix[1] == "skills"
    }
    return false
  }
}
