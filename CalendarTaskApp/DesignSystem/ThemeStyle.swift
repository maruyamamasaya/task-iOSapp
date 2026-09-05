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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let palette = settings.theme.appearance(for: scheme)
        let shape = RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous)
        configuration.label
            .font(settings.theme.headingFont(.subheadline, for: scheme))
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(palette.control, in: shape)
            .overlay {
                shape.fill(palette.accent.opacity(configuration.isPressed ? 0.12 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(contrast == .increased ? palette.accent : palette.border,
                                   lineWidth: scheme == .dark || contrast == .increased ? 1 : 0.5)
            }
            .contentShape(shape)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Each appearance is art-directed separately; opaque reading surfaces keep texture behind content.
struct ThemeAppearance {
    let background: Color
    let surface: Color
    let accent: Color
    let ink: Color
    let mutedInk: Color
    let selectionInk: Color
    let border: Color
    let ornament: Color
    let control: Color
    let shadow: Color
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let surfaceRadius: CGFloat
    let controlRadius: CGFloat
    let borderWidth: CGFloat
    let headingWeight: Font.Weight
    let headingTracking: CGFloat
    let subtitle: String

    init(background: UInt32, surface: UInt32, accent: UInt32, ink: UInt32, muted: UInt32,
         selectionInk: UInt32, border: UInt32, ornament: UInt32, control: UInt32,
         shadow: UInt32, shadowOpacity: Double, shadowRadius: CGFloat, shadowY: CGFloat,
         surfaceRadius: CGFloat, controlRadius: CGFloat, borderWidth: CGFloat = 0.75,
         headingWeight: Font.Weight = .semibold, headingTracking: CGFloat = 0,
         subtitle: String) {
        self.background = Color(themeHex: background); self.surface = Color(themeHex: surface)
        self.accent = Color(themeHex: accent); self.ink = Color(themeHex: ink)
        self.mutedInk = Color(themeHex: muted); self.selectionInk = Color(themeHex: selectionInk)
        self.border = Color(themeHex: border); self.ornament = Color(themeHex: ornament)
        self.control = Color(themeHex: control); self.shadow = Color(themeHex: shadow).opacity(shadowOpacity)
        self.shadowRadius = shadowRadius; self.shadowY = shadowY
        self.surfaceRadius = surfaceRadius; self.controlRadius = controlRadius
        self.borderWidth = borderWidth; self.headingWeight = headingWeight
        self.headingTracking = headingTracking; self.subtitle = subtitle
    }
}

private extension Color {
    init(themeHex: UInt32) {
        self.init(.sRGB, red: Double((themeHex >> 16) & 255) / 255,
                  green: Double((themeHex >> 8) & 255) / 255, blue: Double(themeHex & 255) / 255, opacity: 1)
    }
}

extension AppTheme {
    func appearance(for scheme: ColorScheme) -> ThemeAppearance {
        switch (self, scheme) {
        case (.classic, .light):
            ThemeAppearance(background: 0xF2EEE3, surface: 0xFFFCF4, accent: 0x315D88, ink: 0x292D32, muted: 0x626975,
                            selectionInk: 0xFFFFFF, border: 0xD8D2C3, ornament: 0x6987A0, control: 0xE8EDF0,
                            shadow: 0x4E4534, shadowOpacity: 0.09, shadowRadius: 2, shadowY: 2,
                            surfaceRadius: 8, controlRadius: 8, headingTracking: 0.3, subtitle: "クリームの紙、青いインクと罫線")
        case (.classic, _):
            ThemeAppearance(background: 0x151B23, surface: 0x232C36, accent: 0xD8BB83, ink: 0xF1EBDD, muted: 0xBDB9AE,
                            selectionInk: 0x252018, border: 0x59606A, ornament: 0xB99A61, control: 0x343B43,
                            shadow: 0x000000, shadowOpacity: 0.22, shadowRadius: 4, shadowY: 3,
                            surfaceRadius: 8, controlRadius: 7, headingWeight: .medium, headingTracking: 0.5,
                            subtitle: "濃紺の装丁、金箔とアイボリーの文字")
        case (.sakura, .light):
            ThemeAppearance(background: 0xFFF0F2, surface: 0xFFFAFB, accent: 0xA6395C, ink: 0x432D38, muted: 0x79606D,
                            selectionInk: 0xFFFFFF, border: 0xEDD1DC, ornament: 0xD583A0, control: 0xF8E3EB,
                            shadow: 0xB96786, shadowOpacity: 0.12, shadowRadius: 10, shadowY: 4,
                            surfaceRadius: 22, controlRadius: 18, subtitle: "薄桜の花びら、柔らかな白い余白")
        case (.sakura, _):
            ThemeAppearance(background: 0x1D1828, surface: 0x302536, accent: 0xF0AAC7, ink: 0xF8EAF2, muted: 0xCFB3C5,
                            selectionInk: 0x3B2030, border: 0x695066, ornament: 0xB78FCA, control: 0x473346,
                            shadow: 0x080511, shadowOpacity: 0.28, shadowRadius: 12, shadowY: 5,
                            surfaceRadius: 22, controlRadius: 18, headingWeight: .medium, headingTracking: 0.2,
                            subtitle: "月明かりの夜桜、紫紺と淡い紅色")
        case (.linen, .light):
            ThemeAppearance(background: 0xEAE2D1, surface: 0xF8F3E7, accent: 0x52613C, ink: 0x36382D, muted: 0x62634F,
                            selectionInk: 0xFFFFFF, border: 0xCEC4AE, ornament: 0x988360, control: 0xE7E6D7,
                            shadow: 0x68583C, shadowOpacity: 0.08, shadowRadius: 2, shadowY: 1,
                            surfaceRadius: 12, controlRadius: 10, headingWeight: .medium, headingTracking: 0.3,
                            subtitle: "生成りの織り目、草木のインク")
        case (.linen, _):
            ThemeAppearance(background: 0x241D18, surface: 0x362C24, accent: 0xD9B28B, ink: 0xF1E6D6, muted: 0xC9B59D,
                            selectionInk: 0x312318, border: 0x6E5946, ornament: 0xB7936A, control: 0x4B3D30,
                            shadow: 0x120B05, shadowOpacity: 0.32, shadowRadius: 3, shadowY: 3,
                            surfaceRadius: 10, controlRadius: 8, borderWidth: 1, headingWeight: .medium, headingTracking: 0.4,
                            subtitle: "深い革の色、縫い目と温かな活字")
        case (.midnight, .light):
            ThemeAppearance(background: 0xE8EFF5, surface: 0xF7FAFD, accent: 0x285E82, ink: 0x223747, muted: 0x566D80,
                            selectionInk: 0xFFFFFF, border: 0xBECDD9, ornament: 0x688DA8, control: 0xE0EAF2,
                            shadow: 0x344F66, shadowOpacity: 0.06, shadowRadius: 3, shadowY: 2,
                            surfaceRadius: 14, controlRadius: 10, headingTracking: 0.4, subtitle: "青白い製図用紙、整然とした方眼")
        case (.midnight, _):
            ThemeAppearance(background: 0x101B2B, surface: 0x1B2C40, accent: 0x96CAE7, ink: 0xE4EEF8, muted: 0xADC1D5,
                            selectionInk: 0x152B3C, border: 0x465E76, ornament: 0x83B7D8, control: 0x2B4055,
                            shadow: 0x000714, shadowOpacity: 0.24, shadowRadius: 6, shadowY: 3,
                            surfaceRadius: 12, controlRadius: 9, headingWeight: .medium, headingTracking: 0.6,
                            subtitle: "静かな星図、深い青と銀青の光")
        case (.modern, .light):
            ThemeAppearance(background: 0xF1F2F6, surface: 0xFFFFFF, accent: 0x5C42B5, ink: 0x282833, muted: 0x666575,
                            selectionInk: 0xFFFFFF, border: 0xDEDEE8, ornament: 0xB0A3D7, control: 0xEEEAF9,
                            shadow: 0x45435D, shadowOpacity: 0.10, shadowRadius: 12, shadowY: 5,
                            surfaceRadius: 24, controlRadius: 14, headingWeight: .bold, headingTracking: -0.3,
                            subtitle: "白いSurface、明快な紫と広い余白")
        case (.modern, _):
            ThemeAppearance(background: 0x19191D, surface: 0x29292F, accent: 0xC1B4F6, ink: 0xF0F0F5, muted: 0xBCBAC8,
                            selectionInk: 0x29223F, border: 0x515158, ornament: 0x9A96B0, control: 0x3B374A,
                            shadow: 0x000000, shadowOpacity: 0.24, shadowRadius: 8, shadowY: 4,
                            surfaceRadius: 20, controlRadius: 12, headingTracking: -0.2,
                            subtitle: "チャコールの面、端正なラベンダー")
        }
    }

    func headingFont(_ style: Font.TextStyle, for scheme: ColorScheme) -> Font {
        .system(style, design: headingDesign, weight: appearance(for: scheme).headingWeight)
    }
}

struct ThemeSurface: View {
    let theme: AppTheme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = theme.appearance(for: scheme)
        let shape = RoundedRectangle(cornerRadius: palette.surfaceRadius, style: .continuous)
        shape.fill(palette.surface)
            .overlay {
                shape.strokeBorder(contrast == .increased ? palette.mutedInk : palette.border,
                                   lineWidth: contrast == .increased ? 1.5 : palette.borderWidth)
            }
            .overlay {
                if theme == .linen && scheme == .dark {
                    shape.inset(by: 4).stroke(palette.ornament.opacity(0.28), style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
                }
            }
            .shadow(color: palette.shadow, radius: palette.shadowRadius, y: palette.shadowY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ThemedListRowsModifier: ViewModifier {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let palette = settings.theme.appearance(for: scheme)
        content.listRowBackground(palette.surface).listRowSeparatorTint(palette.border)
    }
}

extension View {
    func themedListRows() -> some View { modifier(ThemedListRowsModifier()) }
}

struct ThemedProminentStyle: ButtonStyle {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let palette = settings.theme.appearance(for: scheme)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .foregroundStyle(isEnabled ? palette.selectionInk : palette.mutedInk)
            .background(isEnabled ? palette.accent : palette.control,
                        in: RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
