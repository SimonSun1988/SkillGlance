import Foundation
import Testing

@testable import SkillsUsageApp

private let resources = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  .appendingPathComponent("Sources/SkillsUsageApp/Resources")

@Test func shippedLanguagesHaveCompleteMatchingCatalogs() throws {
  var catalogs: [[String: String]] = []
  for language in ["en", "zh-Hans", "zh-Hant"] {
    let url = resources.appendingPathComponent("\(language).lproj/Localizable.strings")
    #expect(FileManager.default.fileExists(atPath: url.path), "Missing \(language) catalog")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let data = try Data(contentsOf: url)
    let catalog = try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    #expect(catalog.count > 100)
    #expect(catalog.values.allSatisfy { !$0.isEmpty })
    catalogs.append(catalog)
  }
  #expect(Set(catalogs[0].keys) == Set(catalogs[1].keys))
  #expect(Set(catalogs[0].keys) == Set(catalogs[2].keys))
  let placeholder = try NSRegularExpression(pattern: "%(@|lld)")
  for key in catalogs[0].keys {
    let formats = catalogs.map { catalog in
      let value = catalog[key]!
      return placeholder.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
        (value as NSString).substring(with: $0.range)
      }
    }
    #expect(formats[0] == formats[1], "Simplified Chinese format mismatch: \(key)")
    #expect(formats[0] == formats[2], "Traditional Chinese format mismatch: \(key)")
  }
}

@Test func nativeLanguageMatchingSupportsRegionalChineseAndEnglishFallback() {
  let available = ["en", "zh-Hans", "zh-Hant"]
  for (preference, expected) in [
    ("zh-TW", "zh-Hant"), ("zh-HK", "zh-Hant"), ("zh-CN", "zh-Hans"),
    ("zh-SG", "zh-Hans"), ("en-GB", "en"), ("ja-JP", "en"),
  ] {
    #expect(
      Bundle.preferredLocalizations(from: available, forPreferences: [preference]).first == expected
    )
  }
}

@Test func dateLocaleFollowsTheResolvedStringLanguage() {
  let taiwan = Locale(identifier: "zh_TW")
  #expect(L10n.locale(language: "zh-Hant", current: taiwan) == taiwan)
  #expect(L10n.locale(language: "en", current: taiwan).identifier == "en_TW")
  #expect(L10n.locale(language: "zh-Hans", current: taiwan).identifier == "zh-Hans_TW")
  // A Japanese system falls back to English strings, so dates must not stay Japanese.
  let japan = Locale(identifier: "ja_JP")
  #expect(L10n.locale(language: "en", current: japan).language.languageCode == "en")
  #expect(L10n.locale(language: nil, current: japan) == japan)
}

@Test func storedDiagnosticsAreTranslatedWithoutTreatingPathsAsMessages() throws {
  let root = try #require(L10n.bundle.resourceURL)
  let english = try #require(Bundle(url: root.appendingPathComponent("en.lproj")))
  let simplified = try #require(Bundle(url: root.appendingPathComponent("zh-Hans.lproj")))
  let traditional = try #require(Bundle(url: root.appendingPathComponent("zh-Hant.lproj")))
  #expect(L10n.text("設定", bundle: english) == "Settings")
  #expect(L10n.text("設定", bundle: simplified) == "设置")
  #expect(L10n.text("設定", bundle: traditional) == "設定")
  #expect(L10n.message("保護中", bundle: english) == "Protected")
  #expect(
    L10n.message("Codex 有無法解析的完整紀錄行", bundle: english)
      == "Codex has complete log lines that could not be parsed.")
  #expect(
    L10n.message("Claude Desktop 部分檔案無法讀取（CocoaError）", bundle: english)
      == "Some Claude Desktop files could not be read (CocoaError).")
  #expect(
    L10n.message("紀錄輪替、截斷或改寫：Codex，觀察期已重設", bundle: simplified)
      == "记录轮替、截断或改写：Codex，观察期已重置")
  #expect(L10n.message("/tmp/保護中/SKILL.md", bundle: english) == "/tmp/保護中/SKILL.md")
}
