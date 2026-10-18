import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Colour tokens from the Sigil design canvas.
enum Palette {
    static let ink = Color(hex: 0x111318)
    static let paper = Color(hex: 0xF4F4F0)
    static let card = Color.white
    static let accent = Color(hex: 0x2B45E0)

    static let textSecondary = Color(hex: 0x3D4049)
    static let muted = Color(hex: 0x5B5E66)
    static let mutedOnDark = Color(hex: 0xB3B7C2)
    static let chevron = Color(hex: 0x7A7D85)
    static let segmentOff = Color(hex: 0x4A4D55)

    static let border = Color(hex: 0xE2E2DA)
    static let borderStrong = Color(hex: 0xD4D4CB)
    static let borderButton = Color(hex: 0xDCDCD4)
    static let divider = Color(hex: 0xECECE5)
    static let track = Color(hex: 0xE6E6DF)
    static let segmentTrack = Color(hex: 0xE4E4DC)
    static let dashed = Color(hex: 0xC9C9BF)
    static let dashedChip = Color(hex: 0xB9B9AE)

    static let blueSoft = Color(hex: 0xDDE3FF)
    static let blueInk = Color(hex: 0x1F33B0)

    static let orange = Color(hex: 0xE8833A)
    static let orangeSoft = Color(hex: 0xFCE9D6)
    static let orangeBorder = Color(hex: 0xF2C79E)
    static let orangeInk = Color(hex: 0x7A3D0E)
    static let orangeDeep = Color(hex: 0x5A2A05)
    static let orangeOnFill = Color(hex: 0x2B1402)

    static let graySoft = Color(hex: 0xECECE5)
    static let green = Color(hex: 0x1F9D55)
    static let mint = Color(hex: 0x8FE3B0)
    static let danger = Color(hex: 0xB42318)
    static let dangerSoft = Color(hex: 0xFBE6E3)
}

/// Type scale. The design uses Bricolage Grotesque (display), Geist (body) and
/// Geist Mono (figures); these map to the system faces until the fonts are bundled.
enum Typo {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
