import SwiftUI

// MARK: - Open Book View (unified spread with spine + outside chevrons)
struct OpenBookView: View {
    let pages: [MockBookPage]
    @Binding var currentPage: Int
    let bookWidth: CGFloat
    let bookHeight: CGFloat

    // Layout tunables
    private var pageInset: CGFloat { max(12, bookWidth * 0.02) } // inner margins
    private let notchSize = CGSize(width: 36, height: 10)

    var body: some View {
        ZStack {
            // Back cover/frame
            RoundedRectangle(cornerRadius: Tokens.cornerRadius + 6)
                .fill(Tokens.paper.opacity(0.0))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.cornerRadius + 6)
                        .stroke(Tokens.accentSoft.opacity(0.35), lineWidth: 1)
                )
                .softDropShadow()

            // Inner two-page spread (single container — no “two cards”)
            ZStack {
                // Paper spread with depth
                RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                    .fill(Tokens.paper)
                    .softDropShadow()

                // Subtle side shading to imply curvature
                HStack(spacing: 0) {
                    Tokens.pageSideShade(isLeftPage: true)
                    Tokens.pageSideShade(isLeftPage: false)
                }
                .clipShape(RoundedRectangle(cornerRadius: Tokens.cornerRadius))

                // Center spine/gutter
                Tokens.gutterGradient
                    .frame(width: Tokens.spineWidth)
                    .blur(radius: 1)
                    .allowsHitTesting(false)

                // Tiny bottom notch/hinge
                VStack {
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(Color.black.opacity(0.12))
                        .frame(width: notchSize.width, height: notchSize.height)
                        .offset(y: 6)
                }
                .allowsHitTesting(false)
            }

            // Page content with natural margins, clipped to the spread
            PageCurlBookController(pages: pages, currentPage: $currentPage)
                .padding(.all, pageInset)
                .clipShape(RoundedRectangle(cornerRadius: max(8, Tokens.cornerRadius - 2)))

            // Outside chevrons (do not overlap page bounds)
            if pages.count > 1 {
                HStack {
                    arrowButton(system: "chevron.left",
                                disabled: currentPage == 0,
                                accessibility: "Previous page") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if currentPage > 0 { currentPage -= 1; hapticFeedback() }
                        }
                    }

                    Spacer(minLength: 0)

                    arrowButton(system: "chevron.right",
                                disabled: currentPage >= pages.count - 1,
                                accessibility: "Next page") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if currentPage < pages.count - 1 { currentPage += 1; hapticFeedback() }
                        }
                    }
                }
                // Make the chevrons’ centers sit outside the spread by ~12–16pt
                .frame(width: bookWidth + Tokens.chevronSize * 0.8, height: bookHeight)
            }
        }
        .frame(width: bookWidth, height: bookHeight)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Chevron style
    private func arrowButton(system: String,
                             disabled: Bool,
                             accessibility: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Tokens.paper.opacity(0.85))
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: Tokens.shadow.opacity(0.4), radius: 2, x: 0, y: 1)

                Image(systemName: system)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Tokens.ink.opacity(disabled ? 0.35 : 0.7))
            }
            .frame(width: Tokens.chevronSize, height: Tokens.chevronSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
        .accessibilityLabel(accessibility)
    }

    private func hapticFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
