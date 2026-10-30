import SkillsUsageCore
import SwiftUI

struct SkillDetail: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.textBase) private var base
  let row: UsageRow
  var events: [UsageEvent] {
    model.snapshot.events.filter { $0.skillID == row.id && $0.evidence != .context }
  }
  var body: some View {
    let recent = Array(events.prefix(60))
    let days = Dictionary(grouping: recent) { Calendar.current.startOfDay(for: $0.time) }
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .firstTextBaseline) {
          Text(row.skill.name).font(.system(size: base + 5, weight: .bold)).textSelection(.enabled)
          Spacer()
          Button {
            model.important(row.skill)
          } label: {
            Image(systemName: row.skill.important ? "star.fill" : "star")
          }.help(row.skill.important ? L10n.text("取消重要標記") : L10n.text("標記為重要")).accessibilityLabel(
            L10n.text("重要標記")
          ).disabled(model.scanning)
        }
        Text(row.reason).foregroundStyle(Color.muted)
        HStack(spacing: 28) {
          Figure(value: row.invocations, title: L10n.text("呼叫"))
          Figure(value: row.reads, title: L10n.text("確認讀取"))
          Figure(value: row.conversations, title: L10n.text("對話"))
          Figure(value: row.days, title: L10n.text("天數"))
        }
        Divider()
        VStack(spacing: 6) {
          fact(L10n.text("失敗")) { Text(row.failures, format: .number).monospacedDigit() }
          fact(L10n.text("未知")) { Text(row.unknown, format: .number).monospacedDigit() }
          fact(L10n.text("開始觀察")) { Text(row.skill.observedAt, style: .date) }
          fact(L10n.text("最近使用")) {
            if let date = row.lastUsed { Text(date, style: .date) } else { Text("—") }
          }
        }
        if row.skill.aliases.count > 1 {
          Text(L10n.format("%lld 個路徑連到同一來源，已合併計算。", row.skill.aliases.count))
            .font(.system(size: base - 1)).foregroundStyle(Color.muted)
        }
        Divider()
        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.text("安裝來源")).font(.system(size: base, weight: .semibold))
          Text(row.skill.path).font(.system(size: base - 1, design: .monospaced)).foregroundStyle(Color.muted)
            .textSelection(.enabled)
          Button(L10n.text("在 Finder 中顯示"), systemImage: "folder") { model.reveal(row.skill.path) }
        }
        Divider()
        Text(L10n.text("使用紀錄")).font(.system(size: base, weight: .semibold))
        if events.isEmpty { Text(L10n.text("尚無可歸屬紀錄")).foregroundStyle(Color.muted) }
        ForEach(days.keys.sorted(by: >), id: \.self) { day in
          VStack(alignment: .leading, spacing: 10) {
            Text(day, format: .dateTime.year().month().day().weekday())
              .font(.system(size: base - 1, weight: .semibold)).foregroundStyle(Color.muted)
            ForEach(days[day] ?? []) { event in EventRow(event: event, observedAt: row.skill.observedAt) }
          }
        }
        Text(L10n.text("成功回傳不代表任務成功；讀取不代表已遵循指示。")).font(.system(size: base - 1))
          .foregroundStyle(Color.muted)
      }.padding(20)
    }
  }
  private func fact<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
    HStack {
      Text(title).foregroundStyle(Color.muted)
      Spacer()
      value()
    }
  }
}
struct EventRow: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.textBase) private var base
  let event: UsageEvent
  let observedAt: Date
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(
          event.evidence == .invocation
            ? L10n.text("呼叫") : event.confirmed ? L10n.text("確認讀取") : L10n.text("讀取嘗試")
        ).fontWeight(.medium)
        Text(
          event.outcome == .success
            ? L10n.text("成功回傳")
            : event.outcome == .failure ? L10n.text("失敗") : L10n.text("結果未知")
        ).foregroundStyle(event.outcome == .failure ? Color.red : Color.muted)
        Spacer()
        Text(event.time, format: .dateTime.hour().minute()).foregroundStyle(Color.muted)
          .monospacedDigit()
        Button {
          model.reveal(event.source)
        } label: {
          Image(systemName: "arrow.up.right.square")
        }.buttonStyle(.borderless).help(
          event.line > 0 ? L10n.format("來源第 %lld 行", event.line) : L10n.text("在 Finder 顯示來源")
        ).accessibilityLabel(L10n.text("在 Finder 顯示來源"))
      }
      Text(details).font(.system(size: base - 1)).foregroundStyle(Color.muted).help(event.cwd)
      if event.time < observedAt {
        Text(L10n.text("歷史路徑／名稱關聯 · 未驗證當時版本")).font(.system(size: base - 1)).foregroundStyle(Color.muted)
      }
    }
  }
  // Name the place by its worktree or project, not by the last folder of the working directory.
  private var details: String {
    let place = event.worktree ?? event.project ?? (event.cwd.isEmpty ? nil : event.cwd)
    var parts = [event.platform.label]
    if let place { parts.append(URL(fileURLWithPath: place).lastPathComponent) }
    if event.evidence == .read { parts.append(L10n.format("讀取範圍：%@", L10n.text(event.scope))) }
    return parts.joined(separator: " · ")
  }
}
struct SourcesView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.textBase) private var base
  var body: some View {
    Form {
      Section(L10n.text("AI 工具")) {
        ForEach(Platform.allCases, id: \.self) { platform in
          let source = model.snapshot.sources.first { $0.platform == platform }
          let detected = source != nil && source?.requiredForAssessment != false
          let review = detected && (source?.issues ?? 0) > 0
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(
              systemName: source == nil
                ? "circle.dotted"
                : !detected ? "minus.circle" : review ? "exclamationmark.triangle.fill" : "checkmark.circle"
            ).foregroundStyle(review ? Color.orange : Color.muted).frame(width: 18)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(platform.label).font(.system(size: base, weight: .semibold))
                Spacer()
                Text(
                  source == nil
                    ? L10n.text("未掃描")
                    : !detected ? L10n.text("未偵測") : review ? L10n.text("待確認") : L10n.text("本機可讀")
                ).foregroundStyle(review ? Color.orange : Color.muted)
              }
              Text(sourceDescription(platform)).font(.system(size: base - 1)).foregroundStyle(Color.muted)
              if let source, detected {
                Text(
                  L10n.format(
                    "%lld 個紀錄檔 · %@", source.files,
                    ByteCountFormatter.string(fromByteCount: source.bytes, countStyle: .file)))
              }
              if review, let source {
                Text(L10n.message(source.message)).font(.system(size: base - 1)).foregroundStyle(Color.muted)
              }
            }
          }.padding(.vertical, 4)
        }
        Text(L10n.text("使用者指定與 AI 自行選用都會計入；依實際呼叫、讀取或明確載入紀錄計算。"))
          .foregroundStyle(Color.muted)
      }
      Section(L10n.text("資料品質")) {
        if model.snapshot.scanIncomplete == true {
          Label(L10n.text("匯入尚未完成，移除評估暫停"), systemImage: "pause.circle")
        }
        LabeledContent(
          L10n.text("未歸屬紀錄"), value: "\(model.snapshot.events.filter { $0.skillID == nil }.count)")
        if model.snapshot.issues.isEmpty && model.snapshot.scanIncomplete != true {
          Label(L10n.text("目前沒有已知匯入錯誤"), systemImage: "checkmark.circle")
        }
        ForEach(model.snapshot.issues, id: \.self) {
          Label(L10n.message($0), systemImage: "exclamationmark.circle")
        }
        ForEach(model.snapshot.notices ?? [], id: \.self) {
          Label(L10n.message($0), systemImage: "info.circle").font(.system(size: base - 1))
            .foregroundStyle(Color.muted)
        }
        Text(
          L10n.text(
            "僅分析本機可讀紀錄。Antigravity 歷史紀錄只能確認讀取請求，無法配對結果時不增加確認讀取；未知格式與來源缺漏會暫停移除評估。")
        )
        .foregroundStyle(Color.muted)
      }
      if model.snapshot.events.contains(where: { $0.skillID == nil }) {
        Section(L10n.text("未歸屬的歷史紀錄")) {
          ForEach(
            Array(
              Dictionary(grouping: model.snapshot.events.filter { $0.skillID == nil }, by: \.target)
                .keys.sorted().prefix(30)), id: \.self
          ) { target in
            let events = model.snapshot.events.filter { $0.skillID == nil && $0.target == target }
            VStack(alignment: .leading, spacing: 5) {
              Text(target).monospaced().textSelection(.enabled)
              Text(
                L10n.format(
                  "%lld 次呼叫 · %lld 次確認讀取 · %lld 個上下文訊號",
                  events.filter { $0.evidence == .invocation }.count,
                  events.filter { $0.confirmed }.count,
                  events.filter { $0.evidence == .context }.count)
              ).foregroundStyle(Color.muted)
            }
          }
          Text(L10n.text("明確操作仍納入概覽；安裝來源無法唯一對應時，不會歸入目前 Skills 的排行。")).foregroundStyle(Color.muted)
        }
      }
      Section(L10n.text("專案 Skills")) {
        ForEach(model.snapshot.projectRoots, id: \.self) { path in
          LabeledContent(URL(fileURLWithPath: path).lastPathComponent) {
            Text(path).monospaced().textSelection(.enabled)
            Button {
              model.removeProject(path)
            } label: {
              Image(systemName: "minus.circle")
            }.help(L10n.text("移除掃描範圍，保留摘要")).accessibilityLabel(L10n.text("移除掃描範圍")).disabled(
              model.scanning)
          }
        }
        Button(L10n.text("加入專案資料夾"), systemImage: "folder.badge.plus") { model.addProject() }
          .disabled(
            model.scanning)
        Text(L10n.text("只盤點加入專案內各工具約定的 Skills 目錄，不掃描整台電腦。"))
          .foregroundStyle(Color.muted)
      }
    }.formStyle(.grouped)
  }

  private func sourceDescription(_ platform: Platform) -> String {
    switch platform {
    case .codex: "~/.codex/sessions · archived_sessions"
    case .claudeDesktop: "Desktop Code metadata ＋ ~/.claude/projects"
    case .claudeCode: L10n.text("Claude Code 本機對話紀錄")
    case .gemini: "~/.gemini/tmp/*/chats"
    case .antigravity: L10n.text("App／IDE／CLI 的 transcript_full 紀錄")
    case .cursor: L10n.text("Cursor 本機 SQLite 紀錄")
    }
  }
}
struct PreferencesView: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(TextSize.storageKey) private var textSize = TextSize.large
  @State private var confirmRebuild = false
  var body: some View {
    Form {
      Section(L10n.text("一般")) {
        Toggle(
          L10n.text("登入時自動啟動"),
          isOn: Binding(get: { model.loginRequested }, set: { model.setLogin($0) }))
        Text(L10n.text("登入 Mac 後常駐選單列，不自動開啟統計視窗。"))
          .foregroundStyle(Color.muted)
        if model.loginStatus == .requiresApproval {
          LabeledContent {
            Button(L10n.text("開啟系統設定"), systemImage: "arrow.up.forward.square") {
              model.openLoginSettings()
            }
          } label: {
            Label(L10n.text("等待允許登入項目"), systemImage: "exclamationmark.circle")
          }
        } else if model.loginStatus == .enabled {
          Label(L10n.text("已啟用登入時自動啟動"), systemImage: "checkmark.circle")
            .foregroundStyle(Color.muted)
        }
        LabeledContent(L10n.text("更新方式"), value: L10n.text("啟動時更新，之後每小時一次"))
        Picker(L10n.text("文字大小"), selection: $textSize) {
          ForEach(TextSize.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented)
      }
      Section(L10n.text("隱私與儲存")) {
        Label(L10n.text("所有分析都在這台 Mac 上完成"), systemImage: "lock.shield")
        Text(L10n.text("資料庫只儲存事件摘要、來源定位與讀取進度，不儲存對話原文或工具輸出。")).foregroundStyle(Color.muted)
        LabeledContent(L10n.text("資料位置")) {
          Button(L10n.text("在 Finder 顯示"), systemImage: "folder") {
            model.reveal(model.directory.path)
          }
        }
      }
      Section(L10n.text("統計資料")) {
        Button(L10n.text("重新建立統計"), systemImage: "arrow.triangle.2.circlepath") {
          confirmRebuild = true
        }
        .disabled(model.scanning)
        Text(L10n.text("重新讀取本機紀錄，保留重要標記與專案設定。觀察期會重新計算；來源紀錄不會變更。")).foregroundStyle(Color.muted)
      }
      Section(L10n.text("關於")) {
        LabeledContent("SkillGlance", value: L10n.format("%@ · 本機版本", "0.3.0"))
        Text(L10n.text("移除建議僅供檢視；App 不會刪除 Skills。")).foregroundStyle(Color.muted)
      }
    }.formStyle(.grouped)
      .onAppear { model.refreshLoginStatus() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { model.refreshLoginStatus() }
      }
      .confirmationDialog(
        L10n.text("重新建立統計？"), isPresented: $confirmRebuild, titleVisibility: .visible
      ) {
        Button(L10n.text("重新建立")) { model.refresh(rebuild: true) }
        Button(L10n.text("取消"), role: .cancel) {}
      } message: {
        Text(L10n.text("完成後才會以新統計取代舊統計，並重設 90 天觀察期。"))
      }
  }
}
