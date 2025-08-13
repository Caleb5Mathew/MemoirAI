import SwiftUI

// MARK: - Mock Book Page Data
struct MockBookPage {
    let id = UUID()
    let type: PageType
    let content: String
    let imageName: String?
    
    enum PageType {
        case cover
        case text
        case photo
        case mixed
    }
}

// MARK: - Sample Book Pages
extension MockBookPage {
    static let samplePages: [MockBookPage] = [
        MockBookPage(type: .cover, content: "Memories of Achievement", imageName: nil),
        MockBookPage(type: .text, content: "In the spring of 1985, I found myself standing at the threshold of what would become the most transformative period of my life. The air was thick with possibility, and every decision felt like it carried the weight of a thousand tomorrows.", imageName: nil),
        MockBookPage(type: .photo, content: "A short two-line caption underneath the photograph.", imageName: "graduation_photo"),
        MockBookPage(type: .mixed, content: "The journey wasn't always easy, but looking back now, I can see how each challenge shaped me into the person I am today.", imageName: "family_photo"),
        MockBookPage(type: .text, content: "My grandmother used to say that life is like a book - each chapter brings new characters, new settings, and new lessons to learn. She was right, of course. Every memory I've collected is like a page in the story of my life.", imageName: nil)
    ]
}

// MARK: - Book Page View
struct MockBookPageView: View {
    let page: MockBookPage
    let isLeftPage: Bool
    
    var body: some View {
        ZStack {
            // Page background
            Tokens.paper
                .shadow(color: Tokens.shadow, radius: 2, x: 0, y: 1)
            
            VStack(spacing: 16) {
                switch page.type {
                case .cover:
                    coverPage
                case .text:
                    textPage
                case .photo:
                    photoPage
                case .mixed:
                    mixedPage
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var coverPage: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text(page.content)
                .font(Tokens.Typography.title)
                .foregroundColor(Tokens.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            // Decorative element
            Rectangle()
                .fill(Tokens.accentSoft)
                .frame(width: 60, height: 2)
                .padding(.bottom, 20)
        }
    }
    
    private var textPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(page.content)
                .font(Tokens.Typography.subtitle)
                .foregroundColor(Tokens.ink)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            // Page number
            HStack {
                if isLeftPage {
                    Text("1")
                        .font(Tokens.Typography.hint)
                        .foregroundColor(Tokens.accentSoft)
                }
                Spacer()
                if !isLeftPage {
                    Text("2")
                        .font(Tokens.Typography.hint)
                        .foregroundColor(Tokens.accentSoft)
                }
            }
        }
    }
    
    private var photoPage: some View {
        VStack(spacing: 16) {
            // Title
            Text("Memories of Achievement:")
                .font(Tokens.Typography.subtitle)
                .foregroundColor(Tokens.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Photo placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Tokens.bgWash)
                .frame(height: 200)
                .overlay(
                    VStack {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(Tokens.accentSoft)
                        Text("Photo Placeholder")
                            .font(Tokens.Typography.hint)
                            .foregroundColor(Tokens.accentSoft)
                    }
                )
            
            // Caption
            Text(page.content)
                .font(Tokens.Typography.hint)
                .foregroundColor(Tokens.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Page numbers
            HStack {
                if isLeftPage {
                    Text("3")
                        .font(Tokens.Typography.hint)
                        .foregroundColor(Tokens.accentSoft)
                }
                Spacer()
                if !isLeftPage {
                    Text("4")
                        .font(Tokens.Typography.hint)
                        .foregroundColor(Tokens.accentSoft)
                }
            }
        }
    }
    
    private var mixedPage: some View {
        VStack(spacing: 16) {
            // Text content
            Text(page.content)
                .font(Tokens.Typography.subtitle)
                .foregroundColor(Tokens.ink)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
            
            // Small photo
            RoundedRectangle(cornerRadius: 6)
                .fill(Tokens.bgWash)
                .frame(height: 120)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundColor(Tokens.accentSoft)
                )
            
            Spacer()
            
            // Page numbers
            HStack {
                if isLeftPage {
                    Text("5")
                        .font(Tokens.Typography.hint)
                        .foregroundColor(Tokens.accentSoft)
                }
                Spacer()
                if !isLeftPage {
                    Text("6")
                        .font(Tokens.Typography.hint)
                        .foregroundColor(Tokens.accentSoft)
                }
            }
        }
    }
} 