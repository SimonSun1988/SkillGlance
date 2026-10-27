import Foundation
import Testing

@testable import SkillsUsageCore

@Test func linkedWorktreesShareRepositoryAndKeepIndividualTree() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let repo = root.appendingPathComponent("repo")
  let tree = root.appendingPathComponent("tree")
  let git = repo.appendingPathComponent(".git")
  let admin = git.appendingPathComponent("worktrees/tree")
  for url in [admin, tree.appendingPathComponent("src")] {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  try "gitdir: \(admin.path)\n".write(
    to: tree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
  try "../..\n".write(
    to: admin.appendingPathComponent("commondir"), atomically: true, encoding: .utf8)
  let first = ProjectResolver.resolve(repo.path, roots: [])
  let second = ProjectResolver.resolve(tree.appendingPathComponent("src").path, roots: [])
  #expect(first?.repository == repo.path)
  #expect(second?.repository == repo.path)
  #expect(second?.worktree == tree.path)
  #expect(ProjectResolver.resolve("/nonexistent-stale-project", roots: []) == nil)
}
@Test func plainFolderNeedsExplicitProjectRoot() throws {
  let root = try temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  #expect(ProjectResolver.resolve(root.path, roots: []) == nil)
  #expect(ProjectResolver.resolve(root.path, roots: [root.path])?.repository == root.path)
}
