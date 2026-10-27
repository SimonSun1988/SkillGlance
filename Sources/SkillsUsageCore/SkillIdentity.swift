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
}
