import Foundation
import Testing

@testable import SkillsUsageCore

@Test func supportedProvidersHaveStableStoredIdentifiers() {
  for name in ["codex", "claudeDesktop", "claudeCode", "gemini", "antigravity", "cursor"] {
    #expect(Platform(rawValue: name) != nil, "Missing provider: \(name)")
  }
}

@Test func conversationsFromDifferentToolsNeverCollapseTogether() {
  let skill = fixtureSkill()
  let first = usage(skill, at: Date(), group: "same-id")
  var second = first
  second.platform = .claudeDesktop
  second.id = "different-event"
  #expect(UsageMetrics.summary([first, second]).conversations == 2)
}
