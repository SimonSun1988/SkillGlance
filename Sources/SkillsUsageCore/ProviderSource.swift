import Foundation

struct ProviderScan {
  var events: [UsageEvent] = []
  var handledFiles: Set<String> = []
  var blockedNames: [String: Date] = [:]
  var notices: [String] = []
  var status: SourceStatus

  init(platform: Platform, found: Bool) {
    status = SourceStatus(
      id: platform.rawValue, platform: platform, files: 0, bytes: 0, issues: 0,
      message: found ? "本機可讀紀錄" : "尚未偵測到本機紀錄",
      requiredForAssessment: found)
  }

  // A source-level failure: it pauses every removal assessment.
  mutating func issue(_ message: String = "來源格式或證據不完整") {
    status.issues += 1
    status.message = message
    status.requiredForAssessment = true
  }

  // A record about known skills that could not be confirmed: it pauses only those skills.
  mutating func block(
    _ names: some Sequence<String>, at time: Date?, _ message: String = "部分 Skill 紀錄尚無法確認"
  ) {
    let time = time ?? Date()
    for name in names where !name.isEmpty {
      blockedNames[name] = max(blockedNames[name] ?? .distantPast, time)
    }
    note(message)
  }

  // A skill-related record without a known target: block what it names, otherwise only note it.
  mutating func unresolved(_ value: Any?, at time: Date?, _ message: String = "部分 Skill 讀取工具尚未支援") {
    guard ProviderFile.referencesSkillFile(value) else { return }
    let names = ProviderFile.skillNames(value)
    names.isEmpty ? note("部分提及 SKILL.md 的紀錄無法解析，且未指出特定 Skill") : block(names, at: time, message)
  }

  mutating func note(_ message: String) {
    if !notices.contains(message) { notices.append(message) }
  }
}

enum ProviderFile {
  static let maximumBytes = 64 * 1024 * 1024

  static func referencesSkillFile(_ value: Any?, depth: Int = 0) -> Bool {
    guard depth < 16 else { return true }
    if let text = value as? String { return text.contains("SKILL.md") }
    if let values = value as? [String: Any] {
      return values.values.contains { referencesSkillFile($0, depth: depth + 1) }
    }
    if let values = value as? [Any] {
      return values.contains { referencesSkillFile($0, depth: depth + 1) }
    }
    return false
  }

  static func skillNames(_ value: Any?, depth: Int = 0) -> Set<String> {
    guard depth < 16 else { return [] }
    if let text = value as? String { return SkillIdentity.mentionedNames(text) }
    if let values = value as? [String: Any] {
      return values.values.reduce(into: []) { $0.formUnion(skillNames($1, depth: depth + 1)) }
    }
    if let values = value as? [Any] {
      return values.reduce(into: []) { $0.formUnion(skillNames($1, depth: depth + 1)) }
    }
    return []
  }

  static func read(_ url: URL) throws -> Data {
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size <= maximumBytes
    else { throw StoreError(message: "來源檔案類型或大小不受支援") }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    guard data.count <= maximumBytes else { throw StoreError(message: "來源檔案過大") }
    return data
  }
}
