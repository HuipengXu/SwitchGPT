import SwiftUI

enum ChatGPTStyle {
  static let toolbarHeight: CGFloat = 46
  static let toolbarHorizontalInset: CGFloat = 16
  static let sidebarWidth: CGFloat = 268
  static let contentWidth: CGFloat = 850
  static let contentHorizontalInset: CGFloat = 32
  static let rowRadius: CGFloat = 10
  static let panelRadius: CGFloat = 15

  // ChatGPT keeps structure neutral and uses color only to communicate meaning.
  static let actionBlue = Color(red: 10 / 255, green: 132 / 255, blue: 1)
  static let successGreen = Color(red: 36 / 255, green: 151 / 255, blue: 72 / 255)
  static let warningOrange = Color(red: 1, green: 107 / 255, blue: 38 / 255)
  static let dangerRed = Color(red: 1, green: 59 / 255, blue: 48 / 255)

  static func surface(for scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255) : .white
  }

  static func sidebarBackground(for scheme: ColorScheme) -> LinearGradient {
    let colors =
      scheme == .dark
      ? [
        Color(red: 33 / 255, green: 33 / 255, blue: 35 / 255),
        Color(red: 29 / 255, green: 38 / 255, blue: 45 / 255),
      ]
      : [
        Color(red: 236 / 255, green: 237 / 255, blue: 239 / 255),
        Color(red: 229 / 255, green: 241 / 255, blue: 250 / 255),
      ]
    return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
  }

  static func softSurface(for scheme: ColorScheme) -> Color {
    scheme == .dark
      ? Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)
      : Color(red: 243 / 255, green: 243 / 255, blue: 243 / 255)
  }

  static func elevatedSurface(for scheme: ColorScheme) -> Color {
    scheme == .dark
      ? Color(red: 48 / 255, green: 48 / 255, blue: 48 / 255)
      : .white
  }

  static let subtleFill = Color.primary.opacity(0.05)
  static let hoverFill = Color.primary.opacity(0.08)
  static let border = Color.primary.opacity(0.08)
  static let strongBorder = Color.primary.opacity(0.12)

  static func semanticFill(_ color: Color) -> Color {
    color.opacity(0.09)
  }

  static func semanticBorder(_ color: Color) -> Color {
    color.opacity(0.20)
  }
}

struct ChatGPTIconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .frame(width: 30, height: 30)
      .background(
        configuration.isPressed ? ChatGPTStyle.hoverFill : Color.clear,
        in: RoundedRectangle(cornerRadius: ChatGPTStyle.rowRadius, style: .continuous)
      )
      .contentShape(Rectangle())
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

struct ChatGPTPrimaryButtonStyle: ButtonStyle {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
      .padding(.horizontal, 16)
      .frame(minHeight: 36)
      .background(
        colorScheme == .dark ? Color.white : Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255),
        in: RoundedRectangle(cornerRadius: ChatGPTStyle.rowRadius, style: .continuous)
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.36)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

struct ChatGPTSecondaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14, weight: .medium))
      .padding(.horizontal, 14)
      .frame(minHeight: 36)
      .background(
        configuration.isPressed ? ChatGPTStyle.hoverFill : ChatGPTStyle.subtleFill,
        in: RoundedRectangle(cornerRadius: ChatGPTStyle.rowRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: ChatGPTStyle.rowRadius, style: .continuous)
          .stroke(ChatGPTStyle.border, lineWidth: 1)
      }
      .opacity(isEnabled ? 1 : 0.42)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

struct ChatGPTSwitchToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(configuration.isOn ? ChatGPTStyle.actionBlue : Color.primary.opacity(0.14))
        .frame(width: 34, height: 20)
        .overlay(alignment: configuration.isOn ? .trailing : .leading) {
          Circle()
            .fill(.white)
            .frame(width: 16, height: 16)
            .padding(2)
            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
        }
    }
    .buttonStyle(.plain)
    .accessibilityValue(configuration.isOn ? "On" : "Off")
    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
  }
}

struct ChatGPTPanelModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content
      .background(
        ChatGPTStyle.softSurface(for: colorScheme),
        in: RoundedRectangle(cornerRadius: ChatGPTStyle.panelRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: ChatGPTStyle.panelRadius, style: .continuous)
          .stroke(ChatGPTStyle.border, lineWidth: 1)
      }
  }
}

struct ChatGPTContentColumnModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .frame(maxWidth: ChatGPTStyle.contentWidth, alignment: .leading)
      .padding(.horizontal, ChatGPTStyle.contentHorizontalInset)
      .frame(maxWidth: .infinity, alignment: .center)
  }
}

extension View {
  func chatGPTPanel() -> some View {
    modifier(ChatGPTPanelModifier())
  }

  /// Keeps the scroll content responsive without making the toolbar inherit
  /// the same centered column geometry.
  func chatGPTContentColumn() -> some View {
    modifier(ChatGPTContentColumnModifier())
  }
}
