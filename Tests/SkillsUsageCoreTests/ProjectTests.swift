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
@Test func plainFolderIsItsOwnProjectUnlessAProjectRootContainsIt() throws {
  let root = try temporaryDirectory().resolvingSymlinksInPath()
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = root.appendingPathComponent("work/notes")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  #expect(ProjectResolver.resolve(folder.path, roots: [])?.repository == folder.path)
  #expect(ProjectResolver.resolve(folder.path, roots: [root.path])?.repository == root.path)
  #expect(ProjectResolver.resolve(root.appendingPathComponent("missing").path, roots: []) == nil)
  let home = FileManager.default.homeDirectoryForCurrentUser
  #expect(ProjectResolver.resolve(home.path, roots: []) == nil)
  #expect(ProjectResolver.resolve(home.appendingPathComponent("Library/Caches").path, roots: []) == nil)
  #expect(ProjectResolver.resolve("/", roots: []) == nil)
}
