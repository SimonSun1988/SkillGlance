import SkillsUsageCore
import SwiftUI

struct SkillDetail: View {
  @EnvironmentObject var model: AppModel
  let row: UsageRow
  var events: [UsageEvent] {
    model.snapshot.events.filter { $0.skillID == row.id && $0.evidence != .context }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          Image(systemName: "doc.text").font(.title).foregroundStyle(.tint)
          Spacer()
          Button {
            model.important(row.skill)
          } label: {
            Image(systemName: row.skill.important ? "star.fill" : "star")
          }.help(row.skill.important ? L10n.text("取消重要標記") : L10n.text("標記為重要")).accessibilityLabel(
            L10n.text("重要標記")
          ).disabled(
            model.scanning)
        }
        Text(row.skill.name).font(.title.bold()).textSelection(.enabled)
        Label(
          row.reason, systemImage: row.skill.important || row.skill.managed ? "shield" : "clock"
        ).foregroundStyle(.secondary)
        HStack {
          Metric(value: row.invocations, title: L10n.text("呼叫"), icon: "bolt")
          Metric(value: row.reads, title: L10n.text("確認讀取"), icon: "doc.text")
        }
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Text(L10n.text("安裝來源")).font(.headline)
          Text(row.skill.path).font(.body.monospaced()).foregroundStyle(.secondary)
            .textSelection(.enabled)
          Button(L10n.text("在 Finder 中顯示"), systemImage: "folder") { model.reveal(row.skill.path) }
        }
        HStack {
          Label(L10n.text("失敗"), systemImage: "xmark.circle")
          Spacer()
          Text("\(row.failures)")
          Label(L10n.text("未知"), systemImage: "questionmark.circle")
          Text("\(row.unknown)")
        }.foregroundStyle(.secondary)
        LabeledContent(L10n.text("開始觀察")) { Text(row.skill.observedAt, style: .date) }
        if row.skill.aliases.count > 1 {
          Text(L10n.format("%lld 個路徑連到同一來源，已合併計算。", row.skill.aliases.count)).font(.body)
            .foregroundStyle(
              .secondary)
        }
        Divider()
        Text(L10n.text("使用紀錄")).font(.headline)
        if events.isEmpty { Text(L10n.text("尚無可歸屬紀錄")).foregroundStyle(.secondary) }
        ForEach(events.prefix(60)) { event in
          VStack(alignment: .leading, spacing: 7) {
            HStack {
              Image(systemName: event.evidence == .invocation ? "bolt" : "doc.text")
              Text(
                event.evidence == .invocation
                  ? L10n.text("呼叫") : event.confirmed ? L10n.text("確認讀取") : L10n.text("讀取嘗試"))
              Spacer()
              Text(
                event.outcome == .success
                  ? L10n.text("成功回傳")
                  : event.outcome == .failure ? L10n.text("失敗") : L10n.text("結果未知")
              )
              .foregroundStyle(.secondary)
            }
            HStack {
              Text(event.platform.label)
              Spacer()
              Text(event.time, format: .dateTime.month().day().hour().minute())
            }.font(.body).foregroundStyle(.secondary)
            if event.time < row.skill.observedAt {
              Text(L10n.text("歷史路徑／名稱關聯 · 未驗證當時版本")).font(.body).foregroundStyle(.secondary)
            }
            if event.evidence == .read {
              Text(L10n.format("讀取範圍：%@", L10n.text(event.scope))).font(.body).foregroundStyle(
                .secondary)
            }
            if !event.cwd.isEmpty {
              Text(URL(fileURLWithPath: event.cwd).lastPathComponent).font(.body)
                .foregroundStyle(.secondary)
            }
            Button(
              event.line > 0 ? L10n.format("來源第 %lld 行", event.line) : L10n.text("在 Finder 顯示來源"),
              systemImage: "arrow.up.right.square"
            ) {
              model.reveal(event.source)
            }.font(.body).buttonStyle(.link)
          }.padding(12).background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
        Text(L10n.text("成功回傳不代表任務成功；讀取不代表已遵循指示。")).font(.body).foregroundStyle(.secondary)
      }.padding(20)
    }
  }
}
struct SourcesView: View {
  @EnvironmentObject var model: AppModel
  var body: some View {
    Form {
      Section(L10n.text("AI 工具")) {
        ForEach(Platform.allCases, id: \.self) { platform in
          let source = model.snapshot.sources.first { $0.platform == platform }
          HStack(alignment: .top, spacing: 14) {
            Image(systemName: "terminal").font(.title2).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 6) {
              Text(platform.label).font(.headline)
              Text(sourceDescription(platform)).font(.body).foregroundStyle(.secondary)
              Text(
                source.map {
                  L10n.format(
                    "%lld 個紀錄檔 · %@", $0.files,
                    ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file))
                } ?? L10n.text("等待首次匯入")
              )
              Text(L10n.message(source?.message ?? "未掃描")).font(.body).foregroundStyle(.secondary)
            }
            Spacer()
            Label(
              source == nil
                ? L10n.text("未掃描")
                : source?.requiredForAssessment == false
                  ? L10n.text("未偵測")
                  : (source?.issues ?? 0) > 0 ? L10n.text("待確認") : L10n.text("本機可讀"),
              systemImage: source?.requiredForAssessment == false
                ? "minus.circle"
                : (source?.issues ?? 0) > 0 ? "exclamationmark.circle" : "checkmark.circle"
            ).font(.body).foregroundStyle(.secondary)
          }.padding(.vertical, 8)
        }
        Text(L10n.text("使用者指定與 AI 自行選用都會計入；依實際呼叫、讀取或明確載入紀錄計算。"))
          .font(.body).foregroundStyle(.secondary)
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
        Text(
          L10n.text(
            "僅分析本機可讀紀錄。Antigravity 歷史紀錄只能確認讀取請求，無法配對結果時不增加確認讀取；未知格式與來源缺漏會暫停移除評估。")
        )
        .font(.body).foregroundStyle(.secondary)
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
              Text(target).font(.body.monospaced()).textSelection(.enabled)
              Text(
                L10n.format(
                  "%lld 次呼叫 · %lld 次確認讀取 · %lld 個上下文訊號",
                  events.filter { $0.evidence == .invocation }.count,
                  events.filter { $0.confirmed }.count,
                  events.filter { $0.evidence == .context }.count)
              ).font(.body).foregroundStyle(.secondary)
            }
          }
          Text(L10n.text("明確操作仍納入概覽；安裝來源無法唯一對應時，不會歸入目前 Skills 的排行。")).font(.body).foregroundStyle(
            .secondary)
        }
      }
      Section(L10n.text("專案 Skills")) {
        ForEach(model.snapshot.projectRoots, id: \.self) { path in
          LabeledContent(URL(fileURLWithPath: path).lastPathComponent) {
            Text(path).font(.body.monospaced()).textSelection(.enabled)
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
        Text(L10n.text("只盤點加入專案內各工具約定的 Skills 目錄，不掃描整台電腦。")).font(.body)
          .foregroundStyle(.secondary)
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
  @State private var confirmRebuild = false
  var body: some View {
    Form {
      Section(L10n.text("一般")) {
        Toggle(
          L10n.text("登入時自動啟動"),
          isOn: Binding(get: { model.loginRequested }, set: { model.setLogin($0) }))
        Text(L10n.text("登入 Mac 後常駐選單列，不自動開啟統計視窗。"))
          .font(.body).foregroundStyle(.secondary)
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
            .font(.body).foregroundStyle(.secondary)
        }
        LabeledContent(L10n.text("更新方式"), value: L10n.text("啟動時更新，之後每小時一次"))
        LabeledContent(L10n.text("外觀"), value: L10n.text("跟隨 macOS"))
      }
      Section(L10n.text("隱私與儲存")) {
        Label(L10n.text("所有分析都在這台 Mac 上完成"), systemImage: "lock.shield")
        Text(L10n.text("資料庫只儲存事件摘要、來源定位與讀取進度，不儲存對話原文或工具輸出。")).foregroundStyle(
          .secondary)
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
        Text(L10n.text("重新讀取本機紀錄，保留重要標記與專案設定。觀察期會重新計算；來源紀錄不會變更。")).font(.body).foregroundStyle(
          .secondary)
      }
      Section(L10n.text("關於")) {
        LabeledContent("SkillGlance", value: L10n.format("%@ · 本機版本", "0.2.1"))
        Text(L10n.text("移除建議僅供檢視；App 不會刪除 Skills。")).foregroundStyle(.secondary)
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
