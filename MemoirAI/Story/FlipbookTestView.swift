import SwiftUI

// MARK: - Flipbook Test View
struct FlipbookTestView: View {
    @State private var currentPage = 0
    @State private var flipbookReady = false
    @State private var useFallback = false
    @State private var testMode: TestMode = .enhanced
    
    enum TestMode: String, CaseIterable {
        case enhanced = "Enhanced Sample"
        case generated = "Generated Content"
        case wordCount = "Word Count Test"
        case userFlow = "User Flow Test"
    }
    
    // Test with enhanced FlipPage content
    private let enhancedTestPages = [
        FlipPage(type: .cover, title: "Test Book"),
        
        // Chapter 1
        FlipPage(type: .chapterBreak, title: "Chapter 1", caption: "The Beginning", chapterNumber: 1),
        
        FlipPage(type: .textPage, 
                title: "Introduction", 
                textContent: "This is a test page with full text content. The text should be properly formatted with professional typography and should flow naturally across the page. This demonstrates the enhanced text handling capabilities of the new flipbook system. The content should be readable and well-spaced, with proper line breaks and paragraph structure.",
                chapterNumber: 1, pageNumber: 1, totalPages: 2),
        
        FlipPage(type: .textWithImage, 
                title: "With Image", 
                textContent: "This page combines text content with an image. The text should be positioned above the image with proper spacing, and the image should have breathing room around it. This layout demonstrates how the system handles mixed content effectively.",
                caption: "A test image with caption that can be longer than two lines and should display properly without being cut off.",
                imageName: "test_photo",
                chapterNumber: 1, pageNumber: 2, totalPages: 2),
        
        // Chapter 2
        FlipPage(type: .chapterBreak, title: "Chapter 2", caption: "The Middle", chapterNumber: 2),
        
        FlipPage(type: .imagePage, 
                title: "Dedicated Image", 
                caption: "This is a dedicated image page that gives the image plenty of space to breathe. The caption can be longer and more detailed, providing context for the image without being constrained by line limits.",
                imageName: "test_photo2",
                chapterNumber: 2, pageNumber: 1, totalPages: 1),
        
        FlipPage(type: .textPage, 
                title: "Conclusion", 
                textContent: "This final text page demonstrates the complete text handling capabilities. The content should be well-formatted with proper typography, line spacing, and justification. This shows how the system can handle longer text content while maintaining readability and professional appearance.",
                chapterNumber: 2, pageNumber: 2, totalPages: 2)
    ]
    
    // Test with generated content simulation
    private var generatedTestPages: [FlipPage] {
        let storyVM = StoryPageViewModel()
        
        // Create mock PageItems to test the conversion
        let mockPageItems: [StoryPageViewModel.PageItem] = [
            .illustration(image: UIImage(), caption: "Test memory with image"),
            .textPage(index: 1, total: 2, body: "This is a test memory with longer text content that should be properly paginated. The text should be split into appropriate chunks of around 175 words per page, ensuring that every word is visible and readable. This demonstrates the enhanced pagination system working with real content from the StoryPageViewModel."),
            .textPage(index: 2, total: 2, body: "This is the second page of the test memory, continuing the story from where the first page left off. The pagination should maintain the flow of the narrative while ensuring proper formatting and readability."),
            .qrCode(id: UUID(), url: URL(string: "memoirai://memory/test")!)
        ]
        
        return storyVM.generateFlipPages(from: mockPageItems)
    }
    
    // Test specifically for word count verification
    private var wordCountTestPages: [FlipPage] {
        let longText = """
        This is a comprehensive test of the word count pagination system. The goal is to ensure that each page contains between 150 and 200 words, which is the optimal range for professional book layout. This text will be automatically split into appropriate chunks by the pagination algorithm. The system should maintain natural sentence breaks and paragraph structure while ensuring that no content is lost or cut off. Every word should be visible and readable, with proper typography and formatting. The text should flow naturally from one page to the next, maintaining the narrative structure and readability. This test demonstrates the enhanced capabilities of the new flipbook system, which combines professional typography with smart content distribution. The pagination algorithm takes into account the available space, font size, and line spacing to create optimal page breaks. This ensures that the reading experience is smooth and professional, just like a real book. The system also handles different types of content, including text, images, and mixed layouts, while maintaining consistent formatting and readability throughout the book.
        """
        
        let chunks = longText.paginatedForBook(wordsPerPage: 175)
        
        var pages: [FlipPage] = [
            FlipPage(type: .cover, title: "Word Count Test"),
            FlipPage(type: .chapterBreak, title: "Chapter 1", caption: "Pagination Test", chapterNumber: 1)
        ]
        
        for (index, chunk) in chunks.enumerated() {
            let wordCount = chunk.split { $0.isWhitespace }.count
            pages.append(FlipPage(
                type: .textPage,
                title: "Page \(index + 1) (\(wordCount) words)",
                textContent: chunk,
                chapterNumber: 1,
                pageNumber: index + 1,
                totalPages: chunks.count
            ))
        }
        
        return pages
    }
    
    private var currentTestPages: [FlipPage] {
        switch testMode {
        case .enhanced:
            return enhancedTestPages
        case .generated:
            return generatedTestPages
        case .wordCount:
            return wordCountTestPages
        case .userFlow:
            // Simulate the complete user flow: sample → generated content
            let storyVM = StoryPageViewModel()
            
            // Create realistic mock PageItems that simulate user-generated content
            let mockPageItems: [StoryPageViewModel.PageItem] = [
                .illustration(image: UIImage(), caption: "My first day at school was filled with excitement and nervousness. I remember walking through those big doors, clutching my new backpack, and feeling like I was stepping into a whole new world. The classroom was bright and colorful, and my teacher had a warm smile that made me feel welcome immediately."),
                .textPage(index: 1, total: 3, body: "The morning started with my mother helping me get ready, carefully combing my hair and making sure my clothes were just right. She told me I looked handsome and that I was going to have a wonderful day. I remember the smell of her perfume as she hugged me goodbye, and the way she waved from the car as I walked toward the school building. The playground was already filled with children running and laughing, and I felt a mix of excitement and apprehension about joining them."),
                .textPage(index: 2, total: 3, body: "My teacher, Mrs. Johnson, greeted each of us at the door with a bright smile and a gentle handshake. She showed me where to hang my coat and backpack, and introduced me to the other children in our class. I remember feeling shy at first, but the other kids were friendly and welcoming. We spent the morning learning about the classroom rules and getting to know each other through games and activities."),
                .textPage(index: 3, total: 3, body: "By lunchtime, I had made my first friend, a boy named Tommy who sat next to me. We shared our sandwiches and talked about our favorite cartoons. The cafeteria was noisy and exciting, and I felt proud to be part of this new community. When my mother picked me up at the end of the day, I couldn't stop talking about everything I had learned and all the new friends I had made. That first day of school marked the beginning of my educational journey and taught me that new experiences, while sometimes scary, can lead to wonderful opportunities and friendships."),
                .qrCode(id: UUID(), url: URL(string: "memoirai://memory/school-memory")!)
            ]
            
            return storyVM.generateFlipPages(from: mockPageItems)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Enhanced Flipbook Test")
                .font(.title)
                .fontWeight(.bold)
            
            // Test mode selector
            Picker("Test Mode", selection: $testMode) {
                ForEach(TestMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            Text("Current Page: \(currentPage)")
                .font(.headline)
            
            Text("Status: \(flipbookReady ? "Ready" : "Loading...")")
                .font(.subheadline)
                .foregroundColor(flipbookReady ? .green : .orange)
            
            if useFallback {
                Text("Using Fallback (Native)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // Flipbook container
            ZStack {
                if useFallback {
                    // Fallback view
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 300, height: 400)
                        .overlay(
                            Text("Fallback View")
                                .foregroundColor(.gray)
                        )
                } else {
                    // Enhanced Flipbook view
                    FlipbookView(
                        pages: currentTestPages,
                        currentPage: $currentPage,
                        onReady: {
                            flipbookReady = true
                        },
                        onFlip: { pageIndex in
                            currentPage = pageIndex
                        }
                    )
                    .frame(width: 300, height: 400)
                    .onAppear {
                        // Set a timeout to fallback if flipbook doesn't load
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            if !flipbookReady {
                                useFallback = true
                            }
                        }
                    }
                }
            }
            
            // Navigation buttons
            HStack(spacing: 20) {
                Button("Previous") {
                    if currentPage > 0 {
                        currentPage -= 1
                    }
                }
                .disabled(currentPage == 0)
                
                Button("Next") {
                    if currentPage < currentTestPages.count - 1 {
                        currentPage += 1
                    }
                }
                .disabled(currentPage >= currentTestPages.count - 1)
            }
            
            Button("Reset") {
                currentPage = 0
            }
            
            // Page info
            VStack(spacing: 8) {
                Text("Page \(currentPage + 1) of \(currentTestPages.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if currentPage < currentTestPages.count {
                    let page = currentTestPages[currentPage]
                    Text("Type: \(page.type.rawValue)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let chapterNumber = page.chapterNumber {
                        Text("Chapter: \(chapterNumber)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let textContent = page.textContent {
                        let wordCount = textContent.split { $0.isWhitespace }.count
                        Text("Text: \(textContent.count) chars, \(wordCount) words")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Preview
struct FlipbookTestView_Previews: PreviewProvider {
    static var previews: some View {
        FlipbookTestView()
    }
} 