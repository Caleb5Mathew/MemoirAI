import SwiftUI

enum LinenTheme {
    static let paper = Color(hex: "F8F3E9")
    static let ink = Color(hex: "362D25")
    static let secondary = Color(hex: "74695F")
    static let surface = Color(hex: "EAE1D2")
    static let accent = Color(hex: "98583D")
    static let onAccent = Color(hex: "FFF7E8")
    static let line = Color(hex: "D9CEBD")
    static let forest = Color(hex: "3F5546")
    static let card = Color(hex: "E8DCC8")

    static func heading(_ size: CGFloat = 25) -> Font {
        .custom("Fraunces-Regular", size: size, relativeTo: .title2)
    }

    static func body(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "DMSans-Bold"
        case .semibold: name = "DMSans-SemiBold"
        case .medium: name = "DMSans-Medium"
        default: name = "DMSans-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }
}

extension View {
    func linenScreen() -> some View {
        self
            .font(LinenTheme.body())
            .foregroundStyle(LinenTheme.ink)
            .tint(LinenTheme.accent)
            .background(LinenTheme.paper.ignoresSafeArea())
            .toolbarBackground(LinenTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
