import Foundation

public struct UsageRow: Identifiable, Sendable {
  public let skill: Skill
  public var id: String { skill.id }
  public var invocations: Int = 0
  public var reads: Int = 0
  public var conversations: Int = 0
  public var days: Int = 0
  public var failures: Int = 0
  public var unknown: Int = 0
  public var lastUsed: Date?
  public var candidate = false
  public var reason = ""
}
public enum UsageMetrics {
  public static func rows(
    _ snapshot: Snapshot, since: Date = .distantPast, platform: Platform? = nil, now: Date = Date()
  ) -> [UsageRow] {
    let cutoff = now.addingTimeInterval(-90 * 86400)
    let grouped = Dictionary(grouping: snapshot.events, by: { $0.skillID ?? "unresolved" })
    let paused =
      snapshot.scanIncomplete == true || !snapshot.issues.isEmpty || !completeCoverage(snapshot)
      || snapshot.lastScan.map { now.timeIntervalSince($0) > ScanPolicy.maximumSnapshotAge } ?? true
    // Records that may belong to a skill but could not be attributed pause only that skill.
    let uncertain = Set(
      (snapshot.blockedNames ?? [:]).filter { $0.value >= cutoff }.keys
        + (grouped["unresolved"] ?? []).filter { $0.time >= cutoff }.map {
          SkillIdentity.shortName($0.target)
        })
    return snapshot.skills.map { skill in
      let all = grouped[skill.id] ?? []
      let visible = all.filter { $0.time >= since && (platform == nil || $0.platform == platform) }
      let active = visible.filter {
        ($0.evidence == .invocation && $0.outcome == .success)
          || ($0.evidence == .read && $0.confirmed)
      }
      var row = UsageRow(skill: skill)
      row.invocations = visible.filter { $0.evidence == .invocation }.count
      row.reads = visible.filter { $0.evidence == .read && $0.confirmed }.count
      row.conversations = Set(active.map { "\($0.platform.rawValue)|\($0.group)" }).count
      row.days = Set(active.map { Calendar.current.startOfDay(for: $0.time) }).count
      row.failures = visible.filter { $0.outcome == .failure && $0.evidence != .context }.count
      row.unknown = visible.filter { $0.outcome == .unknown && $0.evidence != .context }.count
      row.lastUsed = active.map(\.time).max()
      if skill.important || skill.managed {
        row.reason = "保護中"
      } else if !skill.installed || skill.cacheOnly {
        row.reason = "安裝狀態待確認"
      } else if skill.observedAt > cutoff {
        row.reason = "觀察未滿 90 天"
      } else if all.contains(where: { $0.time >= cutoff }) {
        row.reason = "近 90 天有使用或嘗試訊號"
      } else if paused {
        row.reason = "來源或證據不完整，暫停評估"
      } else if !uncertain.isDisjoint(with: SkillIdentity.names(skill)) {
        row.reason = "可能屬於此 Skill 的紀錄尚無法確認，暫停評估"
      } else {
        row.candidate = true
        row.reason = "完整觀察 90 天，無使用訊號"
      }
      return row
    }.sorted {
      if $0.conversations != $1.conversations { return $0.conversations > $1.conversations }
      if $0.days != $1.days { return $0.days > $1.days }
      if $0.lastUsed != $1.lastUsed {
        return ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast)
      }
      return $0.skill.name == $1.skill.name ? $0.id < $1.id : $0.skill.name < $1.skill.name
    }
  }

  private static func completeCoverage(_ snapshot: Snapshot) -> Bool {
    let expected: Set<Platform> =
      snapshot.sourceCoverageRevision == 1
      ? Set(Platform.allCases) : Set([.codex, .claudeDesktop])
    guard expected.isSubset(of: Set(snapshot.sources.map(\.platform))) else { return false }
    let required = snapshot.sources.filter { $0.requiredForAssessment != false }
    return !required.isEmpty && required.allSatisfy { $0.issues == 0 && $0.files > 0 }
  }
}
public struct UsageSummary: Sendable {
  public init() {}
  public init(invocations: Int, reads: Int, conversations: Int, activeSkills: Int) {
    self.invocations = invocations
    self.reads = reads
    self.conversations = conversations
    self.activeSkills = activeSkills
  }
  public var invocations = 0
  public var reads = 0
  public var conversations = 0
  public var activeSkills = 0
}
extension UsageMetrics {
  public static func summary(_ events: [UsageEvent]) -> UsageSummary {
    let active = events.filter {
      ($0.evidence == .invocation && $0.outcome == .success)
        || ($0.evidence == .read && $0.confirmed)
    }
    return UsageSummary(
      invocations: events.filter { $0.evidence == .invocation }.count,
      reads: events.filter { $0.evidence == .read && $0.confirmed }.count,
      conversations: Set(active.map { "\($0.platform.rawValue)|\($0.group)" }).count,
      activeSkills: Set(active.compactMap(\.skillID)).count)
  }
}
