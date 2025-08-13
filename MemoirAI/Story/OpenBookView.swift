import SwiftUI

// MARK: - Open Book View
struct OpenBookView: View {
    let pages: [MockBookPage]
    @Binding var currentPage: Int
    let bookWidth: CGFloat
    let bookHeight: CGFloat
    
    var body: some View {
        ZStack {
            // Main book container
            HStack(spacing: 0) {
                // Left page
                leftPage
                
                // Spine/gutter
                spine
                
                // Right page
                rightPage
            }
            .frame(width: bookWidth, height: bookHeight)
            .shadow(color: Tokens.shadow, radius: 12, x: 0, y: 6)
            
            // Navigation chevrons (outside page edges, vertically centered)
            if pages.count > 1 {
                HStack {
                    // Left chevron
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if currentPage > 0 {
                                currentPage -= 1
                                hapticFeedback()
                            }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Tokens.bgWash.opacity(0.8))
                                .frame(width: Tokens.chevronSize, height: Tokens.chevronSize)
                                .shadow(color: Tokens.shadow.opacity(0.3), radius: 2, x: 0, y: 1)
                            
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Tokens.ink.opacity(0.7))
                        }
                    }
                    .disabled(currentPage == 0)
                    .opacity(currentPage == 0 ? 0.3 : 1.0)
                    .accessibilityLabel("Previous page")
                    
                    Spacer()
                    
                    // Right chevron
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if currentPage < pages.count - 1 {
                                currentPage += 1
                                hapticFeedback()
                            }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Tokens.bgWash.opacity(0.8))
                                .frame(width: Tokens.chevronSize, height: Tokens.chevronSize)
                                .shadow(color: Tokens.shadow.opacity(0.3), radius: 2, x: 0, y: 1)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Tokens.ink.opacity(0.7))
                        }
                    }
                    .disabled(currentPage == pages.count - 1)
                    .opacity(currentPage == pages.count - 1 ? 0.3 : 1.0)
                    .accessibilityLabel("Next page")
                }
                .padding(.horizontal, -Tokens.chevronSize/2)
                .frame(width: bookWidth + Tokens.chevronSize)
            }
        }
    }
    
    private var leftPage: some View {
        ZStack {
            // Page background with subtle texture
            Tokens.paper
                .overlay(
                    // Very subtle noise texture
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(0.02),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            
            // Page content - render the left side of the spread
            if currentPage < pages.count {
                let page = pages[currentPage]
                if page.type == .twoPageSpread {
                    // For two-page spread, show left side content
                    TwoPageSpreadView(page: page)
                        .mask(
                            Rectangle()
                                .frame(width: (bookWidth - Tokens.spineWidth) / 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                } else {
                    // For single pages, show full content
                    MockBookPageView(page: page, isLeftPage: true)
                }
            }
            
            // Page edge highlight
            Rectangle()
                .fill(Tokens.pageEdgeHighlight)
                .frame(width: 2)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                .stroke(Tokens.accentSoft.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private var spine: some View {
        ZStack {
            // Spine background
            Tokens.spineColor
            
            // Inner shadow for gutter effect
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Tokens.gutterShadow,
                            Color.clear,
                            Tokens.gutterShadow
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .frame(width: Tokens.spineWidth)
    }
    
    private var rightPage: some View {
        ZStack {
            // Page background with subtle texture
            Tokens.paper
                .overlay(
                    // Very subtle noise texture
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(0.02),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            
            // Page content - render the right side of the spread
            if currentPage < pages.count {
                let page = pages[currentPage]
                if page.type == .twoPageSpread {
                    // For two-page spread, show right side content
                    TwoPageSpreadView(page: page)
                        .mask(
                            Rectangle()
                                .frame(width: (bookWidth - Tokens.spineWidth) / 2)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        )
                } else {
                    // For single pages, show full content
                    MockBookPageView(page: page, isLeftPage: false)
                }
            }
            
            // Page edge highlight
            Rectangle()
                .fill(Tokens.pageEdgeHighlight)
                .frame(width: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                .stroke(Tokens.accentSoft.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private func hapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
} 