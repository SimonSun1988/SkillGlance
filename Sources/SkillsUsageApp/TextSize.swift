import SwiftUI

enum TextSize: String, CaseIterable, Identifiable {
  case standard, large, extraLarge
  static let storageKey = "textSize"
  var id: Self { self }
  var base: CGFloat {
    switch self {
    case .standard: 13
    case .large: 15
    case .extraLarge: 17
    }
  }
  var title: String {
    switch self {
    case .standard: L10n.text("標準")
    case .large: L10n.text("大")
    case .extraLarge: L10n.text("特大")
    }
  }
}

private struct TextBaseKey: EnvironmentKey {
  static let defaultValue: CGFloat = TextSize.large.base
}

extension EnvironmentValues {
  // Body size in points; every other size on screen is derived from it.
  var textBase: CGFloat {
    get { self[TextBaseKey.self] }
    set { self[TextBaseKey.self] = newValue }
  }
}

extension Color {
  // Secondary text a step darker than the system style, which read as too faint.
  static let muted = Color.primary.opacity(0.72)
}

struct ScaledText: ViewModifier {
  @AppStorage(TextSize.storageKey) private var size = TextSize.large
  func body(content: Content) -> some View {
    content.environment(\.textBase, size.base).font(.system(size: size.base))
      .controlSize(size == .standard ? .regular : .large)
  }
}

extension View {
  func scaledText() -> some View { modifier(ScaledText()) }
}
