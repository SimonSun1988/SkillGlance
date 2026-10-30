import SkillsUsageCore
import SwiftUI

struct MainView: View {
  @EnvironmentObject var model: AppModel
  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 12) {
        BrandMark(size: 25).foregroundStyle(.tint).padding(
          .vertical, 16
        ).accessibilityHidden(true)
        ForEach(Page.allCases) { page in
          if page == .settings { Spacer() }
          Button {
            model.page = page
            model.selection = nil
            model.showDetail = false
          } label: {
            Image(systemName: page.icon).font(.system(size: 19)).frame(width: 44, height: 40)
              .background(
                model.page == page ? Color.accentColor.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 9)
              )
              .foregroundStyle(model.page == page ? Color.accentColor : Color.secondary)
          }.buttonStyle(.plain).help(page.title).accessibilityLabel(page.title)
            .accessibilityAddTraits(model.page == page ? .isSelected : [])
        }
      }.padding(.horizontal, 12).padding(.bottom, 18).frame(width: 76).background(
        .background.secondary)
      Divider()
      VStack(spacing: 0) {
        if model.scanning {
          HStack {
            ProgressView(value: model.progress).frame(maxWidth: 240)
            Text(model.progressText).font(.body).foregroundStyle(.secondary)
            Spacer()
            Button(L10n.text("取消")) { model.cancel() }.controlSize(.small)
          }.padding(.horizontal, 24).padding(.vertical, 8)
          Divider()
        }
        if model.automaticUpdatesPaused && !model.scanning {
          HStack {
            Label(L10n.text("自動更新已暫停"), systemImage: "pause.circle").foregroundStyle(.secondary)
            Spacer()
            Button(L10n.text("繼續")) { model.refresh() }
          }.padding(.horizontal, 24).padding(.vertical, 8)
          Divider()
        }
        if model.page == .sources {
          SourcesView()
        } else if model.page == .settings {
          PreferencesView()
        } else {
          SkillsView()
        }
      }
    }
    .frame(minWidth: 1080, minHeight: 680)
    .navigationTitle(model.page.title)
    .toolbar {
      ToolbarItem {
        if let date = model.snapshot.lastScan {
          Text(date, style: .time).font(.body).foregroundStyle(.secondary).help(L10n.text("最後完成更新"))
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
struct Metric: View {
  let value: Int
  let title: String
  let icon: String
  @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 34
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon).font(.body).foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
      Text(value, format: .number).font(
        .system(size: numberSize, weight: .semibold, design: .rounded)
      )
      .monospacedDigit()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct SkillsView: View {
  @EnvironmentObject var model: AppModel
  @ScaledMetric(relativeTo: .largeTitle) private var headingSize = 30
  var rows: [UsageRow] { model.rows }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text(model.page.title).font(.system(size: headingSize, weight: .bold))
          Text(
            model.page == .candidates
              ? L10n.text("完整觀察後，才提出整理建議。") : L10n.text("每個 Skill 的使用足跡，都在這裡。")
          )
          .foregroundStyle(.secondary)
        }
        Spacer()
        Picker(L10n.text("期間"), selection: $model.days) {
          Text(L10n.text("7 天")).tag(7)
          Text(L10n.text("30 天")).tag(30)
          Text(L10n.text("90 天")).tag(90)
          Text(L10n.text("全部")).tag(0)
        }.frame(width: 145)
      }
      HStack(spacing: 20) {
        // Count the whole catalog; `rows` is filtered by page, so the candidates page showed 0.
        Metric(
          value: model.snapshot.skills.filter { $0.installed && !$0.cacheOnly }.count,
          title: L10n.text("已安裝"),
          icon: "square.grid.2x2")
        Metric(value: model.summary.invocations, title: L10n.text("呼叫次數"), icon: "bolt")
        Metric(value: model.summary.reads, title: L10n.text("確認讀取"), icon: "doc.text")
        Metric(
          value: model.summary.conversations, title: L10n.text("確認活躍對話"),
          icon: "bubble.left.and.bubble.right")
      }.padding(18).background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
      HStack {
        Picker(L10n.text("安裝範圍"), selection: $model.catalogScope) {
          Text(L10n.text("全部項目")).tag("all")
          Text(L10n.text("目前安裝")).tag("installed")
          Text(L10n.text("歷史項目")).tag("history")
          Text(L10n.text("Plugin 快取")).tag("cache")
        }.labelsHidden().frame(width: 155)
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField(L10n.text("搜尋 Skills"), text: $model.search).textFieldStyle(.plain)
          .frame(minWidth: 140, maxWidth: 260)
        Spacer()
        Picker(L10n.text("工具"), selection: $model.platform) {
          Text(L10n.text("所有工具")).tag(Platform?.none)
          ForEach(Platform.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
        }.frame(width: 180)
        Picker(L10n.text("專案"), selection: $model.project) {
          Text(L10n.text("所有專案")).tag("")
          Text(L10n.text("未歸屬")).tag("__unassigned")
          ForEach(model.projects, id: \.self) {
            Text(URL(fileURLWithPath: $0).lastPathComponent).tag($0)
          }
        }.frame(width: 200)
      }
      if !model.project.isEmpty && model.project != "__unassigned" {
        Picker("Worktree", selection: $model.worktree) {
          Text(L10n.text("所有 Worktrees")).tag("")
          ForEach(model.worktrees, id: \.self) { Text($0).tag($0) }
        }.frame(maxWidth: 420).onChange(of: model.project) { _, _ in model.worktree = "" }
      }
      if !model.snapshot.issues.isEmpty || model.snapshot.scanIncomplete == true {
        Button {
          model.page = .sources
        } label: {
          Label(L10n.text("部分證據待確認 · 移除評估暫停"), systemImage: "exclamationmark.circle")
        }.buttonStyle(.plain).foregroundStyle(.secondary).help(L10n.text("查看資料來源與限制"))
      }
      if rows.isEmpty {
        ContentUnavailableView(
          model.page == .candidates ? L10n.text("目前沒有移除建議") : L10n.text("目前沒有符合的 Skills"),
          systemImage: model.page == .candidates ? "checkmark.shield" : "magnifyingglass",
          description: Text(
            model.page == .candidates
              ? L10n.text("新加入的 Skills 需觀察 90 天；有資料缺漏時會暫停評估。") : L10n.text("等待匯入完成，或調整搜尋條件。"))
        ).frame(maxHeight: .infinity)
      } else {
        Table(rows, selection: $model.selection) {
          TableColumn("Skill") { row in
            HStack(spacing: 8) {
              Image(
                systemName: row.skill.important
                  ? "star.fill" : row.skill.managed ? "shippingbox" : "doc.text"
              ).foregroundStyle(row.skill.important ? Color.accentColor : .secondary)
              VStack(alignment: .leading, spacing: 3) {
                Text(row.skill.name).fontWeight(.medium).lineLimit(1)
                Text(
                  row.skill.cacheOnly
                    ? L10n.text("Plugin 快取 · 狀態未確認")
                    : row.skill.managed
                      ? L10n.text("系統／Plugin 管理")
                      : !row.skill.installed ? L10n.text("歷史項目 · 不在盤點範圍") : L10n.text("使用者安裝")
                ).font(.body).foregroundStyle(.secondary)
              }
            }.padding(.vertical, 3)
          }.width(min: 220, ideal: 290)
          TableColumn(L10n.text("呼叫")) { Text($0.invocations, format: .number).monospacedDigit() }
            .width(70).alignment(.trailing)
          TableColumn(L10n.text("讀取")) { Text($0.reads, format: .number).monospacedDigit() }
            .width(70).alignment(.trailing)
          TableColumn(L10n.text("對話")) { Text($0.conversations, format: .number).monospacedDigit() }
            .width(70).alignment(.trailing)
          TableColumn(L10n.text("未知")) { Text($0.unknown, format: .number).monospacedDigit() }
            .width(80).alignment(.trailing)
          TableColumn(L10n.text("天數")) { Text($0.days, format: .number).monospacedDigit() }
            .width(60).alignment(.trailing)
          TableColumn(L10n.text("最近使用")) { row in
            if let date = row.lastUsed {
              Text(date, style: .relative).foregroundStyle(.secondary)
            } else {
              Text(L10n.text("尚無確認紀錄")).foregroundStyle(.secondary)
            }
          }.width(min: 110, ideal: 140)
          TableColumn(L10n.text("狀態")) { row in
            Label(
              row.reason,
              systemImage: row.skill.important || row.skill.managed
                ? "shield" : row.candidate ? "archivebox" : "clock"
            ).font(.body).foregroundStyle(.secondary).lineLimit(1).help(row.reason)
          }.width(min: 190, ideal: 220)
        }.tableStyle(.inset(alternatesRowBackgrounds: false))
          .onChange(of: model.selection) { _, value in model.showDetail = value != nil }
      }
      HStack {
        Text(L10n.format("%lld Skills", rows.count))
        Spacer()
        Label(L10n.text("僅在本機分析"), systemImage: "lock")
        Text(L10n.text("呼叫與讀取分開計算")).help(L10n.text("讀取不代表遵循指示；成功回傳不代表任務成功。"))
      }.font(.body).foregroundStyle(.secondary)
    }.padding(24)
  }
}
