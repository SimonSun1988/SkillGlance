import AppKit
import ServiceManagement
import SkillsUsageCore
import SwiftUI

@MainActor final class AppModel: ObservableObject {
  @Published var snapshot = Snapshot() { didSet { updateRows() } }
  @Published private(set) var rows: [UsageRow] = []
  @Published private(set) var summary = UsageSummary()
  @Published private(set) var menuSummary = UsageSummary()
  @Published var catalogScope = "all" { didSet { updateRows() } }
  @Published private(set) var menuRows: [UsageRow] = []
  @Published private(set) var candidateCount = 0
  // User-installed Skills over the fixed 90-day removal window, independent of filters.
  @Published private(set) var userSkills = 0
  @Published private(set) var unusedUserSkills = 0
  // User-installed Skills that removal assessment applies to, with untranslated reasons.
  @Published private(set) var assessment: [UsageRow] = []
  @Published var scanning = false { didSet { updateRows() } }
  @Published var automaticUpdatesPaused = false
  @Published var progress = 0.0
  @Published var progressText = L10n.text("準備匯入")
  @Published var error: String?
  @Published var page: Page = .skills { didSet { updateRows() } }
  @Published var search = "" { didSet { updateRows() } }
  @Published var days = 90 { didSet { updateRows() } }
  @Published var platform: Platform? { didSet { updateRows() } }
  @Published var project = "" { didSet { updateRows() } }
  @Published var worktree = "" { didSet { updateRows() } }
  @Published var selection: String?
  @Published var showDetail = false
  @Published private(set) var loginStatus = SMAppService.mainApp.status
  var loginRequested: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
  private var scanTask: Task<Void, Never>?
  private var monitor: Task<Void, Never>?
  let directory: URL
  private let store: UsageStore?
  private let importer: ImportCoordinator?
  init() {
    directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SkillsUsage")
    do {
      let store = try UsageStore(directory: directory)
      self.store = store
      importer = ImportCoordinator(store: store)
    } catch {
      store = nil
      importer = nil
      self.error = error.localizedDescription
    }
    Task {
      do { if let store { snapshot = try await store.load() } } catch {
        self.error = error.localizedDescription
      }
      refresh()
    }
  }
  private func updateRows() {
    let since = days == 0 ? Date.distantPast : Date().addingTimeInterval(-Double(days) * 86400)
    var filtered = snapshot
    if !project.isEmpty {
      filtered.events = snapshot.events.filter {
        project == "__unassigned" ? $0.project == nil : $0.project == project
      }
    }
    if !worktree.isEmpty { filtered.events = filtered.events.filter { $0.worktree == worktree } }
    // Candidate eligibility always comes from the complete snapshot, independent of filters.
    let complete = UsageMetrics.rows(snapshot)
    let eligibility = Dictionary(
      uniqueKeysWithValues: complete.map { ($0.id, ($0.candidate, $0.reason)) })
    assessment = complete.filter {
      $0.skill.installed && !$0.skill.managed && !$0.skill.cacheOnly && !$0.skill.important
    }.map { row in
      var row = row
      row.candidate = row.candidate && !scanning
      return row
    }
    let menuEvents = snapshot.events.filter { $0.time >= Date().addingTimeInterval(-90 * 86400) }
    menuSummary = UsageMetrics.summary(menuEvents)
    summary = UsageMetrics.summary(
      filtered.events.filter { $0.time >= since && (platform == nil || $0.platform == platform) })
    menuRows = UsageMetrics.rows(snapshot, since: Date().addingTimeInterval(-90 * 86400))
    let user = menuRows.filter { $0.skill.installed && !$0.skill.managed && !$0.skill.cacheOnly }
    userSkills = user.count
    unusedUserSkills = user.filter { $0.conversations == 0 }.count
    candidateCount = scanning ? 0 : eligibility.values.filter(\.0).count
    rows = UsageMetrics.rows(filtered, since: since, platform: platform).map { row in
      var row = row
      row.candidate = !scanning && (eligibility[row.id]?.0 ?? false)
      row.reason = L10n.message(scanning ? "掃描中，暫停評估" : eligibility[row.id]?.1 ?? "")
      return row
    }.filter { row in
      (catalogScope == "all"
        || (catalogScope == "installed" && row.skill.installed && !row.skill.cacheOnly)
        || (catalogScope == "history" && !row.skill.installed)
        || (catalogScope == "cache" && row.skill.cacheOnly))
        && (search.isEmpty || row.skill.name.localizedCaseInsensitiveContains(search))
        && (page != .protected || row.skill.important || row.skill.managed)
        && (page != .candidates || row.candidate)
    }
  }
  var selected: UsageRow? {
    guard let row = rows.first(where: { $0.id == selection })
      ?? assessment.first(where: { $0.id == selection })
    else { return nil }
    var shown = row
    shown.reason = L10n.message(row.reason)
    return shown
  }
  var projects: [String] { Set(snapshot.events.compactMap(\.project)).sorted() }
  var worktrees: [String] {
    Set(snapshot.events.filter { project.isEmpty || $0.project == project }.compactMap(\.worktree))
      .sorted()
  }
  func refresh(rebuild: Bool = false) {
    guard !scanning, let importer else { return }
    monitor?.cancel()
    automaticUpdatesPaused = false
    scanning = true
    progress = 0
    scanTask = Task {
      do {
        snapshot = try await importer.scan(rebuild: rebuild) { [weak self] text, value in
          await self?.updateProgress(text, value)
        }
      } catch is CancellationError {
        progressText = L10n.text("已取消，保留已儲存摘要")
        if let store { snapshot = (try? await store.load()) ?? snapshot }
      } catch { self.error = error.localizedDescription }
      scanning = false
      scheduleNextRefresh()
    }
  }
  private func updateProgress(_ text: String, _ value: Double) {
    progressText = L10n.message(text)
    progress = value
  }
  func cancel() {
    automaticUpdatesPaused = true
    monitor?.cancel()
    scanTask?.cancel()
  }
  func important(_ skill: Skill) {
    guard !scanning, let importer else { return }
    Task {
      do {
        try await importer.setImportant(skill.id, value: !skill.important)
        if let store { snapshot = try await store.load() }
      } catch { self.error = error.localizedDescription }
    }
  }
  func addProject() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = L10n.text("加入專案")
    guard panel.runModal() == .OK, let url = panel.url, let importer else { return }
    Task {
      do {
        try await importer.addProject(url.path)
        refresh()
      } catch { self.error = error.localizedDescription }
    }
  }
  func removeProject(_ path: String) {
    guard !scanning, let importer else { return }
    Task {
      do {
        try await importer.removeProject(path)
        refresh()
      } catch { self.error = error.localizedDescription }
    }
  }
  func setLogin(_ enabled: Bool) {
    let service = SMAppService.mainApp
    defer { refreshLoginStatus() }
    do {
      if enabled {
        if service.status != .enabled && service.status != .requiresApproval {
          try service.register()
        }
      } else if service.status != .notRegistered {
        try service.unregister()
      }
    } catch {
      self.error = L10n.format("無法變更登入時自動啟動：%@", error.localizedDescription)
    }
  }
  func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }
  func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
  func reveal(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
  }
  private func scheduleNextRefresh() {
    monitor?.cancel()
    guard !automaticUpdatesPaused else { return }
    monitor = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(ScanPolicy.interval)) } catch { return }
      guard let self, !automaticUpdatesPaused else { return }
      monitor = nil
      refresh()
    }
  }
}
enum Page: String, CaseIterable, Identifiable {
  case skills, protected, candidates, sources
  var id: Self { self }
  var title: String {
    switch self {
    case .skills: L10n.text("所有 Skills")
    case .protected: L10n.text("保護中")
    case .candidates: L10n.text("移除建議")
    case .sources: L10n.text("資料來源")
    }
  }
  var icon: String {
    switch self {
    case .skills: "square.grid.2x2"
    case .protected: "shield"
    case .candidates: "archivebox"
    case .sources: "externaldrive"
    }
  }
}
