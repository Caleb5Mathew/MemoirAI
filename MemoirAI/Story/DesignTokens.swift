import SwiftUI

// MARK: - Color Helpers (self-contained, no external Color(hex:) needed)
extension Color {
    /// Safe hex parser. Supports #RGB, #RRGGBB, #RRGGBBAA.
    static func safeHex(_ hex: String, fallback: Color) -> Color {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()

        func makeColor(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) -> Color {
            Color(red: Double(r/255), green: Double(g/255), blue: Double(b/255), opacity: Double(a))
        }

        switch cleaned.count {
        case 3: // RGB (12-bit)
            let r = cleaned[0]
            let g = cleaned[1]
            let b = cleaned[2]
            let rr = CGFloat(Int(String([r,r]), radix: 16) ?? 255)
            let gg = CGFloat(Int(String([g,g]), radix: 16) ?? 255)
            let bb = CGFloat(Int(String([b,b]), radix: 16) ?? 255)
            return makeColor(r: rr, g: gg, b: bb)
        case 6, 8:
            var value: UInt64 = 0
            guard Scanner(string: cleaned).scanHexInt64(&value) else { return fallback }
            if cleaned.count == 6 {
                let r = CGFloat((value & 0xFF0000) >> 16)
                let g = CGFloat((value & 0x00FF00) >> 8)
                let b = CGFloat(value & 0x0000FF)
                return makeColor(r: r, g: g, b: b)
            } else {
                let r = CGFloat((value & 0xFF000000) >> 24)
                let g = CGFloat((value & 0x00FF0000) >> 16)
                let b = CGFloat((value & 0x0000FF00) >> 8)
                let a = CGFloat(value & 0x000000FF)
                return makeColor(r: r, g: g, b: b, a: a)
            }
        default:
            return fallback
        }
    }

    // Convenience to index a single hex char
    subscript(i: Int) -> Character {
        Array(String(describing: self))[i]
    }
}

// MARK: - Design Tokens (Single Source of Truth)
enum Tokens {
    // Palette (warm parchment vibe)
    static let bgPrimary = Color.safeHex("#F6F1E8", fallback: Color(red: 0.96, green: 0.94, blue: 0.91))
    static let bgWash    = Color.safeHex("#EDE6DA", fallback: Color(red: 0.93, green: 0.90, blue: 0.85))
    static let ink       = Color.safeHex("#2F2A25", fallback: Color(red: 0.18, green: 0.16, blue: 0.15))
    static let accent    = Color.safeHex("#7C5C3A", fallback: Color(red: 0.49, green: 0.36, blue: 0.23))
    static let accentSoft = Color.safeHex("#C9B6A0", fallback: Color(red: 0.79, green: 0.71, blue: 0.63))
    static let paper     = Color.white
    static let shadow    = Color.black.opacity(0.12)

    // Book-specific
    static let spineColor = Color.safeHex("#8B7355", fallback: Color(red: 0.55, green: 0.45, blue: 0.33))
    static let pageEdgeHighlight = Color.white.opacity(0.8)
    static let gutterShadow = Color.black.opacity(0.08)

    // Gradient outline for primary button
    static let primaryOutlineGradient = [
        Color.safeHex("#F8C850", fallback: Color(red: 0.97, green: 0.78, blue: 0.31)),
        Color.safeHex("#F28C3A", fallback: Color(red: 0.95, green: 0.55, blue: 0.23)),
        Color.safeHex("#E04A3A", fallback: Color(red: 0.88, green: 0.29, blue: 0.23))
    ]
    static var primaryOutlineLinear: LinearGradient {
        LinearGradient(colors: primaryOutlineGradient, startPoint: .leading, endPoint: .trailing)
    }

    // Typography
    struct Typography {
        static let title      = Font.system(size: 30, weight: .semibold, design: .serif)
        static let subtitle   = Font.system(size: 17, weight: .regular, design: .default)
        static let hint       = Font.system(size: 18, weight: .regular, design: .default)
        static let button     = Font.system(size: 20, weight: .semibold, design: .serif)
        static let chapterTitle = Font.system(size: 16, weight: .medium, design: .serif)
        static let caption    = Font.system(size: 14, weight: .regular, design: .default)
    }

    // Sizing
    static let pageAspect: CGFloat = 3.0 / 4.0  // book page ratio (w:h)
    static let bookMaxWidthPct: CGFloat = 0.86  // of safe area width
    static let cornerRadius: CGFloat = 20
    static let softShadow = (radius: CGFloat(14), y: CGFloat(6), opacity: Double(0.22))
    static let chevronSize: CGFloat = 44        // min hit target
    static let spineWidth: CGFloat = 8
    static let pageMargin: CGFloat = 16
    static let gradientStrokeWidth: CGFloat = 2.5

    // Rhythm
    static let headerSpacing: CGFloat = 12
    static let bookSpacing: CGFloat = 20
    static let buttonSpacing: CGFloat = 16
    static let bottomPadding: CGFloat = 30

    // Subtle page shading across the spread (for depth)
    static func pageSideShade(isLeftPage: Bool) -> LinearGradient {
        let leading = Color.black.opacity(isLeftPage ? 0.06 : 0.02)
        let trailing = Color.black.opacity(isLeftPage ? 0.02 : 0.06)
        return LinearGradient(gradient: Gradient(colors: [leading, .clear, trailing]),
                              startPoint: .leading, endPoint: .trailing)
    }

    // Center gutter gradient (spine highlight/shadow)
    static var gutterGradient: LinearGradient {
        LinearGradient(gradient: Gradient(colors: [
            Color.black.opacity(0.08),
            Color.black.opacity(0.02),
            Color.black.opacity(0.08)
        ]), startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Reusable Styles
struct GradientOutlineCapsule: ViewModifier {
    var lineWidth: CGFloat = Tokens.gradientStrokeWidth
    func body(content: Content) -> some View {
        content.overlay(
            Capsule().stroke(Tokens.primaryOutlineLinear, lineWidth: lineWidth)
        )
    }
}

extension View {
    /// Applies the brand gradient outline (yellow→orange→red) to a capsule-shaped button.
    func primaryGradientOutline(lineWidth: CGFloat = Tokens.gradientStrokeWidth) -> some View {
        self.modifier(GradientOutlineCapsule(lineWidth: lineWidth))
    }

    /// A soft drop shadow used across the UI.
    func softDropShadow() -> some View {
        self.shadow(color: Tokens.shadow, radius: Tokens.softShadow.radius, x: 0, y: Tokens.softShadow.y)
    }
}
