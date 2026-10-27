import Foundation
import Testing

@testable import SkillsUsageCore

@Test func storeSurvivesReopenWithoutStoringConversationText() async throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try UsageStore(directory: root)
  var snapshot = Snapshot()
  var skill = fixtureSkill()
  skill.important = true
  snapshot.skills = [skill]
  var checkpoint = Checkpoint()
  checkpoint.offset = 35
  try await store.save(snapshot, checkpoints: ["file": checkpoint])
  let reopened = try UsageStore(directory: root)
  #expect(try await reopened.load().skills.first?.important == true)
  #expect(try await reopened.checkpoints()["file"]?.offset == 35)
}
func usage(
  _ skill: Skill, at: Date, group: String, evidence: Evidence = .invocation,
  outcome: Outcome = .success
) -> UsageEvent {
  UsageEvent(
    id: UUID().uuidString, platform: .codex, session: UUID().uuidString, group: group,
    skillID: skill.id, target: skill.name, time: at, cwd: "", evidence: evidence, outcome: outcome,
    confirmed: evidence == .read && outcome == .success, scope: "完整", source: "file", line: 1)
}
@Test func metricsDeduplicateGroupsAndKeepReadSeparate() {
  let skill = fixtureSkill()
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  var snapshot = Snapshot()
  snapshot.skills = [skill]
  snapshot.events = [
    usage(skill, at: now, group: "a"), usage(skill, at: now, group: "a"),
    usage(skill, at: now, group: "b", evidence: .read),
    usage(skill, at: now, group: "c", outcome: .failure),
  ]
  let row = UsageMetrics.rows(snapshot, now: now).first
  #expect(row?.invocations == 3)
  #expect(row?.reads == 1)
  #expect(row?.conversations == 2)
  #expect(row?.days == 1)
  #expect(row?.failures == 1)
}
@Test func candidatesRequireNinetyDaysAndUnfilteredEvidence() {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  var skill = fixtureSkill()
  skill.observedAt = now.addingTimeInterval(-91 * 86400)
  var snapshot = Snapshot()
  snapshot.skills = [skill]
  snapshot.lastScan = now
  // Source formats have known unsupported operations; candidate decisions must stay conservative.
  snapshot.issues = ["unsupported source"]
  #expect(UsageMetrics.rows(snapshot, now: now).first?.candidate == false)
  snapshot.issues = []
  snapshot.sources = [
    SourceStatus(id: "codex", platform: .codex, files: 1, bytes: 100, issues: 0, message: "ready"),
    SourceStatus(
      id: "claude", platform: .claudeDesktop, files: 1, bytes: 100, issues: 0, message: "ready"),
  ]
  #expect(UsageMetrics.rows(snapshot, now: now).first?.candidate == true)
  snapshot.events = [usage(skill, at: now, group: "recent", outcome: .unknown)]
  #expect(
    UsageMetrics.rows(
      snapshot, since: now.addingTimeInterval(1), platform: .claudeDesktop, now: now
    ).first?.candidate == false)
}
@Test func partialImportBlocksCandidateEvenWithFreshPreviousScan() {
  let now = Date()
  var skill = fixtureSkill()
  skill.observedAt = now.addingTimeInterval(-91 * 86400)
  var snapshot = Snapshot()
  snapshot.skills = [skill]
  snapshot.lastScan = now
  snapshot.sources = [
    SourceStatus(id: "c", platform: .codex, files: 1, bytes: 1, issues: 0, message: ""),
    SourceStatus(id: "d", platform: .claudeDesktop, files: 1, bytes: 1, issues: 0, message: ""),
  ]
  snapshot.scanIncomplete = true
  #expect(UsageMetrics.rows(snapshot, now: now).first?.candidate == false)
}
@Test func overviewIncludesUnresolvedCallsWithoutDoubleCountingConversationUnion() {
  let skill = fixtureSkill()
  let now = Date()
  var one = usage(skill, at: now, group: "same")
  one.skillID = nil
  let two = usage(skill, at: now, group: "same", evidence: .read)
  let result = UsageMetrics.summary([one, two])
  #expect(result.invocations == 1)
  #expect(result.reads == 1)
  #expect(result.conversations == 1)
}

@Test func hourlySnapshotsRemainUsableUntilTheNextScanAndCompletionGraceExpire() {
  let now = Date()
  var skill = fixtureSkill()
  skill.observedAt = now.addingTimeInterval(-100 * 86400)
  var snapshot = Snapshot()
  snapshot.skills = [skill]
  snapshot.lastScan = now
  snapshot.sources = [
    SourceStatus(id: "c", platform: .codex, files: 1, bytes: 1, issues: 0, message: ""),
    SourceStatus(id: "d", platform: .claudeDesktop, files: 1, bytes: 1, issues: 0, message: ""),
  ]
  #expect(UsageMetrics.rows(snapshot, now: now.addingTimeInterval(3600)).first?.candidate == true)
  #expect(UsageMetrics.rows(snapshot, now: now.addingTimeInterval(3780)).first?.candidate == true)
  #expect(UsageMetrics.rows(snapshot, now: now.addingTimeInterval(3781)).first?.candidate == false)
}
