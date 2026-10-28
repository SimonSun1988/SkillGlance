import Foundation

public enum Platform: String, Codable, Sendable, CaseIterable {
  case codex, claudeDesktop, claudeCode, gemini, antigravity, cursor
  public var label: String {
    switch self {
    case .codex: "Codex"
    case .claudeDesktop: "Claude Desktop"
    case .claudeCode: "Claude Code"
    case .gemini: "Gemini CLI"
    case .antigravity: "Antigravity"
    case .cursor: "Cursor"
    }
  }
}
public enum Evidence: String, Codable, Sendable { case invocation, read, context }
public enum Outcome: String, Codable, Sendable { case success, failure, unknown }
public struct Skill: Codable, Identifiable, Sendable, Hashable {
  public var id: String
  public var name: String
  public var declaredName: String? = nil
  public var path: String
  public var aliases: [String]
  public var managed: Bool
  public var cacheOnly: Bool
  public var installed: Bool
  public var important = false
  public var observedAt: Date
  public init(_ item: DiscoveredSkill, now: Date) {
    id = stableID(item.path)
    name = item.name
    declaredName = item.declaredName
    path = item.path
    aliases = item.aliases
    managed = item.managed
    cacheOnly = item.cacheOnly
    installed = true
    observedAt = now
  }
}
public struct UsageEvent: Codable, Identifiable, Sendable, Hashable {
  public var id: String
  public var platform: Platform
  public var session: String
  public var group: String
  public var skillID: String?
  public var target: String
  public var time: Date
  public var cwd: String
  public var project: String?
  public var worktree: String?
  public var evidence: Evidence
  public var outcome: Outcome
  public var confirmed: Bool
  public var conflicted: Bool?
  public var scope: String
  public var source: String
  public var line: Int
}
public struct PendingRead: Codable, Sendable {
  var requiresContentMatch: Bool? = nil
  var target: String
  var skillID: String?
  var evidence: Evidence
  var scope: String
  var time: Date
  var line: Int
  var cwd: String
}
public struct ParseState: Codable, Sendable {
  static let currentRevision = 1
  var parserRevision = currentRevision
  public var session = ""
  public var group = ""
  public var cwd = ""
  public var desktop = false
  var explicitCLI: Bool?
  public var coverageIssues: Set<String> = []
  var continuations: [String: String] = [:]
  var polls: [String: String] = [:]
  var pending: [String: [PendingRead]] = [:]
  public init() {}
  enum CodingKeys: String, CodingKey {
    case session, group, cwd, desktop, pending, coverageIssues, continuations, polls, explicitCLI,
      parserRevision
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    parserRevision = try c.decodeIfPresent(Int.self, forKey: .parserRevision) ?? 0
    session = try c.decodeIfPresent(String.self, forKey: .session) ?? ""
    group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
    cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
    desktop = try c.decodeIfPresent(Bool.self, forKey: .desktop) ?? false
    explicitCLI = try c.decodeIfPresent(Bool.self, forKey: .explicitCLI)
    pending = try c.decodeIfPresent([String: [PendingRead]].self, forKey: .pending) ?? [:]
    coverageIssues = try c.decodeIfPresent(Set<String>.self, forKey: .coverageIssues) ?? []
    continuations = try c.decodeIfPresent([String: String].self, forKey: .continuations) ?? [:]
    polls = try c.decodeIfPresent([String: String].self, forKey: .polls) ?? [:]
  }
}
public struct Checkpoint: Codable, Sendable {
  public var offset: UInt64 = 0
  public var line: Int = 0
  public var identity: String = ""
  public var anchor: String?
  public var state = ParseState()
  public init() {}
}
public struct SourceStatus: Codable, Identifiable, Sendable {
  public var id: String
  public var platform: Platform
  public var files: Int
  public var bytes: Int64
  public var issues: Int
  public var message: String
  // Missing on older snapshots: their existing sources remain required.
  public var requiredForAssessment: Bool? = nil
}
public struct Snapshot: Codable, Sendable {
  public var skills: [Skill] = []
  public var events: [UsageEvent] = []
  public var sources: [SourceStatus] = []
  public var scanIncomplete: Bool?
  public var lastScan: Date?
  public var issues: [String] = []
  public var projectRoots: [String] = []
  public var sourceCoverageRevision: Int? = nil
  public init() {}
}
public enum Dates {
  public static func parse(_ value: Any?) -> Date? {
    guard let value = value as? String else { return nil }
    return
      (try? Date(
        value,
        strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(
          separator: .colon)))
      ?? (try? Date(
        value,
        strategy: .iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(
          separator: .colon)))
  }
}
