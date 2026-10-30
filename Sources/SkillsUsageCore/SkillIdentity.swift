import Foundation

public enum SkillIdentity {
  public static func resolve(_ target: String, catalog: [Skill]) -> String? {
    Index(catalog).resolve(target)
  }

  // Lookup tables over one catalog, so resolving many events does not rescan every Skill.
  public struct Index {
    private let catalog: [Skill]
    private var paths: [String: Set<Int>] = [:]
    private var aliases: [String: Set<Int>] = [:]
    private var names: [String: Set<Int>] = [:]
    private var aliasNames: [String: Set<Int>] = [:]

    public init(_ catalog: [Skill]) {
      self.catalog = catalog
      for (index, skill) in catalog.enumerated() {
        paths[skill.path, default: []].insert(index)
        names[skill.name, default: []].insert(index)
        if let declared = skill.declaredName { names[declared, default: []].insert(index) }
        for alias in skill.aliases {
          aliases[alias, default: []].insert(index)
          aliasNames[URL(fileURLWithPath: alias).lastPathComponent, default: []].insert(index)
        }
      }
    }

    // A target names one Skill only when exactly one catalog entry matches it.
    public func resolve(_ target: String) -> String? {
      let matches: Set<Int>
      if target.hasSuffix("/SKILL.md") {
        let path = URL(fileURLWithPath: target).deletingLastPathComponent().path
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        matches = paths[canonical, default: []].union(aliases[path, default: []])
      } else {
        let name = target.split(separator: ":").last.map(String.init) ?? target
        matches = names[target, default: []].union(names[name, default: []])
          .union(aliasNames[name, default: []])
      }
      return matches.count == 1 ? catalog[matches.first!].id : nil
    }
  }

  // A path target is named by its directory; a namespaced target `a:b` by `b`.
  public static func shortName(_ target: String) -> String {
    if URL(fileURLWithPath: target).lastPathComponent == "SKILL.md" {
      return URL(fileURLWithPath: target).deletingLastPathComponent().lastPathComponent
    }
    return target.split(separator: ":").last.map(String.init) ?? target
  }

  public static func names(_ skill: Skill) -> Set<String> {
    var names: Set<String> = [skill.name, URL(fileURLWithPath: skill.path).lastPathComponent]
    if let declared = skill.declaredName { names.insert(shortName(declared)) }
    for alias in skill.aliases { names.insert(URL(fileURLWithPath: alias).lastPathComponent) }
    return names
  }

  // Names of skills whose SKILL.md is mentioned in text that could not be parsed exactly.
  public static func mentionedNames(_ text: String) -> Set<String> {
    let range = NSRange(text.startIndex..., in: text)
    return Set(
      mentionPattern.matches(in: text, range: range).compactMap { match in
        Range(match.range(at: 1), in: text).map { shortName(String(text[$0])) }
      }.filter { !$0.isEmpty && $0 != "." && $0 != ".." })
  }

  private static let mentionPattern = try! NSRegularExpression(
    pattern: #"([A-Za-z0-9_.:-]+)/SKILL\.md"#)
}
