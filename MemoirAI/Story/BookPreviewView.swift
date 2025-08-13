import SwiftUI

// MARK: - Book Preview View
struct BookPreviewView: View {
    let pages: [MockBookPage]
    @Binding var currentPage: Int
    let bookWidth: CGFloat
    let bookHeight: CGFloat
    
    var body: some View {
        ZStack {
            // Book container with shadow
            RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                .fill(Tokens.paper)
                .shadow(
                    color: Tokens.shadow,
                    radius: Tokens.softShadow.radius,
                    x: 0,
                    y: Tokens.softShadow.y
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                        .stroke(Tokens.accentSoft.opacity(0.3), lineWidth: 1)
                )
            
            // Page curl book controller
            PageCurlBookController(pages: pages, currentPage: $currentPage)
                .frame(width: bookWidth * 0.9, height: bookHeight * 0.9)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.cornerRadius - 4))
            
            // Navigation arrows
            if pages.count > 1 {
                HStack {
                    // Left arrow
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if currentPage > 0 {
                                currentPage -= 1
                            }
                        }
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 40, weight: .thin))
                            .foregroundColor(Tokens.ink.opacity(0.7))
                            .shadow(color: Tokens.shadow, radius: 3)
                    }
                    .disabled(currentPage == 0)
                    .opacity(currentPage == 0 ? 0.3 : 1.0)
                    
                    Spacer()
                    
                    // Right arrow
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if currentPage < pages.count - 1 {
                                currentPage += 1
                            }
                        }
                    }) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 40, weight: .thin))
                            .foregroundColor(Tokens.ink.opacity(0.7))
                            .shadow(color: Tokens.shadow, radius: 3)
                    }
                    .disabled(currentPage == pages.count - 1)
                    .opacity(currentPage == pages.count - 1 ? 0.3 : 1.0)
                }
                .padding(.horizontal, bookWidth * 0.05)
                .frame(width: bookWidth)
            }
        }
        .frame(width: bookWidth, height: bookHeight)
    }
}

// MARK: - Blank Book Cover View
struct BlankBookCoverView: View {
    let bookWidth: CGFloat
    let bookHeight: CGFloat
    
    var body: some View {
        ZStack {
            // Book container with shadow
            RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                .fill(Tokens.paper)
                .shadow(
                    color: Tokens.shadow,
                    radius: Tokens.softShadow.radius,
                    x: 0,
                    y: Tokens.softShadow.y
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                        .stroke(Tokens.accentSoft.opacity(0.3), lineWidth: 1)
                )
            
            // Blank cover content
            VStack(spacing: 20) {
                Spacer()
                
                Image(systemName: "book.closed")
                    .font(.system(size: 60))
                    .foregroundColor(Tokens.accentSoft)
                
                Text("Your Story Awaits")
                    .font(Tokens.Type.title)
                    .foregroundColor(Tokens.ink)
                    .multilineTextAlignment(.center)
                
                Text("Start creating your memoir to see your story come to life")
                    .font(Tokens.Type.subtitle)
                    .foregroundColor(Tokens.ink.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Spacer()
                
                // Decorative element
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