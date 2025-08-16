import SwiftUI

// MARK: - Flipbook Test View
struct FlipbookTestView: View {
    @State private var currentPage = 0
    @State private var flipbookReady = false
    @State private var useFallback = false
    @State private var showFullscreen = false
    
    // Use the rich sample pages with stories
    private let testPages = FlipPage.samplePages
    
    var body: some View {
        if showFullscreen {
            // Full viewport reading mode - no UI distractions
            ZStack {
                Color(white: 0.95)
                    .ignoresSafeArea()
                
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
                .ignoresSafeArea()
                
                // Minimal exit button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            showFullscreen = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                                .opacity(0.5)
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        } else {
            // Regular view with controls
            VStack(spacing: 20) {
                Text("Flipbook Preview")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Page \(currentPage + 1) of \(testPages.count)")
                    .font(.headline)
                
                // Flipbook container with "Enter Reading Mode" button
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
                        // Flipbook preview
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
                        .cornerRadius(10)
                        .shadow(radius: 10)
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
                
                // Enter Reading Mode button
                Button(action: {
                    showFullscreen = true
                }) {
                    Label("Enter Reading Mode", systemImage: "book.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
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
                
                Text("Create your own book")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top)
            }
            .padding()
        }
    }
}

// MARK: - Preview
struct FlipbookTestView_Previews: PreviewProvider {
    static var previews: some View {
        FlipbookTestView()
    }
}