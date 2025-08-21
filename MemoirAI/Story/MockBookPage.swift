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

// MARK: - Sample Book Pages (emotionally resonant preview content)
extension MockBookPage {
    static let samplePages: [MockBookPage] = [
        // Cover page
        MockBookPage(type: .cover, content: "Our Family Legacy", imageName: nil),
        
        // Story 1: Grandma's Recipe (simplified preview)
        MockBookPage(type: .text, content: "Every Sunday, the aroma of Grandma's apple pie filled our home, carrying with it decades of tradition from the old country.", imageName: nil),
        MockBookPage(type: .photo, content: "Three generations gathering in Grandma's kitchen, where recipes and stories were passed down with love.", imageName: "family_kitchen"),
        
        // Story 2: Dad's Workshop
        MockBookPage(type: .text, content: "In Dad's workshop, among the sawdust and tools, I learned that building things takes patience—just like building a life.", imageName: nil),
        MockBookPage(type: .mixed, content: "The treehouse we built together still stands, a testament to lessons learned with calloused hands and full hearts.", imageName: "workshop_moment"),
        
        // Story 3: Immigration Journey
        MockBookPage(type: .text, content: "They arrived with twenty dollars and infinite hope, seeing America not as it was, but as it could be.", imageName: nil),
        MockBookPage(type: .photo, content: "From Ellis Island to the American Dream—our family's courage written in every sacrifice.", imageName: "family_heritage"),
        
        // Story 4: Mom's Garden
        MockBookPage(type: .mixed, content: "In Mom's garden, we learned that love grows when tended daily, season after season.", imageName: "garden_wisdom")
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
            Text("Treasured Moments")
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
