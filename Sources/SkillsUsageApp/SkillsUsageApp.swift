import AppKit
import SwiftUI

@main struct SkillsUsageApp: App {
  @StateObject private var model = AppModel()
  var body: some Scene {
    MenuBarExtra {
      MenuPanel().environmentObject(model).environment(\.locale, L10n.locale)
    } label: {
      Image(nsImage: BrandAssets.menuBarImage).accessibilityLabel("SkillGlance")
    }
    .menuBarExtraStyle(.window)
    Window("SkillGlance", id: "main") {
      MainView().environmentObject(model).environment(\.locale, L10n.locale)
    }
      .defaultSize(width: 1280, height: 820).windowStyle(.automatic).windowToolbarStyle(
        .unifiedCompact)
  }
}
struct MenuPanel: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.openWindow) var openWindow
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        HStack(spacing: 8) {
          BrandMark(size: 20)
          Text("SkillGlance")
        }.font(.title3.weight(.semibold))
        Spacer()
        Image(systemName: model.scanning ? "arrow.triangle.2.circlepath" : "checkmark.circle")
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 24) {
        Metric(
          value: model.snapshot.skills.filter { $0.installed && !$0.cacheOnly }.count,
          title: L10n.text("已安裝"),
          icon: "square.grid.2x2")
        Metric(value: model.menuSummary.invocations, title: L10n.text("呼叫"), icon: "bolt")
        Metric(value: model.menuSummary.reads, title: L10n.text("確認讀取"), icon: "doc.text")
      }
      HStack {
        Label(L10n.text("活躍 Skills"), systemImage: "waveform.path")
        Spacer()
        Text("\(model.menuSummary.activeSkills)").monospacedDigit()
        Text(L10n.text("／最近 90 天")).foregroundStyle(.secondary)
      }.font(.body)
      Divider()
      ForEach(model.menuRows.filter { $0.conversations > 0 }.prefix(3)) { row in
        HStack {
          Text(row.skill.name).lineLimit(1)
          Spacer()
          Text("\(row.conversations)").monospacedDigit()
          Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(.secondary)
        }.font(.title3)
      }
      if model.scanning {
        ProgressView(value: model.progress)
        Text(model.progressText).font(.body).foregroundStyle(.secondary)
      } else {
        Label(
          model.snapshot.issues.isEmpty ? L10n.text("本機分析 · 最近 90 天") : L10n.text("部分證據待確認"),
          systemImage: model.snapshot.issues.isEmpty ? "lock" : "exclamationmark.circle"
        ).font(.body).foregroundStyle(.secondary)
      }
      HStack {
        Button(L10n.text("開啟統計")) {
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
        }.buttonStyle(.borderedProminent)
        Spacer()
        Button {
          model.refresh()
        } label: {
          Image(systemName: "arrow.clockwise")
        }.help(L10n.text("重新整理")).accessibilityLabel(L10n.text("重新整理")).disabled(model.scanning)
        Button {
          NSApp.terminate(nil)
        } label: {
          Image(systemName: "power")
        }.help(L10n.text("結束 SkillGlance")).accessibilityLabel(L10n.text("結束 SkillGlance"))
      }
    }.font(.title3).controlSize(.large).padding(20).frame(width: 400)
  }
}
