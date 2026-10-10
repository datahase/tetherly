import SwiftUI
import UIKit

/// Brand tokens sampled from the logo, matching the Android app. Orange is the only accent.
enum Brand {
    static let orange = Color(hex: 0xFD6B0B)
    static let orangeOnLight = Color(hex: 0xC2510A) // AA-contrast orange for text and icons on light surfaces
    static let ink = Color(hex: 0x1C1814)
    static let cream = Color(hex: 0xF7EEDB)

    static let background = dynamic(light: 0xFBF7EE, dark: 0x1C1814)
    static let surface = dynamic(light: 0xF4EEE2, dark: 0x27221E)
    static let surfaceLow = dynamic(light: 0xF8F3E8, dark: 0x221E1A)
    static let surfaceHigh = dynamic(light: 0xEFE8DA, dark: 0x2E2924)
    static let surfaceHighest = dynamic(light: 0xE9E1D1, dark: 0x38322C)
    static let onSurface = dynamic(light: 0x1C1814, dark: 0xF7EEDB)
    static let onSurfaceVariant = dynamic(light: 0x5C5348, dark: 0xCFC5B4)
    static let outline = dynamic(light: 0x8A7F70, dark: 0x7A6F62)
    static let primary = dynamic(light: 0xC2510A, dark: 0xFD6B0B)
    static let onPrimary = dynamic(light: 0xFFFDF8, dark: 0x1C1814)
    static let primaryContainer = dynamic(light: 0xFFDCC7, dark: 0x4A2A14)
    static let onPrimaryContainer = dynamic(light: 0x3A1A05, dark: 0xFFDCC7)
    static let errorContainer = dynamic(light: 0xF9DEDC, dark: 0x4D1F1C)
    static let onErrorContainer = dynamic(light: 0x410E0B, dark: 0xFFDAD6)
    static let error = dynamic(light: 0xB3261E, dark: 0xFF8A80)
    static let available = Color(hex: 0x3FB950)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// The filled orange action used for the one primary thing on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Brand.onPrimary)
            .background(Brand.primary.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Tonal and outlined secondary actions share the 12-point corner radius.
struct SecondaryButtonStyle: ButtonStyle {
    var tonal = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Brand.onSurface.opacity(enabled ? 1 : 0.4))
            .background(tonal ? Brand.surfaceHighest : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay { if !tonal { RoundedRectangle(cornerRadius: 12).stroke(Brand.outline, lineWidth: 1) } }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct BrandMark: View {
    var size: CGFloat = 30
    var body: some View {
        Image("BrandMark").resizable().scaledToFit().padding(size * 0.12)
            .frame(width: size, height: size)
            .background(Brand.ink, in: RoundedRectangle(cornerRadius: size * 0.26))
            .accessibilityHidden(true)
    }
}
