import Foundation

// MARK: - FlipPage Model
struct FlipPage: Codable, Identifiable {
    let id = UUID()
    let type: PageType
    let title: String?
    let caption: String?
    let imageBase64: String?
    let imageName: String?
    
    enum PageType: String, Codable, CaseIterable {
        case cover = "cover"
        case leftBars = "leftBars"
        case rightPhoto = "rightPhoto"
        case mixed = "mixed"
        case html = "html"
    }
    
    init(type: PageType, title: String? = nil, caption: String? = nil, imageBase64: String? = nil, imageName: String? = nil) {
        self.type = type
        self.title = title
        self.caption = caption
        self.imageBase64 = imageBase64
        self.imageName = imageName
    }
}

// MARK: - Sample FlipPages (matching the mock)
extension FlipPage {
    static let samplePages: [FlipPage] = [
        // Cover page FIRST (not last)
        FlipPage(type: .cover, title: "Memories of Achievement"),
        
        // Pair 1 (looks like the screenshot spread)
        FlipPage(type: .leftBars, title: nil, caption: "Body paragraph bars"),
        FlipPage(type: .rightPhoto, title: "Memories of Achievement", caption: "A short two-line caption underneath the photograph.", imageName: "graduation_photo"),
        
        // Pair 2
        FlipPage(type: .leftBars, title: nil, caption: "Additional body bars"),
        FlipPage(type: .mixed, title: nil, caption: "The journey wasn't always easy, but each challenge shaped me.", imageName: "family_photo")
    ]
    
    // Convert MockBookPage to FlipPage
    static func fromMockBookPage(_ mockPage: MockBookPage) -> FlipPage {
        switch mockPage.type {
        case .cover:
            return FlipPage(type: .cover, title: mockPage.content)
        case .text:
            return FlipPage(type: .leftBars, caption: mockPage.content)
        case .photo:
            return FlipPage(type: .rightPhoto, title: "Memories of Achievement", caption: mockPage.content, imageName: mockPage.imageName)
        case .mixed:
            return FlipPage(type: .mixed, caption: mockPage.content, imageName: mockPage.imageName)
        case .twoPageSpread:
            // For two-page spreads, we'll create separate left/right pages
            return FlipPage(type: .leftBars, caption: mockPage.content)
        }
    }
} 