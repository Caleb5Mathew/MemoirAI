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
        
        // Memory 1: Early Years
        FlipPage(type: .leftBars, title: "Early Years", caption: "The foundation of who I would become was laid in those early days. Every moment, every lesson, every challenge shaped the person I am today."),
        FlipPage(type: .rightPhoto, title: "First Steps", caption: "My first steps into the world were filled with wonder and curiosity. Each new experience was a building block for the future.", imageName: "childhood_photo"),
        
        // Memory 2: Education Journey
        FlipPage(type: .leftBars, title: "Education Journey", caption: "The classroom became my second home, where knowledge opened doors I never knew existed. Every book, every teacher, every lesson expanded my horizons."),
        FlipPage(type: .rightPhoto, title: "Graduation Day", caption: "Walking across that stage, I realized that every late night studying, every challenge overcome, had led to this moment of achievement.", imageName: "graduation_photo"),
        
        // Memory 3: Career Beginnings
        FlipPage(type: .leftBars, title: "Career Beginnings", caption: "Entering the workforce was both exciting and daunting. Each job taught me new skills, introduced me to amazing people, and helped me discover my true passions."),
        FlipPage(type: .rightPhoto, title: "First Job", caption: "My first real job felt like stepping into adulthood. The responsibility was overwhelming at first, but I quickly learned to embrace the challenge.", imageName: "first_job_photo"),
        
        // Memory 4: Life Lessons
        FlipPage(type: .leftBars, title: "Life Lessons", caption: "Life has a way of teaching us the most important lessons when we least expect them. Every setback became a setup for something greater."),
        FlipPage(type: .mixed, title: "Family Moments", caption: "The most precious memories are those shared with family. These moments of love, laughter, and togetherness are what truly matter in life.", imageName: "family_photo"),
        
        // Memory 5: Achievements
        FlipPage(type: .leftBars, title: "Achievements", caption: "Looking back on my accomplishments, I realize that success isn't just about reaching goals—it's about the person you become along the way."),
        FlipPage(type: .rightPhoto, title: "Milestone Moments", caption: "Each milestone reached was a celebration not just of achievement, but of perseverance, determination, and the support of those who believed in me.", imageName: "achievement_photo")
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