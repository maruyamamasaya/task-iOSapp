import SwiftUI

extension AppTheme {
    var headingDesign: Font.Design {
        switch self {
        case .classic, .linen: .serif
        case .sakura: .rounded
        case .midnight, .modern: .default
        }
    }

    var controlRadius: CGFloat {
        switch self {
        case .classic: 8
        case .sakura: 18
        case .linen: 10
        case .midnight: 10
        case .modern: 14
        }
    }

    var contentSpacing: CGFloat {
        switch self {
        case .classic, .midnight: 14
        case .linen: 18
        case .sakura, .modern: 20
        }
    }

    func headingFont(_ style: Font.TextStyle) -> Font {
        .system(style, design: headingDesign, weight: self == .linen ? .medium : .semibold)
    }
}

/// Quiet feedback that also respects the system's Reduce Motion preference.
struct ThemedPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct ThemedControlStyle: ButtonStyle {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: settings.theme.headingDesign, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(settings.theme.accent.opacity(configuration.isPressed ? 0.20 : 0.09),
                        in: RoundedRectangle(cornerRadius: settings.theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: settings.theme.controlRadius))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
