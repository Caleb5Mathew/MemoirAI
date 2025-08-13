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
        case twoPageSpread // kept for compatibility; rendered as left/right variants
    }
}

// MARK: - Sample Book Pages (paired to resemble the mock: left bars → right photo)
extension MockBookPage {
    static let samplePages: [MockBookPage] = [
        // Pair 1 (looks like the screenshot spread)
        MockBookPage(type: .text,  content: "Body paragraph bars", imageName: nil),
        MockBookPage(type: .photo, content: "A short two-line caption underneath the photograph.", imageName: "graduation_photo"),

        // Pair 2
        MockBookPage(type: .text,  content: "Additional body bars", imageName: nil),
        MockBookPage(type: .mixed, content: "The journey wasn't always easy, but each challenge shaped me.", imageName: "family_photo"),

        // Optional cover (won’t be shown in the core mock spread but kept here)
        MockBookPage(type: .cover, content: "Memories of Achievement", imageName: nil)
    ]
}

// MARK: - Two-Page Spread View (compat helper)
// If a page is declared as .twoPageSpread, we render left/right halves depending on isLeftPage.
struct TwoPageSpreadSlice: View {
    let page: MockBookPage
    let isLeftPage: Bool

    var body: some View {
        if isLeftPage {
            ParagraphBars()
        } else {
            PhotoTitleCaption(imageName: page.imageName, caption: "A short two-line caption underneath the photograph.")
        }
    }
}

// MARK: - Book Page View
struct MockBookPageView: View {
    let page: MockBookPage
    let isLeftPage: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Subtle paper shading for depth
                Tokens.paper
                    .overlay(Tokens.pageSideShade(isLeftPage: isLeftPage))

                // Content with generous margins; slightly larger toward spine
                content
                    .padding(.vertical, 22)
                    .padding(.leading, isLeftPage ? 18 : 26)
                    .padding(.trailing, isLeftPage ? 26 : 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page.type {
        case .cover:
            CoverPage(title: page.content)

        case .text:
            ParagraphBars()

        case .photo:
            PhotoTitleCaption(imageName: page.imageName, caption: page.content)

        case .mixed:
            MixedBarsPlusSmallPhoto(imageName: page.imageName)

        case .twoPageSpread:
            TwoPageSpreadSlice(page: page, isLeftPage: isLeftPage)
        }
    }
}

// MARK: - Subviews (clean, reusable pieces)

// Title-only cover (kept minimal for preview)
private struct CoverPage: View {
    let title: String
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Text(title)
                .font(Tokens.Typography.title)
                .foregroundColor(Tokens.ink)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Rectangle()
                .fill(Tokens.accentSoft)
                .frame(width: 60, height: 2)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// Left-page look: 10–14 rounded bars with varied lengths
private struct ParagraphBars: View {
    var body: some View {
        GeometryReader { geo in
            let maxWidth = geo.size.width
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.pattern(count: 12), id: \.self) { fraction in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Tokens.ink.opacity(0.09))
                        .frame(width: max(40, maxWidth * fraction), height: 10, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // Varied line-length fractions (gives the paragraph vibe)
    static func pattern(count: Int) -> [CGFloat] {
        let base: [CGFloat] = [0.92, 0.78, 0.86, 0.70, 0.95, 0.82, 0.65, 0.90, 0.74, 0.88, 0.68, 0.96]
        return (0..<count).map { base[$0 % base.count] }
    }
}

// Right-page look: title + photo + caption (2 lines)
private struct PhotoTitleCaption: View {
    let imageName: String?
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Memories of Achievement")
                .font(Tokens.Typography.chapterTitle.weight(.semibold))
                .foregroundColor(Tokens.ink)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Tokens.bgWash)
                if let name = imageName, let ui = UIImage(named: name) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 36))
                        .foregroundColor(Tokens.accentSoft)
                }
            }
            .frame(height: 200)
            .clipped()

            Text(caption)
                .font(Tokens.Typography.caption)
                .foregroundColor(Tokens.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

// Mixed page: a few bars + smaller photo
private struct MixedBarsPlusSmallPhoto: View {
    let imageName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(ParagraphBars.pattern(count: 5), id: \.self) { fraction in
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Tokens.ink.opacity(0.09))
                        .frame(width: max(40, geo.size.width * fraction), height: 10, alignment: .leading)
                }
                .frame(height: 10)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Tokens.bgWash)
                if let name = imageName, let ui = UIImage(named: name) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundColor(Tokens.accentSoft)
                }
            }
            .frame(height: 120)

            Spacer(minLength: 0)
        }
    }
}
