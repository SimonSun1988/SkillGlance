import Foundation

public enum SkillIdentity {
  public static func resolve(_ target: String, catalog: [Skill]) -> String? {
    let path = URL(fileURLWithPath: target).deletingLastPathComponent().path
    let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    let name = target.split(separator: ":").last.map(String.init) ?? target
    let matches = catalog.filter { skill in
      if target.hasSuffix("/SKILL.md") {
        return skill.path == canonical || skill.aliases.contains(path)
      }
      return skill.name == target || skill.name == name || skill.declaredName == target
        || skill.declaredName == name
        || skill.aliases.contains { URL(fileURLWithPath: $0).lastPathComponent == name }
    }
    return matches.count == 1 ? matches[0].id : nil
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
