import Foundation
import Testing

@testable import SkillsUsageApp
@testable import SkillsUsageCore

private func row(_ reason: String, candidate: Bool = false, lastUsed: Date? = nil) -> UsageRow {
  var row = UsageRow(
    skill: Skill(DiscoveredSkill(path: "/skills/example", aliases: []), now: Date()))
  row.reason = reason
  row.candidate = candidate
  row.lastUsed = lastUsed
  return row
}

@Test func assessmentStagesFollowTheRemovalReasons() {
  let now = Date()
  let cutoff = now.addingTimeInterval(-90 * 86400)
  #expect(AssessmentStage.of(row("完整觀察 90 天，無使用訊號", candidate: true), cutoff: cutoff) == .candidate)
  #expect(AssessmentStage.of(row("觀察未滿 90 天"), cutoff: cutoff) == .observing)
  // A Skill still under observation that was used recently is active, not waiting for removal.
  #expect(AssessmentStage.of(row("觀察未滿 90 天", lastUsed: now), cutoff: cutoff) == .active)
  #expect(AssessmentStage.of(row("近 90 天有使用或嘗試訊號"), cutoff: cutoff) == .active)
  #expect(AssessmentStage.of(row("可能屬於此 Skill 的紀錄尚無法確認，暫停評估"), cutoff: cutoff) == .paused)
  #expect(AssessmentStage.of(row("來源或證據不完整，暫停評估"), cutoff: cutoff) == .paused)
}
