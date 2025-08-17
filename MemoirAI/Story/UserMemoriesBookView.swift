import SwiftUI
import WebKit
import CoreData

struct UserMemoriesBookView: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var currentPage = 0
    @State private var selectedPhotos: [UIImage] = []
    @State private var showPhotoPicker = false
    @State private var flipbookReady = false
    @State private var useFallback = false
    @State private var flipbookError = false
    @State private var webView: WKWebView?
    @State private var showZoomedPage = false
    @State private var zoomedPageIndex: Int = -1
    @State private var flipbookPages: [FlipPage] = []
    
    @StateObject private var memoryViewModel = MemoryEntryViewModel()
    
    // Helper function to calculate book size outside ViewBuilder context
    private func calculateBookSize(for size: CGSize) -> CGSize {
        // Account for safe areas and UI elements
        let safeAreaTop: CGFloat = 120 // Header + padding
        let safeAreaBottom: CGFloat = 200 // Action buttons + padding
        let availableHeight = size.height - safeAreaTop - safeAreaBottom
        
        // Use more conservative sizing to prevent cut-off
        let maxW = size.width * 0.80  // Reduced from 0.85
        let targetAspect: CGFloat = 3.0 / 2.0
        let maxH = availableHeight * 0.85  // Reduced from 0.75
        
        var bookW = maxW
        var bookH = bookW / targetAspect
        if bookH > maxH {
            bookH = maxH
            bookW = bookH * targetAspect
        }
        
        // Ensure minimum size
        let minWidth: CGFloat = 280
        let minHeight: CGFloat = 374
        bookW = max(bookW, minWidth)
        bookH = max(bookH, minHeight)
        
        return CGSize(width: bookW, height: bookH)
    }
    
    var body: some View {
        ZStack {
            Tokens.bgWash.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                headerView
                
                ScrollView(.vertical, showsIndicators: false) {
                    // Add percentage-based spacing to move book down
                    Spacer()
                        .frame(height: geometry.size.height * 0.03) // 3% of screen height
                    
                    GeometryReader { geo in
                        let bookSize = calculateBookSize(for: geo.size)
                        
                        VStack(spacing: 0) {
                            // Flipbook preview with user's memories
                            if useFallback {
                                // Fallback to native implementation
                                ZStack {
                                    OpenBookView(
                                        pages: convertFlipPagesToMockPages(flipbookPages),
                                        currentPage: $currentPage,
                                        bookWidth: bookSize.width,
                                        bookHeight: bookSize.height
                                    )
                                }
                            } else {
                                // Flipbook implementation with external chevrons
                                ZStack {
                                    FlipbookViewWithWebView(
                                        pages: flipbookPages,
                                        currentPage: $currentPage,
                                        webView: $webView,
                                        onReady: {
                                            print("UserMemoriesBookView: Flipbook ready!")
                                            flipbookReady = true
                                        },
                                        onFlip: { pageIndex in
                                            print("UserMemoriesBookView: Page flipped to \(pageIndex)")
                                            if pageIndex == -1 {
                                                // Error occurred
                                                print("UserMemoriesBookView: Flipbook error detected, falling back to native")
                                                flipbookError = true
                                                useFallback = true
                                            } else {
                                                currentPage = pageIndex
                                            }
                                        },
                                        onPageTap: { index in
                                            zoomedPageIndex = index
                                            showZoomedPage = true
                                        }
                                    )
                                    .frame(width: bookSize.width, height: bookSize.height)
                                }
                                .onAppear {
                                    print("UserMemoriesBookView: Flipbook view appeared")
                                    print("UserMemoriesBookView: Geometry size: \(geo.size)")
                                    print("UserMemoriesBookView: Calculated book size: \(bookSize)")
                                    
                                    // Set a timeout to fallback if flipbook doesn't load
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        if !flipbookReady || flipbookError {
                                            print("UserMemoriesBookView: Flipbook timeout or error - falling back to native")
                                            useFallback = true
                                        }
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            actionButtonsView
                                .padding(.bottom, Tokens.bottomPadding)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 8)
                        .clipped()
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            currentPage = 0
            loadUserMemories()
        }
        .fullScreenCover(isPresented: $showZoomedPage) {
            PageZoomView(pageIndex: zoomedPageIndex, pages: $flipbookPages)
        }
    }
    
    // MARK: - Load User Memories
    private func loadUserMemories() {
        // Fetch memories for the current profile
        memoryViewModel.fetchEntries(for: profileVM.selectedProfile.id)
        
        // Convert memories to FlipPage format
        flipbookPages = convertMemoriesToFlipPages()
    }
    
    // MARK: - Convert Memories to FlipPages
    private func convertMemoriesToFlipPages() -> [FlipPage] {
        var pages: [FlipPage] = []
        
        // Add cover page with user's name
        pages.append(FlipPage(
            type: .cover,
            title: "\(profileVM.selectedProfile.name)'s Memories",
            caption: "A collection of precious moments",
            text: nil,
            imageBase64: nil,
            imageName: nil
        ))
        
        // Process each memory
        for memory in memoryViewModel.entries {
            // Add chapter title page if there's a prompt
            if let prompt = memory.prompt, !prompt.isEmpty {
                // Use prompt as chapter title
                let chapterTitle = prompt
                
                if let text = memory.text, !text.isEmpty {
                    // Split text into pages (150 words each)
                    let words = text.split(separator: " ").map(String.init)
                    let wordsPerPage = 150
                    
                    for i in stride(from: 0, to: words.count, by: wordsPerPage) {
                        let endIndex = min(i + wordsPerPage, words.count)
                        let pageWords = words[i..<endIndex].joined(separator: " ")
                        
                        // First page gets the title, subsequent pages are continuations
                        let isFirstPage = i == 0
                        
                        pages.append(FlipPage(
                            type: .text,
                            title: isFirstPage ? chapterTitle : nil,
                            caption: nil,
                            text: pageWords,
                            imageBase64: nil,
                            imageName: nil
                        ))
                    }
                } else {
                    // Memory has no text, just add title page
                    pages.append(FlipPage(
                        type: .text,
                        title: chapterTitle,
                        caption: nil,
                        text: "Memory recorded on \(formatDate(memory.createdAt ?? Date()))",
                        imageBase64: nil,
                        imageName: nil
                    ))
                }
            }
        }
        
        // Add ending page if we have memories
        if !memoryViewModel.entries.isEmpty {
            pages.append(FlipPage(
                type: .text,
                title: "The End",
                caption: nil,
                text: "Thank you for sharing your memories.\n\nEvery story told becomes a treasure for future generations.",
                imageBase64: nil,
                imageName: nil
            ))
        } else {
            // No memories yet - add placeholder pages
            pages.append(FlipPage(
                type: .text,
                title: "Your Story Awaits",
                caption: nil,
                text: "Start recording your memories to see them come to life in this beautiful book format.\n\nEach memory you share becomes a page in your personal memoir.",
                imageBase64: nil,
                imageName: nil
            ))
            
            pages.append(FlipPage(
                type: .text,
                title: "How to Begin",
                caption: nil,
                text: "1. Record a memory using the Record button\n2. Answer the guided prompts\n3. Your memories will automatically appear here\n4. Create your finished book when ready",
                imageBase64: nil,
                imageName: nil
            ))
        }
        
        return pages
    }
    
    // MARK: - Helper function to format date
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // MARK: - Convert FlipPages to MockBookPages for fallback
    private func convertFlipPagesToMockPages(_ flipPages: [FlipPage]) -> [MockBookPage] {
        return flipPages.map { page in
            switch page.type {
            case .cover:
                return MockBookPage(
                    type: .cover,
                    title: page.title ?? "Memories",
                    content: page.caption ?? "",
                    imageName: nil
                )
            case .text, .leftBars:
                return MockBookPage(
                    type: .textOnly,
                    title: page.title,
                    content: page.text ?? page.caption ?? "",
                    imageName: nil
                )
            case .rightPhoto:
                return MockBookPage(
                    type: .imageOnly,
                    title: page.title,
                    content: page.caption,
                    imageName: page.imageName
                )
            case .mixed:
                return MockBookPage(
                    type: .textWithImage,
                    title: page.title,
                    content: page.text ?? page.caption ?? "",
                    imageName: page.imageName
                )
            default:
                return MockBookPage(
                    type: .textOnly,
                    title: page.title,
                    content: page.text ?? page.caption ?? "",
                    imageName: nil
                )
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        GeometryReader { geo in
            HStack(alignment: .top) {
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Tokens.ink.opacity(0.7))
                        .padding(10)
                        .background(Tokens.bgWash)
                        .clipShape(Circle())
                }
                
                Spacer()
                
                VStack(spacing: 20) {
                    Text("Your Memory Book")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.ink)
                    
                    Text("Preview your recorded memories")
                        .font(Tokens.Typography.subtitle)
                        .foregroundColor(Tokens.ink.opacity(0.7))
                }
                .padding(.top, geo.size.height * 0.20) // Consistent with StorybookView
                
                Spacer()
                
                // Info button
                Button(action: showInfo) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Tokens.ink.opacity(0.7))
                        .padding(10)
                        .background(Tokens.bgWash)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, geo.safeAreaInsets.top > 0 ? geo.size.height * 0.06 : geo.size.height * 0.08)
            .padding(.bottom, 20)
        }
        .frame(height: 120)
    }
    
    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        VStack(spacing: Tokens.buttonSpacing) {
            // Primary: Record more memories
            NavigationLink(destination: RecordMemoryView().environmentObject(profileVM)) {
                Text("Record a memory")
                    .font(Tokens.Typography.button)
                    .foregroundColor(Tokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.clear))
                    .animatedGradientOutline(lineWidth: Tokens.gradientStrokeWidth)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record a memory")
            
            // Secondary: Create finished book
            NavigationLink(destination: StoryPage().environmentObject(profileVM)) {
                Text("Create finished book")
                    .font(Tokens.Typography.button)
                    .fontWeight(.medium)
                    .foregroundColor(Tokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(Tokens.bgPrimary)
                            .overlay(
                                Capsule()
                                    .stroke(Tokens.ink.opacity(0.1), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create finished book from memories")
        }
        .padding(.horizontal, 20)
    }
    
    private func showInfo() {
        // Show information about the memory book feature
        print("Info: This preview shows your recorded memories in book format")
    }
    
    private var geometry: CGSize {
        UIScreen.main.bounds.size
    }
}

// MARK: - Tokens (reuse from StorybookView)
private struct Tokens {
    static let bgWash = Color(red: 0.98, green: 0.96, blue: 0.94)
    static let bgPrimary = Color(red: 0.96, green: 0.93, blue: 0.88)
    static let ink = Color(red: 0.2, green: 0.2, blue: 0.2)
    static let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    
    static let buttonSpacing: CGFloat = 12
    static let bottomPadding: CGFloat = 24
    static let gradientStrokeWidth: CGFloat = 2
    
    struct Typography {
        static let title = Font.system(size: 24, weight: .bold, design: .serif)
        static let subtitle = Font.system(size: 16, weight: .medium, design: .serif)
        static let button = Font.system(size: 16, weight: .semibold, design: .rounded)
    }
}