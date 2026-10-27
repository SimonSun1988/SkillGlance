import Foundation

struct ProviderScan {
  var events: [UsageEvent] = []
  var handledFiles: Set<String> = []
  var status: SourceStatus

  init(platform: Platform, found: Bool) {
    status = SourceStatus(
      id: platform.rawValue, platform: platform, files: 0, bytes: 0, issues: 0,
      message: found ? "本機可讀紀錄" : "尚未偵測到本機紀錄",
      requiredForAssessment: found)
  }

  mutating func issue(_ message: String = "來源格式或證據不完整") {
    status.issues += 1
    status.message = message
    status.requiredForAssessment = true
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
