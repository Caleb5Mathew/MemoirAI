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
        case twoPageSpread // New type for the specific mock layout
    }
}

// MARK: - Sample Book Pages
extension MockBookPage {
    static let samplePages: [MockBookPage] = [
        MockBookPage(type: .cover, content: "Memories of Achievement", imageName: nil),
        MockBookPage(type: .twoPageSpread, content: "Memories of Achievement", imageName: "graduation_photo"),
        MockBookPage(type: .text, content: "In the spring of 1985, I found myself standing at the threshold of what would become the most transformative period of my life. The air was thick with possibility, and every decision felt like it carried the weight of a thousand tomorrows.", imageName: nil),
        MockBookPage(type: .mixed, content: "The journey wasn't always easy, but looking back now, I can see how each challenge shaped me into the person I am today.", imageName: "family_photo"),
        MockBookPage(type: .text, content: "My grandmother used to say that life is like a book - each chapter brings new characters, new settings, and new lessons to learn. She was right, of course. Every memory I've collected is like a page in the story of my life.", imageName: nil)
    ]
}

// MARK: - Two-Page Spread View (Main Mock Layout)
struct TwoPageSpreadView: View {
    let page: MockBookPage
    
    var body: some View {
        HStack(spacing: 0) {
            // Left page - Text bars
            leftPage
            
            // Right page - Title + Photo + Caption
            rightPage
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var leftPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 5-7 grey text bars to imply paragraphs (exactly as in mock)
            VStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Tokens.ink.opacity(0.3))
                        .frame(height: 12)
                        .frame(maxWidth: .infinity)
                        .frame(width: [0.8, 0.9, 0.7, 0.85, 0.75, 0.95][index] * UIScreen.main.bounds.width * 0.25)
                }
            }
            .padding(.top, 16)
            
            Spacer()
        }
        .padding(Tokens.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.paper)
    }
    
    private var rightPage: some View {
        VStack(spacing: 16) {
            // Small chapter title (exactly as in mock)
            Text("Memories of Achievement")
                .font(Tokens.Typography.chapterTitle)
                .foregroundColor(Tokens.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
            
            // Photo placeholder with rounded corners (4-6pt radius as specified)
            RoundedRectangle(cornerRadius: 6)
                .fill(Tokens.bgWash)
                .frame(height: 160)
                .overlay(
                    VStack {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundColor(Tokens.accentSoft)
                        Text("Photo")
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Tokens.accentSoft)
                    }
                )
            
            // Two-line caption (exactly as in mock)
            VStack(alignment: .leading, spacing: 2) {
                Text("A short two-line caption")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.ink)
                Text("underneath the photograph.")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding(Tokens.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.paper)
    }
}

// MARK: - Book Page View
struct MockBookPageView: View {
    let page: MockBookPage
    let isLeftPage: Bool
    
    var body: some View {
        ZStack {
            // Page background
            Tokens.paper
            
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
                case .twoPageSpread:
                    TwoPageSpreadView(page: page)
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
            // 5-7 grey text bars to imply paragraphs
            VStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Tokens.ink.opacity(0.3))
                        .frame(height: 12)
                        .frame(maxWidth: .infinity)
                        .frame(width: [0.8, 0.9, 0.7, 0.85, 0.75, 0.95][index] * UIScreen.main.bounds.width * 0.3)
                }
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(Tokens.pageMargin)
    }
    
    private var photoPage: some View {
        VStack(spacing: 16) {
            // Small chapter title
            Text("Memories of Achievement")
                .font(Tokens.Typography.chapterTitle)
                .foregroundColor(Tokens.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            
            // Photo placeholder with rounded corners
            RoundedRectangle(cornerRadius: 6)
                .fill(Tokens.bgWash)
                .frame(height: 160)
                .overlay(
                    VStack {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundColor(Tokens.accentSoft)
                        Text("Photo")
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Tokens.accentSoft)
                    }
                )
            
            // Two-line caption
            VStack(alignment: .leading, spacing: 2) {
                Text("A short two-line caption")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.ink)
                Text("underneath the photograph.")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Tokens.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .padding(Tokens.pageMargin)
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
        }
        .padding(Tokens.pageMargin)
    }
} 