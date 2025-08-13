import SwiftUI

// MARK: - Design Tokens (Single Source of Truth)
enum Tokens {
    // Palette (warm watercolor paper vibe)
    static let bgPrimary = Color(hex: "#F6F1E8")
    static let bgWash    = Color(hex: "#EDE6DA")
    static let ink       = Color(hex: "#2F2A25")
    static let accent    = Color(hex: "#7C5C3A")
    static let accentSoft = Color(hex: "#C9B6A0")
    static let paper     = Color.white
    static let shadow    = Color.black.opacity(0.12)

    // Gradient outline for primary button
    static let primaryOutlineGradient = [Color(hex:"#F8C850"), Color(hex:"#F28C3A"), Color(hex:"#E04A3A")]

    // Typography (use system to avoid custom font deps)
    struct Type {
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

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
} 