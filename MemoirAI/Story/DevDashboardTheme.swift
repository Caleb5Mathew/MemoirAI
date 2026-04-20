import SwiftUI

enum DevDashboardPalette {
    static let bgTop = Color(red: 0.03, green: 0.05, blue: 0.11)
    static let bgMid = Color(red: 0.05, green: 0.09, blue: 0.17)
    static let bgBottom = Color(red: 0.03, green: 0.06, blue: 0.14)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.86)
    static let tertiaryText = Color.white.opacity(0.72)
    static let mutedText = Color.white.opacity(0.6)

    static let accentA = Color(red: 0.41, green: 0.91, blue: 1.0)
    static let accentB = Color(red: 0.57, green: 0.62, blue: 1.0)
}

struct DevDashboardBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                DevDashboardPalette.bgTop,
                DevDashboardPalette.bgMid,
                DevDashboardPalette.bgBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [DevDashboardPalette.accentA.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 50,
                endRadius: 460
            )
        )
        .ignoresSafeArea()
    }
}

private struct DevGlassCardModifier: ViewModifier {
    let radius: CGFloat
    let fillOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(fillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.26),
                                        Color.white.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.34), radius: 16, x: 0, y: 10)
    }
}

struct DevDashboardIconBadge: View {
    let systemImage: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DevDashboardPalette.accentA.opacity(0.3), DevDashboardPalette.accentB.opacity(0.34)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )

            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(DevDashboardPalette.accentA)
        }
    }
}

struct DevDashboardInputStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(DevDashboardPalette.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func devGlassCard(radius: CGFloat = 16, fillOpacity: Double = 0.1) -> some View {
        modifier(DevGlassCardModifier(radius: radius, fillOpacity: fillOpacity))
    }
}
