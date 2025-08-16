import Foundation

// MARK: - FlipPage Model
struct FlipPage: Codable, Identifiable {
    let id = UUID()
    let type: PageType
    let title: String?
    let caption: String?
    let text: String? // Full text content for text pages
    let imageBase64: String?
    let imageName: String?
    
    enum PageType: String, Codable, CaseIterable {
        case cover = "cover"
        case leftBars = "leftBars" // Legacy - use 'text' instead
        case text = "text" // Text content page
        case rightPhoto = "rightPhoto"
        case mixed = "mixed"
        case html = "html"
    }
    
    init(type: PageType, title: String? = nil, caption: String? = nil, text: String? = nil, imageBase64: String? = nil, imageName: String? = nil) {
        self.type = type
        self.title = title
        self.caption = caption
        self.text = text
        self.imageBase64 = imageBase64
        self.imageName = imageName
    }
}

// MARK: - Sample FlipPages with Rich Content
extension FlipPage {
    static let samplePages: [FlipPage] = [
        // Cover page
        FlipPage(type: .cover, title: "Life Stories", caption: "A Collection of Memories"),
        
        // Story 1: The Summer of Discovery
        FlipPage(type: .text, title: "The Summer of Discovery", text: """
        It was the summer of 1985 when everything changed. The air was thick with possibility, and the world seemed to stretch endlessly before me. I was sixteen, standing at the threshold between childhood and something else entirely.
        
        That morning, I woke before dawn, the birds just beginning their symphony. The old oak tree outside my window cast dancing shadows on my bedroom wall. I knew this day would be different. My grandfather had promised to teach me something that would "change the way I see the world."
        
        Down in the kitchen, the smell of fresh coffee mixed with bacon filled the air. Grandpa sat at the worn wooden table, his weathered hands wrapped around a steaming mug. He looked up at me with those piercing blue eyes that seemed to hold decades of wisdom.
        
        "Ready, kiddo?" he asked, a slight smile playing at the corners of his mouth. I nodded, though I had no idea what I was ready for.
        """),
        
        FlipPage(type: .rightPhoto, title: "Summer Memories", caption: "The old farmhouse where it all began, unchanged by time.", imageName: "farmhouse"),
        
        // Story 2: First Day at University
        FlipPage(type: .text, title: "New Beginnings", text: """
        September arrived with a nervous energy I'd never experienced before. The university campus sprawled before me like a small city, full of Gothic buildings and modern glass structures that somehow coexisted in perfect harmony.
        
        My dormitory room was small but filled with potential. Two beds, two desks, and a window overlooking the quad where students lounged on the grass, tossing frisbees and discussing philosophy. My roommate hadn't arrived yet, so I had these precious moments to myself.
        
        I unpacked slowly, placing each item carefully as if the arrangement would somehow determine my success over the next four years. The photo of my family went on the desk, my grandmother's quilt on the bed, and the lucky penny from my father in my pocket where it would stay throughout my studies.
        """),
        
        FlipPage(type: .rightPhoto, title: "Campus Life", caption: "The historic bell tower that would mark the hours of my education.", imageName: "university"),
        
        // Story 3: The Unexpected Journey
        FlipPage(type: .text, title: "The Road Less Traveled", text: """
        Sometimes life's most profound moments come when we least expect them. It was supposed to be a simple business trip to Seattle, nothing more than three days of meetings and hotel conference rooms. But when my flight was cancelled due to an unexpected storm, everything changed.
        
        Instead of waiting at the airport, I rented a car. "Drive," something inside me whispered. "Just drive." And so I did. The Pacific Northwest unfolded before me in layers of green and gray, mountains rising like ancient guardians from the mist.
        
        I stopped at a small diner somewhere outside Portland. The waitress, Martha, had kind eyes and a story to tell. Over pie and coffee, she shared how she'd left everything behind at forty to start over. "Sometimes," she said, "you have to lose yourself to find yourself."
        
        Those words echoed in my mind as I continued driving. By the time I reached Seattle, I had made a decision that would alter the course of my entire life. The meetings no longer seemed important. What mattered was the journey, not the destination.
        """),
        
        FlipPage(type: .mixed, title: "Wanderlust", caption: "The open road calls to those brave enough to answer.", imageName: "highway"),
        
        // Story 4: Family Traditions
        FlipPage(type: .text, title: "Sunday Dinners", text: """
        Every Sunday without fail, our family gathered around grandmother's dining table. The mahogany surface, polished to a mirror shine, reflected the faces of three generations sharing stories, laughter, and occasionally, tears.
        
        The ritual began at dawn with grandmother in her kitchen, flour dusting her apron, humming old hymns as she kneaded dough for her famous rolls. By noon, the house filled with aromas that could summon family members from miles away.
        
        These dinners were more than meals; they were the threads that wove our family tapestry. Uncle Robert would tell his war stories, each version slightly different than the last. Aunt Margaret would update everyone on the neighborhood gossip, her voice dropping to whispers for the juiciest parts.
        
        As children, we'd sneak tastes from the kitchen, dodging grandmother's wooden spoon but never her knowing smile. These moments, simple as they were, became the foundation of who we would become.
        """),
        
        FlipPage(type: .rightPhoto, title: "Family Gatherings", caption: "Three generations, one table, countless memories.", imageName: "family_dinner"),
        
        // Story 5: Career Milestone
        FlipPage(type: .text, title: "The Promotion", text: """
        Twenty years of dedication led to this moment. The corner office with its panoramic city view wasn't just a room; it was a symbol of every late night, every difficult decision, every sacrifice made along the way.
        
        I stood at the window, watching the city pulse with life below. Each light represented someone with their own dreams, their own struggles. It was humbling and inspiring in equal measure.
        
        My mentor, David, had told me years ago: "Success isn't measured by the height of your climb, but by the number of people you lift up along the way." Now, in this position, I finally understood what he meant.
        """),
        
        FlipPage(type: .rightPhoto, title: "Achievement", caption: "The view from the top is sweeter when shared.", imageName: "office_view"),
        
        // Story 6: Love Story
        FlipPage(type: .text, title: "When We Met", text: """
        It was raining in Paris, which seemed almost too cliché to be real. I had ducked into a small bookshop near the Seine, shaking water from my umbrella, when I saw her. She was reading Neruda in the poetry section, completely absorbed, oblivious to the world around her.
        
        I pretended to browse nearby, stealing glances, trying to find the courage to speak. When she finally looked up, our eyes met, and she smiled. That smile changed everything.
        
        "Terrible weather for tourists," she said in accented English. "Perfect weather for readers," I replied. We spent the next four hours in that bookshop, talking about literature, life, and the strange synchronicity that brings strangers together.
        
        Fifty years later, we still return to that bookshop every anniversary. The owner has changed, the books are different, but the magic remains. Some places hold memories so dear that time cannot touch them.
        """),
        
        FlipPage(type: .rightPhoto, title: "Paris in the Rain", caption: "Where every love story should begin.", imageName: "paris_bookshop"),
        
        // Story 7: Life Lessons
        FlipPage(type: .text, title: "What I've Learned", text: """
        After seven decades on this earth, I've collected wisdom like others collect stamps. Each lesson hard-won, each insight paid for with experience.
        
        I've learned that kindness costs nothing but means everything. That the hardest person to forgive is often yourself. That success without fulfillment is the ultimate failure. That time spent with loved ones is never wasted, and time is the only currency that truly matters.
        
        Most importantly, I've learned that life isn't about waiting for the storm to pass; it's about learning to dance in the rain. Every setback taught resilience, every loss taught appreciation, every ending taught that new beginnings are always possible.
        
        If I could tell my younger self one thing, it would be this: Don't be so afraid of making mistakes. Those mistakes will become your greatest teachers, your most interesting stories, and eventually, your wisdom to share.
        """),
        
        // Closing page
        FlipPage(type: .text, title: "The Story Continues", text: """
        This is not an ending, but a pause in the narrative. Life continues to unfold, each day writing new chapters, adding new characters, creating new adventures.
        
        Thank you for joining me on this journey through memory and time. May your own story be filled with wonder, love, and the courage to live authentically.
        
        Remember: we are all authors of our own lives. Make yours a story worth telling.
        """)
    ]
    
    // Convert MockBookPage to FlipPage
    static func fromMockBookPage(_ mockPage: MockBookPage) -> FlipPage {
        switch mockPage.type {
        case .cover:
            return FlipPage(type: .cover, title: mockPage.content)
        case .text:
            return FlipPage(type: .text, text: mockPage.content)
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