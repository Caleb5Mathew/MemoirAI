import Foundation

// MARK: - FlipPage Model
struct FlipPage: Codable, Identifiable {
    let id = UUID()
    let type: PageType
    let title: String?
    let caption: String?
    let imageBase64: String?
    let imageName: String?
    let textContent: String? // NEW: Full text content for text pages
    let chapterNumber: Int? // NEW: Chapter numbering
    let pageNumber: Int? // NEW: Page numbering within chapter
    let totalPages: Int? // NEW: Total pages in chapter
    
    enum PageType: String, Codable, CaseIterable {
        case cover = "cover"
        case leftBars = "leftBars"
        case rightPhoto = "rightPhoto"
        case mixed = "mixed"
        case html = "html"
        case textPage = "textPage" // NEW: Full text content page
        case textWithImage = "textWithImage" // NEW: Text with accompanying image
        case chapterBreak = "chapterBreak" // NEW: Chapter/section divider
        case imagePage = "imagePage" // NEW: Dedicated image page
    }
    
    init(type: PageType, title: String? = nil, caption: String? = nil, imageBase64: String? = nil, imageName: String? = nil, textContent: String? = nil, chapterNumber: Int? = nil, pageNumber: Int? = nil, totalPages: Int? = nil) {
        self.type = type
        self.title = title
        self.caption = caption
        self.imageBase64 = imageBase64
        self.imageName = imageName
        self.textContent = textContent
        self.chapterNumber = chapterNumber
        self.pageNumber = pageNumber
        self.totalPages = totalPages
    }
}

// MARK: - Sample FlipPages (matching the mock)
extension FlipPage {
    static let samplePages: [FlipPage] = [
        // Cover page FIRST (not last)
        FlipPage(type: .cover, title: "Memories of Achievement"),
        
        // Chapter 1: Early Years
        FlipPage(type: .chapterBreak, title: "Chapter 1", caption: "Early Years", chapterNumber: 1),
        
        FlipPage(type: .textPage, 
                title: "The Foundation", 
                textContent: "The foundation of who I would become was laid in those early days. Every moment, every lesson, every challenge shaped the person I am today. Looking back, I can see how those formative years created the blueprint for my future. The values instilled in me during childhood became the compass that guided my decisions throughout life. Each experience, whether joyful or challenging, contributed to building the resilient and determined person I am today.",
                chapterNumber: 1, pageNumber: 1, totalPages: 2),
        
        FlipPage(type: .textWithImage, 
                title: "First Steps", 
                textContent: "My first steps into the world were filled with wonder and curiosity. Each new experience was a building block for the future. The excitement of discovering new things, the thrill of learning, and the joy of making connections with others all began in those early moments. These experiences taught me that life is an adventure waiting to be explored.",
                caption: "My first steps into the world were filled with wonder and curiosity. Each new experience was a building block for the future.",
                imageName: "childhood_photo",
                chapterNumber: 1, pageNumber: 2, totalPages: 2),
        
        // Chapter 2: Education Journey
        FlipPage(type: .chapterBreak, title: "Chapter 2", caption: "Education Journey", chapterNumber: 2),
        
        FlipPage(type: .textPage, 
                title: "Learning and Growth", 
                textContent: "The classroom became my second home, where knowledge opened doors I never knew existed. Every book, every teacher, every lesson expanded my horizons. The pursuit of education taught me discipline, critical thinking, and the value of continuous learning. These skills would serve me well throughout my life, opening opportunities I could never have imagined as a child.",
                chapterNumber: 2, pageNumber: 1, totalPages: 2),
        
        FlipPage(type: .imagePage, 
                title: "Graduation Day", 
                caption: "Walking across that stage, I realized that every late night studying, every challenge overcome, had led to this moment of achievement. The ceremony marked not just the end of one chapter, but the beginning of a new adventure filled with possibilities and opportunities to make a difference in the world.",
                imageName: "graduation_photo",
                chapterNumber: 2, pageNumber: 2, totalPages: 2),
        
        // Chapter 3: Career Beginnings
        FlipPage(type: .chapterBreak, title: "Chapter 3", caption: "Career Beginnings", chapterNumber: 3),
        
        FlipPage(type: .textPage, 
                title: "Professional Path", 
                textContent: "Entering the workforce was both exciting and daunting. Each job taught me new skills, introduced me to amazing people, and helped me discover my true passions. The transition from student to professional required adaptability, resilience, and a willingness to learn from every experience. These early career years shaped my work ethic and professional values.",
                chapterNumber: 3, pageNumber: 1, totalPages: 2),
        
        FlipPage(type: .textWithImage, 
                title: "First Job", 
                textContent: "My first real job felt like stepping into adulthood. The responsibility was overwhelming at first, but I quickly learned to embrace the challenge. Every day brought new lessons about teamwork, problem-solving, and personal growth. This experience taught me that success comes from dedication, hard work, and the courage to step outside my comfort zone.",
                caption: "My first real job felt like stepping into adulthood. The responsibility was overwhelming at first, but I quickly learned to embrace the challenge.",
                imageName: "first_job_photo",
                chapterNumber: 3, pageNumber: 2, totalPages: 2),
        
        // Chapter 4: Life Lessons
        FlipPage(type: .chapterBreak, title: "Chapter 4", caption: "Life Lessons", chapterNumber: 4),
        
        FlipPage(type: .textPage, 
                title: "Wisdom Gained", 
                textContent: "Life has a way of teaching us the most important lessons when we least expect them. Every setback became a setup for something greater. Through challenges and triumphs, I learned that resilience is built through adversity, that failure is often the best teacher, and that success is sweeter when shared with others. These lessons became the foundation of my character.",
                chapterNumber: 4, pageNumber: 1, totalPages: 2),
        
        FlipPage(type: .mixed, 
                title: "Family Moments", 
                caption: "The most precious memories are those shared with family. These moments of love, laughter, and togetherness are what truly matter in life. Family taught me the importance of unconditional love, the value of traditions, and the strength that comes from knowing you have people who will always support you.",
                imageName: "family_photo",
                chapterNumber: 4, pageNumber: 2, totalPages: 2),
        
        // Chapter 5: Achievements
        FlipPage(type: .chapterBreak, title: "Chapter 5", caption: "Achievements", chapterNumber: 5),
        
        FlipPage(type: .textPage, 
                title: "Milestones Reached", 
                textContent: "Looking back on my accomplishments, I realize that success isn't just about reaching goals—it's about the person you become along the way. Each achievement represents not just a moment of triumph, but the culmination of countless hours of effort, determination, and growth. These milestones remind me that dreams are achievable through persistence and hard work.",
                chapterNumber: 5, pageNumber: 1, totalPages: 2),
        
        FlipPage(type: .imagePage, 
                title: "Milestone Moments", 
                caption: "Each milestone reached was a celebration not just of achievement, but of perseverance, determination, and the support of those who believed in me. These moments remind me that success is a journey, not a destination, and that the greatest rewards come from the relationships we build and the lives we touch along the way.",
                imageName: "achievement_photo",
                chapterNumber: 5, pageNumber: 2, totalPages: 2)
    ]
    
    // Convert MockBookPage to FlipPage
    static func fromMockBookPage(_ mockPage: MockBookPage) -> FlipPage {
        switch mockPage.type {
        case .cover:
            return FlipPage(type: .cover, title: mockPage.content)
        case .text:
            return FlipPage(type: .textPage, textContent: mockPage.content)
        case .photo:
            return FlipPage(type: .imagePage, title: "Memories of Achievement", caption: mockPage.content, imageName: mockPage.imageName)
        case .mixed:
            return FlipPage(type: .textWithImage, caption: mockPage.content, imageName: mockPage.imageName)
        case .twoPageSpread:
            // For two-page spreads, we'll create separate left/right pages
            return FlipPage(type: .textPage, textContent: mockPage.content)
        }
    }
} 