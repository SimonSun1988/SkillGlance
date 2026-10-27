import Foundation
import SkillsUsageCore

enum L10n {
  static let bundle: Bundle =
    Bundle.main.bundleIdentifier == "local.simonsun.skills-usage" ? .main : .module

  static func text(_ key: String, bundle: Bundle = L10n.bundle) -> String {
    bundle.localizedString(forKey: key, value: nil, table: nil)
  }

  static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: text(key), locale: .current, arguments: arguments)
  }

  // Stored diagnostics stay unchanged; translate only the known messages at presentation time.
  static func message(_ value: String, bundle: Bundle = L10n.bundle) -> String {
    for platform in Platform.allCases.map(\.label) {
      let messages: [(String, String)] = [
        ("紀錄輪替、截斷或改寫：\(platform)，觀察期已重設", "紀錄輪替、截斷或改寫：%@，觀察期已重設"),
        ("\(platform) 有無法解析的完整紀錄行", "%@ 有無法解析的完整紀錄行"),
        ("\(platform) 已匯入的來源檔案已不存在，保留舊摘要", "%@ 已匯入的來源檔案已不存在，保留舊摘要"),
      ]
      if let match = messages.first(where: { $0.0 == value }) {
        return String(format: text(match.1, bundle: bundle), locale: .current, platform)
      }
      let prefix = "\(platform) 部分檔案無法讀取（"
      if value.hasPrefix(prefix) && value.hasSuffix("）") {
        let errorType = String(value.dropFirst(prefix.count).dropLast())
        return String(
          format: text("%@ 部分檔案無法讀取（%@）", bundle: bundle), locale: .current,
          platform, errorType)
      }
    }
    return text(value, bundle: bundle)
  }
}
