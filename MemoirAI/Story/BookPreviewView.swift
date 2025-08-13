import SwiftUI

// MARK: - Book Preview View (open-book frame w/ spine + outside chevrons)
struct BookPreviewView: View {
    let pages: [MockBookPage]
    @Binding var currentPage: Int
    let bookWidth: CGFloat
    let bookHeight: CGFloat

    // Tunables for the look
    private var pageInset: CGFloat { max(12, bookWidth * 0.02) }     // inner padding around the page stack
    private let spineWidth: CGFloat = 8                              // center gutter thickness

    var body: some View {
        ZStack {
            // Back cover / frame (gives the hardbound edge feel)
            RoundedRectangle(cornerRadius: Tokens.cornerRadius + 6)
                .fill(Tokens.paper.opacity(0.0))
                .overlay(
                                RoundedRectangle(cornerRadius: Tokens.cornerRadius + 6)
                .stroke(Tokens.accentSoft.opacity(0.35), lineWidth: 1)
                .shadow(color: Tokens.shadow, radius: Tokens.softShadow.0, x: 0, y: Tokens.softShadow.1)
                )

            // Inner pages area with subtle paper + spine/gutter
            ZStack {
                // Two-page spread background
                RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                    .fill(Tokens.paper)
                    .shadow(color: Tokens.shadow.opacity(0.45), radius: 8, x: 0, y: 3)

                // Center spine/gutter: soft gradient + slight inner shadow
                VStack {
                    Spacer(minLength: 0)
                    // tiny "notch" at bottom like the mock
                    Capsule()
                        .fill(Color.black.opacity(0.12))
                        .frame(width: 36, height: 10)
                        .offset(y: 6)
                }
                .allowsHitTesting(false)

                // Vertical gutter highlight/shadow down the middle
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.08),
                                Color.black.opacity(0.02),
                                Color.black.opacity(0.08)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: spineWidth)
                    .blur(radius: 1.0)
            }
            .padding(.horizontal, 4) // tiny inner breathing from the frame

            // Page curl controller content inset so margins look like a real book
            PageCurlBookController(pages: pages, currentPage: $currentPage)
                .padding(EdgeInsets(top: pageInset, leading: pageInset, bottom: pageInset, trailing: pageInset))
                .clipShape(RoundedRectangle(cornerRadius: max(8, Tokens.cornerRadius - 2)))

            // Outside chevrons (don’t cover the page)
            if pages.count > 1 {
                HStack {
                    // Left
                    arrowButton(system: "chevron.left", disabled: currentPage == 0) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if currentPage > 0 { currentPage -= 1 }
                        }
                    }
                    .accessibilityLabel("Previous page")

                    Spacer(minLength: 0)

                    // Right
                    arrowButton(system: "chevron.right", disabled: currentPage >= pages.count - 1) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if currentPage < pages.count - 1 { currentPage += 1 }
                        }
                    }
                    .accessibilityLabel("Next page")
                }
                // Push the chevrons slightly *outside* the page bounds
                .padding(.horizontal, bookWidth * 0.03)
                .frame(width: bookWidth + bookWidth * 0.08, height: bookHeight) // a touch wider than the book
            }
        }
        .frame(width: bookWidth, height: bookHeight)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Chevron style
    private func arrowButton(system: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Tokens.paper.opacity(0.75))
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: Tokens.shadow.opacity(0.4), radius: 2, x: 0, y: 1)

                Image(systemName: system)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Tokens.ink.opacity(disabled ? 0.35 : 0.7))
            }
            .frame(width: 36, height: 36) // ≥ 44 is ideal; these sit outside the page
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
        .contentShape(Rectangle())
    }
}

// MARK: - Blank Book Cover View (kept for empty state)
struct BlankBookCoverView: View {
    let bookWidth: CGFloat
    let bookHeight: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.cornerRadius + 6)
                .fill(Tokens.paper)
                .shadow(color: Tokens.shadow, radius: Tokens.softShadow.0, x: 0, y: Tokens.softShadow.1)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.cornerRadius + 6)
                        .stroke(Tokens.accentSoft.opacity(0.35), lineWidth: 1)
                )

            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "book.closed")
                    .font(.system(size: 56))
                    .foregroundColor(Tokens.accentSoft)
                Text("Your Story Awaits")
                    .font(Tokens.Typography.title)
                    .foregroundColor(Tokens.ink)
                Text("Start creating your memoir to see your story come to life")
                    .font(Tokens.Typography.subtitle)
                    .foregroundColor(Tokens.ink.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
                Rectangle()
                    .fill(Tokens.accentSoft)
                    .frame(width: 60, height: 2)
                    .padding(.bottom, 20)
            }
            .padding(40)
        }
        .frame(width: bookWidth, height: bookHeight)
    }
}
