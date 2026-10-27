import Foundation

public struct ProjectLocation: Sendable, Equatable {
  public let repository: String
  public let worktree: String
}
public enum ProjectResolver {
  public static func resolve(_ cwd: String, roots: [String]) -> ProjectLocation? {
    guard cwd.hasPrefix("/") else { return nil }
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
      return nil
    }
    let current = URL(fileURLWithPath: cwd).standardizedFileURL
    var folder = current
    for _ in 0..<40 {
      let dotgit = folder.appendingPathComponent(".git")
      if fm.fileExists(atPath: dotgit.path, isDirectory: &isDirectory) {
        if isDirectory.boolValue {
          return ProjectLocation(repository: folder.path, worktree: folder.path)
        }
        guard let pointer = try? String(contentsOf: dotgit, encoding: .utf8),
          pointer.hasPrefix("gitdir:")
        else { return nil }
        let gitPath = pointer.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
        let admin = URL(fileURLWithPath: gitPath, relativeTo: folder).standardizedFileURL
        let common: URL
        if let text = try? String(
          contentsOf: admin.appendingPathComponent("commondir"), encoding: .utf8)
        {
          common =
            URL(
              fileURLWithPath: text.trimmingCharacters(in: .whitespacesAndNewlines),
              relativeTo: admin
            ).standardizedFileURL
        } else {
          common = admin
        }
        guard fm.fileExists(atPath: common.path), common.lastPathComponent == ".git" else {
          return nil
        }
        return ProjectLocation(
          repository: common.deletingLastPathComponent().path, worktree: folder.path)
      }
      let parent = folder.deletingLastPathComponent()
      if parent.path == folder.path { break }
      folder = parent
    }
    if let root = roots.sorted(by: { $0.count > $1.count }).first(where: {
      current.path == $0 || current.path.hasPrefix($0 + "/")
    }) {
      return ProjectLocation(repository: root, worktree: root)
    }
    return nil
  }
}
