import CryptoKit
import Foundation

public struct DiscoveredSkill: Sendable {
  public let path: String
  public var aliases: [String]
  public var declaredName: String? = nil
  public var name: String { URL(fileURLWithPath: path).lastPathComponent }
  public var managed: Bool {
    ([path] + aliases).contains {
      $0.contains("/plugins/") || $0.contains("/.system/")
        || $0.contains("/.cursor/skills-cursor/") || $0.contains("/.gemini/extensions/")
    }
  }
  public var cacheOnly: Bool {
    !(aliases.isEmpty) && aliases.allSatisfy { $0.contains("/plugins/cache/") }
  }
}
public enum SkillInventory {
  public static func scan(roots: [URL]) -> [DiscoveredSkill] {
    let fm = FileManager.default
    var found: [String: DiscoveredSkill] = [:]
    func walk(_ url: URL, _ depth: Int, _ ancestors: Set<String>) {
      guard depth < 9 else { return }
      let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
      guard !ancestors.contains(canonical) else { return }
      if fm.fileExists(atPath: url.appendingPathComponent("SKILL.md").path) {
        if found[canonical] == nil {
          found[canonical] = DiscoveredSkill(
            path: canonical, aliases: [], declaredName: declaredName(url))
        }
        if !found[canonical]!.aliases.contains(url.path) {
          found[canonical]!.aliases.append(url.path)
        }
        return
      }
      guard
        let children = try? fm.contentsOfDirectory(
          at: url, includingPropertiesForKeys: [.isDirectoryKey])
      else { return }
      for child in children
      where
        (try? child.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
        == true
      {
        walk(child, depth + 1, ancestors.union([canonical]))
      }
    }
    for root in roots { walk(root, 0, []) }
    return found.values.sorted { $0.path < $1.path }
  }

  private static func declaredName(_ directory: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: directory.appendingPathComponent("SKILL.md"))
    else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 8192),
      let text = String(data: data, encoding: .utf8)
    else { return nil }
    let lines = text.components(separatedBy: "\n")
    guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }
    for line in lines.dropFirst() {
      if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" { break }
      if line.hasPrefix("name:") {
        let name = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
          .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return name.range(of: #"^[A-Za-z0-9_.:-]{1,256}$"#, options: .regularExpression) != nil
          ? name : nil
      }
    }
    return nil
  }
}
public enum ReaderError: Error { case lineTooLarge }
public enum JSONLReader {
  public static func anchor(_ url: URL, offset: UInt64) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let length = Int(min(offset, 64))
    let prefix = try handle.read(upToCount: length) ?? Data()
    try handle.seek(toOffset: offset - UInt64(length))
    let suffix = try handle.read(upToCount: length) ?? Data()
    return SHA256.hash(data: prefix + suffix).map { String(format: "%02x", $0) }.joined()
  }
  @discardableResult public static func read(
    _ url: URL, offset: UInt64 = 0, consume: (Data, Int) throws -> Void
  ) throws -> UInt64 {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    try handle.seek(toOffset: offset)
    var pending = Data()
    var committed = offset
    var line = 0
    while let chunk = try handle.read(upToCount: 262144), !chunk.isEmpty {
      try Task.checkCancellation()
      pending.append(chunk)
      var start = pending.startIndex
      while let end = pending[start...].firstIndex(of: 10) {
        line += 1
        try autoreleasepool { try consume(Data(pending[start..<end]), line) }
        committed += UInt64(end - start + 1)
        start = end + 1
      }
      pending = Data(pending[start...])
      guard pending.count <= 32 * 1024 * 1024 else { throw ReaderError.lineTooLarge }
    }
    return committed
  }
}
public func stableID(_ value: String) -> String {
  SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}
