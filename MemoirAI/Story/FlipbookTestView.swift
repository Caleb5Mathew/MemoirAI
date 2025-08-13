import SwiftUI

// MARK: - Flipbook Test View
struct FlipbookTestView: View {
    @State private var currentPage = 0
    @State private var flipbookReady = false
    @State private var useFallback = false
    
    private let testPages = [
        FlipPage(type: .cover, title: "Test Book"),
        FlipPage(type: .leftBars, caption: "This is a test page with paragraph bars"),
        FlipPage(type: .rightPhoto, title: "Test Photo", caption: "This is a test photo page", imageName: "test_photo"),
        FlipPage(type: .mixed, caption: "This is a mixed page with bars and photo", imageName: "test_photo2")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Flipbook Test")
                .font(.title)
                .fontWeight(.bold)
            
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
                    // Flipbook view
                    FlipbookView(
                        pages: testPages,
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
                    if currentPage < testPages.count - 1 {
                        currentPage += 1
                    }
                }
                .disabled(currentPage >= testPages.count - 1)
            }
            
            Button("Reset") {
                currentPage = 0
                flipbookReady = false
                useFallback = false
            }
            .padding(.top)
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