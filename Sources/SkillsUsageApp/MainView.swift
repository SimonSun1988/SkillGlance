import AppKit
import SkillsUsageCore
import SwiftUI

struct MainView: View {
  @EnvironmentObject var model: AppModel
  var body: some View {
    NavigationSplitView {
      Sidebar().navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
    } detail: {
      VStack(spacing: 0) {
        if model.scanning {
          HStack {
            ProgressView(value: model.progress).frame(maxWidth: 240)
            Text(model.progressText).foregroundStyle(Color.muted)
            Spacer()
            Button(L10n.text("取消")) { model.cancel() }.controlSize(.small)
          }.padding(.horizontal, 24).padding(.vertical, 8)
          Divider()
        }
        if model.automaticUpdatesPaused && !model.scanning {
          HStack {
            Label(L10n.text("自動更新已暫停"), systemImage: "pause.circle").foregroundStyle(Color.muted)
            Spacer()
            Button(L10n.text("繼續")) { model.refresh() }
          }.padding(.horizontal, 24).padding(.vertical, 8)
          Divider()
        }
        if model.page == .sources {
          SourcesView()
        } else {
          SkillsView()
        }
      }
    }
    .frame(minWidth: 1080, minHeight: 680)
    .navigationTitle(model.page.title)
    .onChange(of: model.page) { _, _ in
      model.selection = nil
      model.showDetail = false
    }
    .toolbar {
      ToolbarItem {
        if let date = model.snapshot.lastScan {
          Text(date, style: .time).foregroundStyle(Color.muted).help(L10n.text("最後完成更新"))
        }
      }
      ToolbarItem {
        Button {
          model.refresh()
        } label: {
          Label(L10n.text("重新整理"), systemImage: "arrow.clockwise")
        }.disabled(model.scanning).keyboardShortcut("r", modifiers: .command)
      }
      ToolbarItem {
        SettingsButton().keyboardShortcut(",", modifiers: .command)
      }
      ToolbarItem {
        Button {
          model.showDetail.toggle()
        } label: {
          Label(L10n.text("詳細資訊"), systemImage: "sidebar.right")
        }.disabled(model.selection == nil)
      }
    }
    .inspector(isPresented: $model.showDetail) {
      if let row = model.selected {
        SkillDetail(row: row)
      } else {
        ContentUnavailableView(L10n.text("選擇 Skill"), systemImage: "doc.text.magnifyingglass")
      }
    }
    .inspectorColumnWidth(min: 340, ideal: 380, max: 460)
    .alert(
      L10n.text("無法完成操作"),
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button(L10n.text("好")) { model.error = nil }
    } message: {
      Text(L10n.message(model.error ?? ""))
    }
  }
}

// The app runs as a menu bar accessory, so it must come forward before the Settings window opens.
struct SettingsButton: View {
  var body: some View {
    SettingsLink {
      Label(L10n.text("設定"), systemImage: "gearshape")
    }.simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
      .help(L10n.text("設定"))
  }
}

struct Sidebar: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.textBase) private var base
  var body: some View {
    let skills = model.snapshot.skills
    List(selection: Binding<Page?>(get: { model.page }, set: { model.page = $0 ?? model.page })) {
      Section {
        row(.skills, count: skills.count)
        row(.protected, count: skills.filter { $0.important || $0.managed }.count)
        row(.candidates, count: model.candidateCount)
      }
      Section(L10n.text("資料")) {
        HStack {
          Label(Page.sources.title, systemImage: Page.sources.icon).font(.system(size: base))
          Spacer()
          if sourcesNeedReview {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
              .imageScale(.small).accessibilityLabel(L10n.text("待確認"))
          }
        }.tag(Page.sources)
      }
    }.listStyle(.sidebar)
  }
  private var sourcesNeedReview: Bool {
    model.snapshot.scanIncomplete == true
      || model.snapshot.sources.contains { $0.issues > 0 && $0.requiredForAssessment != false }
  }
  private func row(_ page: Page, count: Int) -> some View {
    HStack {
      Label(page.title, systemImage: page.icon).font(.system(size: base))
      Spacer()
      Text(count, format: .number).foregroundStyle(Color.muted).monospacedDigit()
    }.tag(page)
  }
}

struct Metric: View {
  let value: Int
  let title: String
  let icon: String
  @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 34
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon).font(.body).foregroundStyle(Color.muted)
        .fixedSize(horizontal: true, vertical: false)
      Text(value, format: .number).font(
        .system(size: numberSize, weight: .semibold, design: .rounded)
      )
      .monospacedDigit()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

// A figure is set as type alone: the number, then its label.
struct Figure: View {
  let value: Int
  let title: String
  @Environment(\.textBase) private var base
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value, format: .number).font(.system(size: (base * 1.9).rounded(), weight: .semibold))
        .monospacedDigit()
      Text(title).foregroundStyle(Color.muted)
    }.accessibilityElement(children: .combine)
  }
}

struct SkillsView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.textBase) private var base
  var rows: [UsageRow] { model.rows }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.page.title).font(.system(size: base + 7, weight: .bold))
          Text(finding).font(.system(size: base + 2))
        }
        Spacer()
        if model.page != .candidates {
          Picker(L10n.text("期間"), selection: $model.days) {
            Text(L10n.text("7 天")).tag(7)
            Text(L10n.text("30 天")).tag(30)
            Text(L10n.text("90 天")).tag(90)
            Text(L10n.text("全部")).tag(0)
          }.labelsHidden().pickerStyle(.segmented).frame(width: 240)
        }
      }
      if model.page != .candidates {
        HStack(spacing: 44) {
          Figure(value: model.summary.activeSkills, title: L10n.text("使用中的 Skills"))
          Figure(value: model.summary.conversations, title: L10n.text("活躍對話"))
          Figure(value: model.summary.invocations, title: L10n.text("呼叫"))
          Figure(value: model.summary.reads, title: L10n.text("確認讀取"))
        }
        filters
      }
      if !model.snapshot.issues.isEmpty || model.snapshot.scanIncomplete == true {
        Button {
          model.page = .sources
        } label: {
          Label(
            L10n.text("部分證據待確認，移除評估暫停。查看資料來源"),
            systemImage: "exclamationmark.triangle.fill")
        }.buttonStyle(.link).foregroundStyle(.orange).help(L10n.text("查看資料來源與限制"))
      }
      if rows.isEmpty {
        ContentUnavailableView(
          model.page == .candidates ? L10n.text("目前沒有移除建議") : L10n.text("目前沒有符合的 Skills"),
          systemImage: model.page == .candidates ? "checkmark.shield" : "magnifyingglass",
          description: Text(
            model.page == .candidates
              ? L10n.text("新加入的 Skills 需觀察 90 天；有資料缺漏時會暫停評估。") : L10n.text("等待匯入完成，或調整搜尋條件。"))
        ).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        table
        Text(L10n.format("%lld Skills", rows.count)).foregroundStyle(Color.muted)
      }
    }.padding(.horizontal, 28).padding(.vertical, 22)
  }

  private var finding: String {
    switch model.page {
    case .protected:
      L10n.format("%lld 個 Skill 受到保護，不會列入移除建議。", rows.count)
    case .candidates:
      L10n.text("完整觀察 90 天且沒有使用訊號的 Skill，才會列在這裡。")
    default:
      model.userSkills == 0
        ? L10n.text("尚未找到你安裝的 Skill。")
        : model.unusedUserSkills == 0
          ? L10n.format("你安裝的 %lld 個 Skill，近 90 天都有使用紀錄。", model.userSkills)
          : L10n.format(
            "你安裝的 %lld 個 Skill 中，有 %lld 個近 90 天沒有使用紀錄。", model.userSkills,
            model.unusedUserSkills)
    }
  }

  private var filters: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        TextField(L10n.text("搜尋 Skills"), text: $model.search).textFieldStyle(.roundedBorder)
          .frame(width: 220)
        Picker(L10n.text("安裝範圍"), selection: $model.catalogScope) {
          Text(L10n.text("全部項目")).tag("all")
          Text(L10n.text("目前安裝")).tag("installed")
          Text(L10n.text("歷史項目")).tag("history")
          Text(L10n.text("Plugin 快取")).tag("cache")
        }.labelsHidden().frame(width: 140)
        Spacer()
        Picker(L10n.text("工具"), selection: $model.platform) {
          Text(L10n.text("所有工具")).tag(Platform?.none)
          ForEach(Platform.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
        }.labelsHidden().frame(width: 150)
        Picker(L10n.text("專案"), selection: $model.project) {
          Text(L10n.text("所有專案")).tag("")
          Text(L10n.text("未歸屬")).tag("__unassigned")
          ForEach(model.projects, id: \.self) {
            Text(URL(fileURLWithPath: $0).lastPathComponent).tag($0)
          }
        }.labelsHidden().frame(width: 170)
      }
      if !model.project.isEmpty && model.project != "__unassigned" {
        Picker("Worktree", selection: $model.worktree) {
          Text(L10n.text("所有 Worktrees")).tag("")
          ForEach(model.worktrees, id: \.self) { Text($0).tag($0) }
        }.frame(maxWidth: 420).onChange(of: model.project) { _, _ in model.worktree = "" }
      }
    }
  }

  private var table: some View {
    let peak = max(rows.map(\.conversations).max() ?? 1, 1)
    return Table(rows, selection: $model.selection) {
      TableColumn("Skill") { row in
        HStack(spacing: 6) {
          Text(row.skill.name).fontWeight(.medium).lineLimit(1)
          if row.skill.important {
            Image(systemName: "star.fill").foregroundStyle(.yellow).imageScale(.small)
              .accessibilityLabel(L10n.text("重要標記"))
          }
          if let tag = tag(row.skill) {
            Text(tag).foregroundStyle(Color.muted).lineLimit(1)
          }
        }
      }.width(min: 200, ideal: 280)
      TableColumn(L10n.text("活躍度")) { row in
        ActivityBar(fraction: Double(row.conversations) / Double(peak))
          .accessibilityLabel(L10n.format("%lld 個對話", row.conversations))
      }.width(min: 70, ideal: 120)
      TableColumn(L10n.text("對話")) { Text($0.conversations, format: .number).monospacedDigit() }
        .width(52).alignment(.trailing)
      TableColumn(L10n.text("呼叫")) { Text($0.invocations, format: .number).monospacedDigit() }
        .width(52).alignment(.trailing)
      TableColumn(L10n.text("讀取")) { Text($0.reads, format: .number).monospacedDigit() }
        .width(52).alignment(.trailing)
      TableColumn(L10n.text("天數")) { Text($0.days, format: .number).monospacedDigit() }
        .width(48).alignment(.trailing)
      TableColumn(L10n.text("最近使用")) { row in
        if let date = row.lastUsed {
          Text(date, format: Date.RelativeFormatStyle(presentation: .numeric))
            .foregroundStyle(Color.muted)
        } else {
          Text("—").foregroundStyle(.tertiary).accessibilityLabel(L10n.text("尚無確認紀錄"))
        }
      }.width(min: 90, ideal: 110)
      TableColumn(L10n.text("觀察")) { row in
        Text(observation(row)).foregroundStyle(Color.muted).monospacedDigit().help(row.reason)
      }.width(min: 70, ideal: 90)
    }.tableStyle(.inset(alternatesRowBackgrounds: false))
      .onChange(of: model.selection) { _, value in model.showDetail = value != nil }
  }

  private func tag(_ skill: Skill) -> String? {
    if skill.cacheOnly { return L10n.text("Plugin 快取") }
    if skill.managed { return L10n.text("系統／Plugin") }
    if !skill.installed { return L10n.text("歷史項目") }
    return nil
  }

  private func observation(_ row: UsageRow) -> String {
    if row.skill.important || row.skill.managed { return L10n.text("保護中") }
    if row.candidate { return L10n.text("移除建議") }
    let left = 90 - Int(Date().timeIntervalSince(row.skill.observedAt) / 86400)
    return left > 0 ? L10n.format("剩 %lld 天", left) : L10n.text("已滿 90 天")
  }
}

struct ActivityBar: View {
  let fraction: Double
  var body: some View {
    GeometryReader { proxy in
      Capsule().fill(Color.accentColor)
        .frame(width: fraction > 0 ? max(3, proxy.size.width * fraction) : 0, height: 6)
        .frame(maxHeight: .infinity)
    }
  }
}
