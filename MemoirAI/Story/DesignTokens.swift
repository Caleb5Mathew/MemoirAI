import SwiftUI

// MARK: - Color Helper
extension Color {
    static func safeHex(_ hex: String, fallback: Color) -> Color {
        return Color(hex: hex) ?? fallback
    }
}

// MARK: - Design Tokens (Single Source of Truth)
enum Tokens {
    // Palette (warm watercolor paper vibe)
    static let bgPrimary = Color.safeHex("#F6F1E8", fallback: Color(red: 0.96, green: 0.94, blue: 0.91))
    static let bgWash    = Color.safeHex("#EDE6DA", fallback: Color(red: 0.93, green: 0.90, blue: 0.85))
    static let ink       = Color.safeHex("#2F2A25", fallback: Color(red: 0.18, green: 0.16, blue: 0.15))
    static let accent    = Color.safeHex("#7C5C3A", fallback: Color(red: 0.49, green: 0.36, blue: 0.23))
    static let accentSoft = Color.safeHex("#C9B6A0", fallback: Color(red: 0.79, green: 0.71, blue: 0.63))
    static let paper     = Color.white
    static let shadow    = Color.black.opacity(0.12)

    // Gradient outline for primary button
    static let primaryOutlineGradient = [
        Color.safeHex("#F8C850", fallback: Color(red: 0.97, green: 0.78, blue: 0.31)),
        Color.safeHex("#F28C3A", fallback: Color(red: 0.95, green: 0.55, blue: 0.23)),
        Color.safeHex("#E04A3A", fallback: Color(red: 0.88, green: 0.29, blue: 0.23))
    ]

    // Typography (use system to avoid custom font deps)
    struct Typography {
        static let title      = Font.system(size: 28, weight: .semibold, design: .serif)
        static let subtitle   = Font.system(size: 17, weight: .regular, design: .default)
        static let hint       = Font.system(size: 18, weight: .regular, design: .default)
        static let button     = Font.system(size: 20, weight: .semibold, design: .serif)
    }

    // Sizing
    static let pageAspect: CGFloat = 3.0/4.0   // book page ratio (w:h)
    static let bookMaxWidthPct: CGFloat = 0.86 // of safe area width
    static let cornerRadius: CGFloat = 20
    static let softShadow = (radius: CGFloat(14), y: CGFloat(6), opacity: Double(0.22))
}

 