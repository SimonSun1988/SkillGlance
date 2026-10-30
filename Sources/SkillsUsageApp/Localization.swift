import Foundation
import SkillsUsageCore

enum L10n {
  static let bundle: Bundle =
    Bundle.main.bundleIdentifier == "local.simonsun.skills-usage" ? .main : .module

  // Dates and numbers follow the language the strings resolved to, so a fallback to English
  // does not leave system-language dates inside English text.
  static let locale = locale(language: bundle.preferredLocalizations.first)

  static func locale(language: String?, current: Locale = .current) -> Locale {
    guard let language else { return current }
    let wanted = Locale.Language(identifier: Locale.Language(identifier: language).maximalIdentifier)
    let system = Locale.Language(identifier: current.language.maximalIdentifier)
    if wanted.languageCode == system.languageCode && wanted.script == system.script {
      return current
    }
    guard let region = current.region else { return Locale(identifier: language) }
    return Locale(identifier: "\(language)_\(region.identifier)")
  }

  static func text(_ key: String, bundle: Bundle = L10n.bundle) -> String {
    bundle.localizedString(forKey: key, value: nil, table: nil)
  }

  static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: text(key), locale: locale, arguments: arguments)
  }

  // Stored diagnostics stay unchanged; translate only the known messages at presentation time.
  static func message(_ value: String, bundle: Bundle = L10n.bundle) -> String {
    for platform in Platform.allCases.map(\.label) {
      let messages: [(String, String)] = [
        ("紀錄輪替、截斷或改寫：\(platform)，已重新讀取該檔案", "紀錄輪替、截斷或改寫：%@，已重新讀取該檔案"),
        ("\(platform) 有無法解析的完整紀錄行", "%@ 有無法解析的完整紀錄行"),
      ]
      if let match = messages.first(where: { $0.0 == value }) {
        return String(format: text(match.1, bundle: bundle), locale: locale, platform)
      }
      let prefix = "\(platform) 部分檔案無法讀取（"
      if value.hasPrefix(prefix) && value.hasSuffix("）") {
        let errorType = String(value.dropFirst(prefix.count).dropLast())
        return String(
          format: text("%@ 部分檔案無法讀取（%@）", bundle: bundle), locale: locale,
          platform, errorType)
      }
    }
    return text(value, bundle: bundle)
  }
}
