import SwiftUI
import WebKit

// MARK: - Zoom Page Identifier
struct ZoomPageIdentifier: Identifiable {
    let id = UUID()
    let pageIndex: Int
}

// MARK: - Preference Key for Page Dimensions
struct ZoomPageSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct FlipbookPageSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Main Storybook View
struct StorybookView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var profileVM: ProfileViewModel
    
    // Flag to distinguish between memory preview and create mode
    let isMemoryPreview: Bool

    @State private var currentPage = 0
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [UIImage] = []
    @State private var flipbookReady = false
    @State private var useFallback = false
    @State private var flipbookError = false
    @State private var webView: WKWebView?
    @State private var zoomPageIdentifier: ZoomPageIdentifier? = nil
    @State private var flipbookPages = FlipPage.samplePages
    @State private var showDownloadOptions = false
    @State private var fallbackTimer: Timer?
    @State private var flipbookPageSize: CGSize = .zero
    @State private var showDebugConsole = false
    
    // Read art style from AppStorage to match user's preference for downloads
    @AppStorage("memoirArtStyle") private var artStyleRaw = ArtStyle.kidsBook.rawValue
    
    private var isKidsBook: Bool {
        // For sample content, check user's art style preference
        return ArtStyle(rawValue: artStyleRaw) == .kidsBook
    }

    private var flipbookBasePageWidth: CGFloat {
        isKidsBook ? 428.8 : 321.6
    }

    private var flipbookBasePageHeight: CGFloat {
        isKidsBook ? 321.6 : 428.8
    }
    
    @StateObject private var downloadManager = BookDownloadManager()

    // Sample pages for the finished book preview
    private let samplePages = MockBookPage.samplePages
    
    // Default initializer
    init(isMemoryPreview: Bool = false) {
        self.isMemoryPreview = isMemoryPreview
    }
    
    // Helper function to calculate book size outside ViewBuilder context
    private func calculateBookSize(for size: CGSize) -> CGSize {
        // Account for safe areas and UI elements
        let safeAreaTop: CGFloat = 120 // Header + padding
        let safeAreaBottom: CGFloat = 200 // Action buttons + padding
        let availableHeight = size.height - safeAreaTop - safeAreaBottom
        
        // Use more conservative sizing to prevent cut-off
        let maxW = size.width * 0.80  // Reduced from 0.85
        // Kids Book = landscape (wider than tall), Others = portrait (taller than wide)
        let targetAspect: CGFloat = isKidsBook ? (11.0 / 8.5) : (8.5 / 11.0)
        let maxH = availableHeight * 0.85  // Reduced from 0.75

        var bookW = maxW
        var bookH = bookW / targetAspect
        if bookH > maxH {
            bookH = maxH
            bookW = bookH * targetAspect
        }
        
        // Ensure minimum size - conditional based on orientation
        let minWidth: CGFloat = isKidsBook ? 374 : 280
        let minHeight: CGFloat = isKidsBook ? 280 : 374
        bookW = max(bookW, minWidth)
        bookH = max(bookH, minHeight)
        
        return CGSize(width: bookW, height: bookH)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Warm parchment gradient background
                LinearGradient(
                    colors: [Tokens.bgPrimary, Tokens.bgWash],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView

                    // Add percentage-based spacing to move book down
                    Spacer()
                        .frame(height: geometry.size.height * 0.03) // 3% of screen height

                    GeometryReader { geo in
                        let bookSize = calculateBookSize(for: geo.size)
                        
                        VStack(spacing: 0) {
                            // Add "Click Page to Zoom" hint text
                            Text("Click Page to Zoom")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Tokens.ink.opacity(0.6))
                                .padding(.bottom, 12)
                            
                            // Flipbook preview with fallback to native OpenBookView
                            if useFallback {
                                // Fallback to native implementation
                                ZStack {
                                    OpenBookView(
                                        pages: samplePages,
                                        currentPage: $currentPage,
                                        bookWidth: bookSize.width,
                                        bookHeight: bookSize.height
                                    )
                                    
                                    // Debug overlay for fallback
                                    VStack {
                                        HStack {
                                            Text("Native Fallback")
                                                .font(.caption)
                                                .padding(4)
                                                .background(Color.red.opacity(0.8))
                                                .foregroundColor(.white)
                                                .cornerRadius(4)
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                    .padding(8)
                                }
                            } else {
                                // Flipbook implementation with external chevrons
                                ZStack {
                                    FlipbookViewWithWebView(
                                        pages: flipbookPages,
                                        currentPage: $currentPage,
                                        webView: $webView,
                                        isKidsBook: isKidsBook,
                                        onReady: {
                                            print("StorybookView: Flipbook ready!")
                                            // Cancel the fallback timer since flipbook is ready
                                            fallbackTimer?.invalidate()
                                            fallbackTimer = nil
                                            flipbookReady = true
                                        },
                                        onFlip: { pageIndex in
                                            print("StorybookView: Page flipped to \(pageIndex)")
                                            if pageIndex == -1 {
                                                // Error occurred
                                                print("StorybookView: Flipbook error detected, falling back to native")
                                                // Cancel timer if error occurs
                                                fallbackTimer?.invalidate()
                                                fallbackTimer = nil
                                                flipbookError = true
                                                useFallback = true
                                            } else {
                                                currentPage = pageIndex
                                            }
                                        },
                                        onPageTap: { index in
                                            print("📖 Swift StorybookView: onPageTap received index \(index), opening zoom view")
                                            print("📖 Swift StorybookView: flipbookPages count is \(flipbookPages.count)")
                                            zoomPageIdentifier = ZoomPageIdentifier(pageIndex: index)
                                        },
                                        onPhotoFrameTap: nil,  // Photo frames not used in AI-generated storybooks
                                        onPhotoFrameMoved: nil  // Photo frame dragging not used in preview storybooks
                                    )
                                    .frame(width: bookSize.width, height: bookSize.height)
                                    .background(
                                        GeometryReader { pageGeo in
                                            Color.clear.preference(key: FlipbookPageSizePreferenceKey.self, value: pageGeo.size)
                                        }
                                    )
                                    .onPreferenceChange(FlipbookPageSizePreferenceKey.self) { size in
                                        flipbookPageSize = size
                                        print("🔍 FLIPBOOK PAGE DIMENSIONS:")
                                        print("   Width: \(size.width)")
                                        print("   Height: \(size.height)")
                                    }
                                    
                                    // Debug overlay removed to prevent layout interference
                                }
                                .onAppear {
                                    print("StorybookView: Flipbook view appeared")
                                    print("StorybookView: Geometry size: \(geo.size)")
                                    print("StorybookView: Calculated book size: \(bookSize)")
                                    
                                    // DEBUG: Check if FlipbookView is getting proper space
                                    print("StorybookView: FlipbookView frame should be: \(bookSize)")
                                    
                                    // Set a timeout to fallback if flipbook doesn't load
                                    // Use Timer instead of DispatchQueue for better control
                                    fallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                                        if !flipbookReady && !flipbookError {
                                            print("StorybookView: Flipbook timeout - falling back to native")
                                            useFallback = true
                                        }
                                    }
                                }
                            }

                            Spacer()

                            // Removed "Swipe to flip pages" text overlay

                            actionButtonsView
                                .padding(.bottom, Tokens.bottomPadding)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 8)  // Reduced from 16 to give more space
                        .clipped() // Ensure content doesn't overflow
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerSheet(
                isPresented: $showPhotoPicker,
                onPhotosSelected: { photos in
                    selectedPhotos = photos
                }
            )
        }
        .onAppear { currentPage = 0 }
        .onDisappear {
            // Clean up timer when view disappears
            fallbackTimer?.invalidate()
            fallbackTimer = nil
        }
        .fullScreenCover(item: $zoomPageIdentifier) { identifier in
            PageZoomView(
                pageIndex: identifier.pageIndex,
                pages: $flipbookPages,
                flipbookPageWidth: flipbookPageSize.width,
                flipbookPageHeight: flipbookPageSize.height,
                onDismiss: { finalPageIndex in
                    // Don't update anything - let the flipbook maintain its own state
                    // The flipbook already knows what page it's on (the one that was clicked)
                    // Updating currentPage here causes state confusion and double-flips
                    print("✅ Zoom dismissed from page \(finalPageIndex), flipbook state unchanged (no Swift state update)")
                }
            )
        }
        .sheet(isPresented: $showDebugConsole) {
            NavigationView {
                DownloadDebugView(webView: webView)
                    .navigationTitle("Download Debug")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showDebugConsole = false
                            }
                        }
                    }
            }
        }
        .overlay(
            Group {
                if showDownloadOptions {
                    DownloadOptionsView(
                        isPresented: $showDownloadOptions,
                        onSaveToPhotos: {
                            handleSaveToPhotos()
                        },
                        onSaveToFiles: {
                            handleSaveToFiles()
                        }
                    )
                }
            }
        )
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

                VStack(spacing: 20) { // Increased from headerSpacing (12) to 20
                    Text("Create your book")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.ink)

                    Text("Flip through a finished book")
                        .font(Tokens.Typography.subtitle)
                        .foregroundColor(Tokens.ink.opacity(0.7))
                }
                .padding(.top, geo.size.height * 0.20) // Moved down more (20% from top)

                Spacer()

                // Download button aligned with back button
                Button(action: downloadBook) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Tokens.ink.opacity(0.7))
                        .padding(10)
                        .background(Tokens.bgWash)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Tokens.ink.opacity(0.1), lineWidth: 1)
                        )
                }
                .onLongPressGesture(minimumDuration: 2.0) {
                    // Long press to open debug console
                    showDebugConsole = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, geo.safeAreaInsets.top > 0 ? geo.size.height * 0.06 : geo.size.height * 0.08) // 6-8% from top
            .padding(.bottom, 20)
        }
        .frame(height: 120) // Fixed height for header
    }

    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        VStack(spacing: Tokens.buttonSpacing) {
            // Primary: gradient-outline pill (navigates to user memories book view)
            NavigationLink(destination: UserMemoriesBookView().environmentObject(profileVM)) {
                Text("Create your own book")
                    .font(Tokens.Typography.button)
                    .foregroundColor(Tokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule().fill(Color.clear)
                    )
                    .animatedGradientOutline(lineWidth: Tokens.gradientStrokeWidth)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create your own book")

            // Secondary: soft cream filled pill (opens photo picker)
            // Only show in create mode, not in memory preview
            if !isMemoryPreview {
                Button(action: { showPhotoPicker = true }) {
                    Text("Add photos")
                        .font(Tokens.Typography.button)
                        .fontWeight(.medium)
                        .foregroundColor(Tokens.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Tokens.bgPrimary)
                                .shadow(color: Tokens.shadow.opacity(Tokens.softShadow.opacity),
                                        radius: Tokens.softShadow.radius,
                                        x: 0,
                                        y: Tokens.softShadow.y)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add photos")
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Helper Functions
    private func hapticFeedback() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func arrowButton(system: String,
                             disabled: Bool,
                             accessibility: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Tokens.paper.opacity(0.85))
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: Tokens.shadow.opacity(0.4), radius: 2, x: 0, y: 1)

                Image(systemName: system)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Tokens.ink.opacity(disabled ? 0.35 : 0.7))
            }
            .frame(width: Tokens.chevronSize, height: Tokens.chevronSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
        .accessibilityLabel(accessibility)
    }
    
    private func downloadBook() {
        // Show download options popup
        showDownloadOptions = true
    }
    
    private func handleSaveToPhotos() {
        // Get the current view controller
        var presentingViewController: UIViewController?
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            presentingViewController = rootVC
        }
        
        // Set the book type before saving
        downloadManager.setBookType(isKidsBook: isKidsBook)
        downloadManager.saveToPhotos(webView: webView, from: presentingViewController)
    }
    
    private func handleSaveToFiles() {
        // Get the current view controller
        var presentingViewController: UIViewController?
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            presentingViewController = rootVC
        }
        
        // Set the book type before saving
        downloadManager.setBookType(isKidsBook: isKidsBook)
        downloadManager.saveToFiles(webView: webView, from: presentingViewController)
    }
}

// MARK: - Helper to expand pages (split long text like JavaScript does)
func expandFlipPages(_ pages: [FlipPage]) -> ([FlipPage], [Int]) {
    var expandedPages: [FlipPage] = []
    var originalIndexMap: [Int] = [] // Maps expanded index to original index
    
    print("📖 Swift expandFlipPages: Starting with \(pages.count) original pages")
    
    for (originalIndex, page) in pages.enumerated() {
        // CRITICAL: Only split .text and .leftBars types (matching JavaScript line 685)
        // JavaScript: if (page.type === 'text' || page.type === 'leftBars')
        if page.type == .text || page.type == .leftBars {
            // Use text OR caption (matching JavaScript: page.text || page.caption || '')
            let fullText = page.text ?? page.caption ?? ""
            
            // Split on whitespace (spaces, newlines, tabs) to match JavaScript's /\s+/
            let words = fullText.split(whereSeparator: { $0.isWhitespace })
            let wordCount = words.count
            
            print("📖 Swift Page \(originalIndex) (\(page.title ?? "No title"), type: \(page.type.rawValue)): \(wordCount) words")
            
            if wordCount > 150 {
                // Split into multiple pages (150 words each) - matching JavaScript
                let wordsPerPage = 150
                var splitCount = 0
                for startIdx in stride(from: 0, to: wordCount, by: wordsPerPage) {
                    let endIdx = min(startIdx + wordsPerPage, wordCount)
                    let pageWords = words[startIdx..<endIdx]
                    let pageText = pageWords.joined(separator: " ")
                    
                    var splitPage = page
                    // Store split text in both text and caption (matching JavaScript line 698)
                    splitPage.text = pageText
                    splitPage.caption = pageText
                    expandedPages.append(splitPage)
                    originalIndexMap.append(originalIndex)
                    splitCount += 1
                    print("   → Swift: Split part \(splitCount): words \(startIdx)-\(endIdx)")
                }
                print("   → Swift: Total split into \(splitCount) pages")
            } else {
                expandedPages.append(page)
                originalIndexMap.append(originalIndex)
                print("   → Swift: No split needed (<= 150 words)")
            }
        } else {
            // All other page types: keep as-is (matching JavaScript line 714-718)
            expandedPages.append(page)
            originalIndexMap.append(originalIndex)
            print("📖 Swift Page \(originalIndex) (\(page.type.rawValue)): Not text/leftBars, no split")
        }
    }
    
    print("📖 Swift expandFlipPages: Created \(expandedPages.count) expanded pages from \(pages.count) original pages")
    print("📖 Swift Mapping: \(originalIndexMap)")
    
    return (expandedPages, originalIndexMap)
}

// MARK: - Zoomed Page View
struct PageZoomView: View {
    let pageIndex: Int
    @Binding var pages: [FlipPage]
    let flipbookPageWidth: CGFloat
    let flipbookPageHeight: CGFloat
    let onDismiss: ((Int) -> Void)?
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.sizeCategory) var sizeCategory
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedText: String = ""
    @State private var editedCaption: String = ""
    @State private var showDeleteConfirmation = false
    @State private var currentViewedIndex: Int = 0
    @State private var expandedPages: [FlipPage] = []
    @State private var originalIndexMap: [Int] = []
    @State private var zoomPageSize: CGSize = .zero
    @State private var currentScaleFactor: CGFloat = 1.0
    
    // Character limit states
    @State private var titleExceeded = false
    @State private var textExceeded = false
    @State private var captionExceeded = false
    
    // Photo layout editing states
    @State private var selectedLayoutId: UUID? = nil
    @State private var showPhotoSourcePicker = false
    @State private var photoToAddToLayout: UUID? = nil
    @State private var showDeleteLayoutConfirmation = false
    @State private var layoutToDelete: UUID? = nil
    
    // Dynamic character limits based on page content
    var dynamicLimits: PageLimits {
        guard let page = currentPage else {
            return PageLimits(titleCharLimit: 30, captionCharLimit: 50, textWordLimit: 150, availableTextHeight: 300)
        }
        // Estimate page size based on screen dimensions
        let screenSize = UIScreen.main.bounds.size
        let pageSize = CGSize(width: screenSize.width * 0.8, height: screenSize.height * 0.6)
        return PageLimits.calculate(for: page, pageSize: pageSize)
    }
    
    var titleCharLimit: Int { dynamicLimits.titleCharLimit }
    var captionCharLimit: Int { dynamicLimits.captionCharLimit }
    var textWordLimit: Int { dynamicLimits.textWordLimit }
    
    var currentPage: FlipPage? {
        guard currentViewedIndex >= 0 && currentViewedIndex < expandedPages.count else { return nil }
        return expandedPages[currentViewedIndex]
    }
    
    // Check if this is a continued page - should only show drop cap on the FIRST page of a chapter
    var isContinuedPage: Bool {
        guard let currentTitle = currentPage?.title else { return false }
        
        // Find the first page with this title in the entire book
        if let firstPageIndex = expandedPages.firstIndex(where: { $0.title == currentTitle }) {
            // This is a continued page if it's NOT the first page with this title
            return currentViewedIndex != firstPageIndex
        }
        
        // If title not found (shouldn't happen), assume it's not continued
        return false
    }
    
    // Get the displayed text for this page (already split, so just return it)
    var displayedText: String {
        let text = currentPage?.text ?? ""
        print("📖 Swift PageZoomView.displayedText: Returning \(text.count) characters, first 100 chars: \(String(text.prefix(100)))")
        return text
    }
    
    // MARK: - Background View
    var backgroundView: some View {
        LinearGradient(
            colors: [Tokens.bgPrimary.opacity(0.98), Tokens.bgWash.opacity(0.98)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(
            Color.black.opacity(0.3)
                .ignoresSafeArea()
        )
    }
    
    // MARK: - Page Content View
    @ViewBuilder
    func pageContentView(at index: Int) -> some View {
        VStack(spacing: 0) {
            navigationHeaderView(at: index)
            pageDisplayView(at: index)
        }
        .tag(index)
    }
    
    // MARK: - Navigation Header View
    @ViewBuilder
    func navigationHeaderView(at index: Int) -> some View {
        HStack {
            Button(action: {
                // Notify parent of the final page index before dismissing
                onDismiss?(currentViewedIndex)
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Tokens.ink.opacity(0.8))
                    .background(Circle().fill(Color.white.opacity(0.9)))
            }
            .padding()
            
            Spacer()
            
            // Only show edit/delete buttons if we're viewing the current index
            if index == currentViewedIndex {
                if !isEditing {
                    editingButtonsView
                } else {
                    doneButtonsView
                }
            }
        }
    }
    
    // MARK: - Editing Buttons View
    var editingButtonsView: some View {
        HStack(spacing: 12) {
            // Delete button on the left
            Button(action: { showDeleteConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Delete")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.red.opacity(0.9)))
            }
            
            // Edit button on the right
            Button(action: { isEditing = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                    Text("Edit")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Tokens.accent))
            }
        }
        .padding()
    }
    
    // MARK: - Done Buttons View
    var doneButtonsView: some View {
        HStack(spacing: 12) {
            Button(action: { 
                isEditing = false
                // Reset to original values
                if let page = currentPage {
                    editedTitle = page.title ?? ""
                    editedText = page.text ?? ""
                    editedCaption = page.caption ?? ""
                }
            }) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Tokens.ink.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
            }
            
            Button(action: { 
                // Save changes back to the page model
                // Use originalIndexMap to get the correct index in the original pages array
                if currentViewedIndex >= 0 && currentViewedIndex < originalIndexMap.count {
                    let originalIndex = originalIndexMap[currentViewedIndex]
                    
                    if originalIndex >= 0 && originalIndex < pages.count {
                        // Check if this page was split (multiple expanded pages share same original index)
                        let relatedExpandedIndices = originalIndexMap.enumerated()
                            .filter { $0.element == originalIndex }
                            .map { $0.offset }
                        
                        if relatedExpandedIndices.count > 1 {
                            // This page was split - we need to handle it carefully
                            // Update the expanded page directly
                            if currentViewedIndex < expandedPages.count {
                                expandedPages[currentViewedIndex].title = editedTitle.isEmpty ? nil : editedTitle
                                expandedPages[currentViewedIndex].text = editedText.isEmpty ? nil : editedText
                                expandedPages[currentViewedIndex].caption = editedCaption.isEmpty ? nil : editedCaption
                            }
                            
                            // Combine all split page texts back into the original
                            let combinedText = relatedExpandedIndices
                                .compactMap { index in
                                    if index == currentViewedIndex {
                                        return editedText
                                    } else if index < expandedPages.count {
                                        return expandedPages[index].text
                                    }
                                    return nil
                                }
                                .joined(separator: " ")
                            
                            pages[originalIndex].text = combinedText.isEmpty ? nil : combinedText
                            pages[originalIndex].title = editedTitle.isEmpty ? nil : editedTitle
                            pages[originalIndex].caption = editedCaption.isEmpty ? nil : editedCaption
                            
                            print("✅ Saved edits to split page - original page \(originalIndex) (combined \(relatedExpandedIndices.count) parts)")
                        } else {
                            // This page wasn't split - update directly
                            pages[originalIndex].title = editedTitle.isEmpty ? nil : editedTitle
                            pages[originalIndex].text = editedText.isEmpty ? nil : editedText
                            pages[originalIndex].caption = editedCaption.isEmpty ? nil : editedCaption
                            
                            print("✅ Saved edits to original page \(originalIndex)")
                        }
                        
                        // Re-expand pages to reflect changes
                        let (expanded, mapping) = expandFlipPages(pages)
                        expandedPages = expanded
                        originalIndexMap = mapping
                        
                        print("   Title: \(editedTitle)")
                        print("   Text: \(editedText.prefix(50))...")
                    }
                }
                isEditing = false
            }) {
                Text("Done")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.blue))
            }
        }
        .padding()
    }
    
    // MARK: - Page Display View
    @ViewBuilder
    func pageDisplayView(at index: Int) -> some View {
        // CRITICAL: Use expandedPages, not pages!
        let page = index >= 0 && index < expandedPages.count ? expandedPages[index] : nil
        let _ = print("📖 Swift PageZoomView.pageDisplayView: Showing page at index \(index), page exists: \(page != nil), title: \(page?.title ?? "nil"), type: \(page?.type.rawValue ?? "nil")")
        
        GeometryReader { geo in
            // CALCULATE SMART SCALE: Proportional + Accessibility
            let screenWidth = geo.size.width
            let zoomPageWidth = min(screenWidth * 0.85, 500)
            
            // 1. PROPORTIONAL COMPONENT: Based on actual dimensions
            let flipbookBaseWidth: CGFloat = max(flipbookPageWidth, 280) // Fallback to typical size
            let proportionalScale = zoomPageWidth / flipbookBaseWidth
            
            // 2. DYNAMIC TYPE COMPONENT: Respect iOS accessibility
            let dynamicTypeScale: CGFloat = {
                switch sizeCategory {
                case .extraSmall: return 0.9
                case .small: return 0.95
                case .medium: return 1.0
                case .large: return 1.05
                case .extraLarge: return 1.15
                case .extraExtraLarge: return 1.25
                case .extraExtraExtraLarge: return 1.4
                case .accessibilityMedium: return 1.6
                case .accessibilityLarge: return 1.8
                case .accessibilityExtraLarge: return 2.0
                case .accessibilityExtraExtraLarge: return 2.2
                case .accessibilityExtraExtraExtraLarge: return 2.5
                @unknown default: return 1.0
                }
            }()
            
            // 3. TARGET ZOOM FACTOR: How much bigger should zoom be than flipbook?
            let targetZoomFactor: CGFloat = 1.5 // Tune this one number!
            
            // 4. FINAL SCALE: Combine all factors
            let baseScale = proportionalScale * dynamicTypeScale * targetZoomFactor
            
            let finalFontSize = 6 * baseScale
            let _ = print("🔍 SMART SCALE:")
            let _ = print("   Screen: \(screenWidth)pt")
            let _ = print("   Zoom page: \(zoomPageWidth)pt")
            let _ = print("   Flipbook: \(flipbookBaseWidth)pt")
            let _ = print("   Proportional: \(proportionalScale)x")
            let _ = print("   Dynamic Type: \(dynamicTypeScale)x (\(sizeCategory))")
            let _ = print("   Target zoom: \(targetZoomFactor)x")
            let _ = print("   ✅ FINAL SCALE: \(baseScale)x → font: \(finalFontSize)pt")
            
            ScrollView {
                if let page = page {
                    // Book page appearance - match flipbook styling
                    VStack {
                        ZStack {
                            // Enhanced book page background with gradient and shadow
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 250/255, green: 248/255, blue: 243/255),
                                            Color(red: 249/255, green: 246/255, blue: 240/255),
                                            Color(red: 250/255, green: 248/255, blue: 243/255)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(red: 200/255, green: 190/255, blue: 180/255).opacity(0.2), lineWidth: 1)
                                )
                            
                            // Page content - SCALED to match zoom size
                            VStack(alignment: .leading, spacing: 0) {
                                if isEditing {
                                    // Edit mode
                                    editablePageContent(page: page)
                                } else {
                                    // Display mode - Use calculated scale
                                    displayPageContent(page: page, scaleFactor: baseScale)
                                }
                            }
                            // MATCH CSS: .page-content padding (SCALED)
                            .padding(EdgeInsets(
                                top: 25 * baseScale,
                                leading: 20 * baseScale,
                                bottom: 35 * baseScale,
                                trailing: 20 * baseScale
                            ))
                        }
                        .frame(width: zoomPageWidth)
                        .frame(minHeight: geo.size.height * 0.7)
                        .padding(.vertical, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    var body: some View {
        ZStack {
            backgroundView
            
            // TabView for swipe navigation (animation disabled for clean transitions)
            TabView(selection: $currentViewedIndex) {
                ForEach(expandedPages.indices, id: \.self) { index in
                    pageContentView(at: index)
                        .onAppear {
                            print("📖 Swift PageZoomView: Tab page \(index) appeared (title: \(expandedPages[index].title ?? "nil"))")
                        }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(nil, value: currentViewedIndex) // Disable page transition animation
            .onAppear {
                print("📖 Swift PageZoomView.onAppear: Received pageIndex=\(pageIndex), pages.count=\(pages.count)")
                
                // Expand pages on appear
                let (expanded, mapping) = expandFlipPages(pages)
                expandedPages = expanded
                originalIndexMap = mapping
                
                print("📖 Swift PageZoomView: After expansion, expandedPages.count=\(expandedPages.count)")
                
                // pageIndex now directly corresponds to the expanded page index from JavaScript
                currentViewedIndex = min(pageIndex, expandedPages.count - 1)
                
                print("📖 Swift PageZoomView: Set currentViewedIndex to \(currentViewedIndex)")
                print("📖 Swift PageZoomView: Current page title: \(currentPage?.title ?? "nil")")
                print("📖 Swift PageZoomView: Current page type: \(currentPage?.type.rawValue ?? "nil")")
                print("📖 Swift PageZoomView: Navigation - can go left: \(currentViewedIndex > 0), can go right: \(currentViewedIndex < expandedPages.count - 1)")
                
                // Initialize edited fields
                if let page = currentPage {
                    editedTitle = page.title ?? ""
                    editedText = displayedText
                    editedCaption = page.caption ?? ""
                }
            }
            .onChange(of: currentViewedIndex) { newIndex in
                print("📖 Swift PageZoomView: currentViewedIndex changed to \(newIndex)")
                print("📖 Swift PageZoomView: New page title: \(currentPage?.title ?? "nil")")
                print("📖 Swift PageZoomView: Navigation arrows - left: \(newIndex > 0), right: \(newIndex < expandedPages.count - 1)")
                
                // Update edited fields when page changes
                if let page = currentPage {
                    editedTitle = page.title ?? ""
                    editedText = displayedText
                    editedCaption = page.caption ?? ""
                }
            }
            
            // Navigation arrows overlay
            HStack {
                // Left arrow (previous page)
                if currentViewedIndex > 0 {
                    Button(action: {
                        print("📖 Swift PageZoomView: Left arrow clicked, going from \(currentViewedIndex) to \(currentViewedIndex - 1)")
                        withAnimation {
                            currentViewedIndex -= 1
                        }
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(.leading, 20)
                } else {
                    Spacer()
                        .frame(width: 44)
                        .padding(.leading, 20)
                }
                
                Spacer()
                
                // Right arrow (next page)
                if currentViewedIndex < expandedPages.count - 1 {
                    Button(action: {
                        print("📖 Swift PageZoomView: Right arrow clicked, going from \(currentViewedIndex) to \(currentViewedIndex + 1)")
                        withAnimation {
                            currentViewedIndex += 1
                        }
                    }) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, 20)
                } else {
                    Spacer()
                        .frame(width: 44)
                        .padding(.trailing, 20)
                }
            }
            .padding(.top, 100) // Position below the close/edit buttons
        }
        .alert("Delete Page", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePage()
            }
        } message: {
            Text("Are you sure you want to delete this page? This action cannot be undone.")
        }
        .alert("Delete Photo Layout", isPresented: $showDeleteLayoutConfirmation) {
            Button("Delete", role: .destructive) {
                if let layoutId = layoutToDelete, let page = currentPage {
                    deleteLayout(layoutId, from: page)
                }
            }
            Button("Cancel", role: .cancel) {
                layoutToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this photo layout?")
        }
        .sheet(isPresented: $showPhotoSourcePicker) {
            if let layoutId = photoToAddToLayout, let page = currentPage {
                PhotoSourcePicker(isPresented: $showPhotoSourcePicker) { image in
                    addPhotoToLayout(layoutId, image: image, in: page)
                }
            }
        }
    }
    
    // MARK: - Delete Page Function
    func deletePage() {
        guard currentViewedIndex >= 0 && currentViewedIndex < expandedPages.count else { return }
        
        // Get the original page index that this expanded page corresponds to
        let originalIndex = originalIndexMap[currentViewedIndex]
        
        // Remove from original pages array
        if originalIndex >= 0 && originalIndex < pages.count {
            pages.remove(at: originalIndex)
        }
        
        // Refresh expanded pages
        let (expanded, mapping) = expandFlipPages(pages)
        expandedPages = expanded
        originalIndexMap = mapping
        
        // Adjust current index if needed
        if currentViewedIndex >= expandedPages.count {
            currentViewedIndex = max(0, expandedPages.count - 1)
        }
        
        // If no pages left, dismiss
        if expandedPages.isEmpty {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    // MARK: - Display Page Content (Read-only)
    @ViewBuilder
    func displayPageContent(page: FlipPage, scaleFactor: CGFloat = 1.0) -> some View {
        switch page.type {
        case .cover:
            VStack(spacing: 16) {
                Spacer()
                Text(page.title ?? "Life Stories")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                    .multilineTextAlignment(.center)
                    .textCase(.uppercase)
                
                if let caption = page.caption {
                    Text(caption)
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .italic()
                        .foregroundColor(Color(red: 122/255, green: 122/255, blue: 122/255))
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            
        case .text, .leftBars:
            // SCALED CSS: .text-content styling
            VStack(alignment: .leading, spacing: 0) {
                if let title = page.title {
                    // Show title with different styling for continued pages
                    if isContinuedPage {
                        // SCALED CSS: .continued-title (line 144-146)
                        VStack(spacing: 0) {
                            Text(title)
                                .font(.custom("Baskerville", size: 8 * scaleFactor)) // CSS: 8px × scale
                                .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                                .textCase(.uppercase)
                                .kerning(0.3 * scaleFactor)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            Text("(continued)")
                                .font(.custom("Baskerville", size: 6 * scaleFactor).italic()) // CSS: 6px × scale
                                .foregroundColor(Color(red: 122/255, green: 122/255, blue: 122/255))
                                .textCase(.lowercase)
                                .opacity(0.7)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 2 * scaleFactor)
                        }
                        .padding(.bottom, 4 * scaleFactor)
                    } else {
                        // SCALED CSS: .page-title (line 123-141)
                        Text(title)
                            .font(.custom("Baskerville", size: 12 * scaleFactor)) // CSS: 12px × scale
                            .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                            .textCase(.uppercase)
                            .kerning(0.3 * scaleFactor)
                            .multilineTextAlignment(.center)
                            .lineSpacing((1.3 * 12 - 12) * scaleFactor) // CSS: line-height: 1.3
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8 * scaleFactor)
                    }
                }
                
                // SCALED CSS: .text-content (line 160-171) with DROP CAP
                // Check if this is a story start (first page of chapter, not continuation)
                if !isContinuedPage && !displayedText.isEmpty {
                    // DROP CAP: First letter large, rest normal
                    HStack(alignment: .top, spacing: 2 * scaleFactor) {
                        // First letter (drop cap)
                        Text(String(displayedText.prefix(1)))
                            .font(.custom("Baskerville", size: 24 * scaleFactor)) // CSS: 24px × scale (4x body)
                            .fontWeight(.regular) // CSS: font-weight: 400
                            .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255)) // Darker for drop cap
                            .textCase(.uppercase)
                        
                        // Rest of text
                        Text(String(displayedText.dropFirst()))
                            .font(.custom("Baskerville", size: 6 * scaleFactor))
                            .foregroundColor(Color(red: 90/255, green: 90/255, blue: 90/255))
                            .lineSpacing((1.4 * 6 - 6) * scaleFactor)
                            .kerning(0.06 * scaleFactor)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Normal text (no drop cap for continued pages)
                    Text(displayedText)
                        .font(.custom("Baskerville", size: 6 * scaleFactor))
                        .foregroundColor(Color(red: 90/255, green: 90/255, blue: 90/255))
                        .lineSpacing((1.4 * 6 - 6) * scaleFactor)
                        .kerning(0.06 * scaleFactor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Debug logging (moved outside conditional)
                let _ = print("📖 Swift PageZoomView: Text view - isContinued: \(isContinuedPage), hasDropCap: \(!isContinuedPage), text: \(displayedText.count) chars")
            }
            
        case .rightPhoto:
            VStack(spacing: 16) {
                if let title = page.title {
                    Text(title)
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                        .textCase(.uppercase)
                        .kerning(0.5)
                }
                
                if let imageName = page.imageName {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .cornerRadius(4)
                }
                
                if let caption = page.caption {
                    Text(caption)
                        .font(.system(size: 8, weight: .light, design: .serif))
                        .italic()
                        .foregroundColor(Color(red: 122/255, green: 122/255, blue: 122/255))
                        .multilineTextAlignment(.center)
                }
            }
            
        case .mixed:
            // Mixed pages: show text AND image together
            VStack(alignment: .leading, spacing: 16) {
                if let title = page.title {
                    Text(title)
                        .font(.system(size: 12 * scaleFactor, weight: .regular, design: .serif))
                        .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                        .textCase(.uppercase)
                        .kerning(0.5 * scaleFactor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                
                // Text content for mixed pages
                if let text = page.text, !text.isEmpty {
                    Text(text)
                        .font(.custom("Baskerville", size: 6 * scaleFactor))
                        .foregroundColor(Color(red: 90/255, green: 90/255, blue: 90/255))
                        .lineSpacing((1.4 * 6 - 6) * scaleFactor)
                        .kerning(0.06 * scaleFactor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Image for mixed pages
                if let imageName = page.imageName {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300 * scaleFactor)
                        .cornerRadius(4)
                }
                
                // Caption if present
                if let caption = page.caption {
                    Text(caption)
                        .font(.system(size: 8 * scaleFactor, weight: .light, design: .serif))
                        .italic()
                        .foregroundColor(Color(red: 122/255, green: 122/255, blue: 122/255))
                        .multilineTextAlignment(.center)
                }
            }
            
        case .html:
            Text(page.text ?? "")
                .font(.system(size: 6, weight: .light, design: .serif))
                .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                
        case .photoLayout, .mixed:
            // Display photo layouts with text if present
            ZStack {
                // Page dimensions for layout positioning
                let pageWidth: CGFloat = flipbookPageWidth * scaleFactor
                let pageHeight: CGFloat = flipbookPageHeight * scaleFactor
                
                VStack(alignment: .leading, spacing: 12 * scaleFactor) {
                    // Title if present
                    if let title = page.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 12 * scaleFactor, weight: .regular, design: .serif))
                            .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                            .textCase(.uppercase)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8 * scaleFactor)
                    }
                    
                    // Text content if present (for mixed pages)
                    if let text = page.text, !text.isEmpty {
                        Text(text)
                            .font(.custom("Baskerville", size: 6 * scaleFactor))
                            .foregroundColor(Color(red: 90/255, green: 90/255, blue: 90/255))
                            .lineSpacing((1.4 * 6 - 6) * scaleFactor)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 12 * scaleFactor)
                    }
                    
                    Spacer()
                }
                
                // Render photo layouts
                if let layouts = page.photoLayouts, !layouts.isEmpty {
                    ForEach(layouts) { layout in
                        PhotoLayoutDisplayView(
                            layout: layout,
                            pageWidth: pageWidth,
                            pageHeight: pageHeight,
                            scaleFactor: scaleFactor,
                            isSelected: selectedLayoutId == layout.id,
                            onTap: {
                                // Always allow tap to add photo, even in display mode
                                photoToAddToLayout = layout.id
                                showPhotoSourcePicker = true
                            }
                        )
                    }
                }
            }
            .frame(width: flipbookPageWidth * scaleFactor, height: flipbookPageHeight * scaleFactor)
        }
    }
    
    // MARK: - Editable Page Content
    @ViewBuilder
    func editablePageContent(page: FlipPage) -> some View {
        switch page.type {
        case .cover:
            VStack(spacing: 16) {
                Spacer()
                VStack(spacing: 4) {
                    TextField("", text: $editedTitle)
                        .font(.system(size: 24, weight: .medium, design: .serif))
                        .foregroundColor(titleExceeded ? Color.red : Color(red: 58/255, green: 58/255, blue: 58/255))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 8)
                        .background(Color.clear)
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(titleExceeded ? Color.red.opacity(0.5) : Color(red: 200/255, green: 190/255, blue: 180/255).opacity(0.5))
                                .offset(y: 20),
                            alignment: .bottom
                        )
                        .onChange(of: editedTitle) { newValue in
                            let limit = titleCharLimit
                            if newValue.count > limit {
                                editedTitle = String(newValue.prefix(limit))
                                titleExceeded = true
                            } else {
                                titleExceeded = false
                                // Recalculate limits as title changes
                                _ = dynamicLimits
                            }
                        }
                    
                    TextLimitIndicator(text: editedTitle, limit: titleCharLimit, countWords: false)
                }
                
                VStack(spacing: 4) {
                    TextField("", text: $editedCaption)
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .italic()
                        .foregroundColor(captionExceeded ? Color.red : Color(red: 122/255, green: 122/255, blue: 122/255))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                        .background(Color.clear)
                        .onChange(of: editedCaption) { newValue in
                            if newValue.count > captionCharLimit {
                                editedCaption = String(newValue.prefix(captionCharLimit))
                                captionExceeded = true
                            } else {
                                captionExceeded = false
                            }
                        }
                    
                    TextLimitIndicator(text: editedCaption, limit: captionCharLimit, countWords: false)
                }
                Spacer()
            }
            
        case .text, .leftBars:
            VStack(alignment: .leading, spacing: 12) {
                // Title with book-like editing
                VStack(spacing: 4) {
                    TextField("", text: $editedTitle)
                        .font(.system(size: isContinuedPage ? 8 : 12, weight: .regular, design: .serif))
                        .foregroundColor(titleExceeded ? Color.red : Color(red: 58/255, green: 58/255, blue: 58/255))
                        .textCase(.uppercase)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                        .background(
                            Color(red: 250/255, green: 248/255, blue: 243/255).opacity(0.5)
                        )
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(titleExceeded ? Color.red.opacity(0.5) : Color(red: 200/255, green: 190/255, blue: 180/255))
                                .offset(y: 15),
                            alignment: .bottom
                        )
                        .onChange(of: editedTitle) { newValue in
                            let limit = titleCharLimit
                            if newValue.count > limit {
                                editedTitle = String(newValue.prefix(limit))
                                titleExceeded = true
                            } else {
                                titleExceeded = false
                                // Recalculate limits as title changes
                                _ = dynamicLimits
                            }
                        }
                    
                    TextLimitIndicator(text: editedTitle, limit: titleCharLimit, countWords: false)
                }
                
                // Text editor styled like book page with word limit
                VStack(spacing: 4) {
                    TextEditor(text: $editedText)
                        .font(.system(size: 10, weight: .light, design: .serif))
                        .foregroundColor(textExceeded ? Color.red : Color(red: 58/255, green: 58/255, blue: 58/255))
                        .lineSpacing(4)
                        .padding(8)
                        .background(Color.clear)
                        .frame(minHeight: 300)
                        .scrollContentBackground(.hidden) // iOS 16+ to hide default background
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(textExceeded ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                        .onChange(of: editedText) { newValue in
                            let wordCount = newValue.split(separator: " ").count
                            if wordCount > textWordLimit {
                                // Trim to word limit
                                let words = newValue.split(separator: " ").prefix(textWordLimit)
                                editedText = words.joined(separator: " ")
                                textExceeded = true
                            } else {
                                textExceeded = false
                            }
                        }
                    
                    TextLimitIndicator(text: editedText, limit: textWordLimit, countWords: true)
                }
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 250/255, green: 248/255, blue: 243/255).opacity(0.3))
                    )
            }
            
        case .rightPhoto, .mixed:
            VStack(spacing: 16) {
                TextField("", text: $editedTitle)
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                    .background(Color.clear)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(red: 200/255, green: 190/255, blue: 180/255).opacity(0.5))
                            .offset(y: 12),
                        alignment: .bottom
                    )
                
                if let imageName = page.imageName {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 250)
                        .cornerRadius(4)
                        .overlay(
                            Text("Tap to change image")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                                .opacity(0.8),
                            alignment: .bottom
                        )
                }
                
                TextField("", text: $editedCaption)
                    .font(.system(size: 8, weight: .light, design: .serif))
                    .italic()
                    .foregroundColor(Color(red: 122/255, green: 122/255, blue: 122/255))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                    .background(Color.clear)
            }
            
        case .html:
            TextEditor(text: $editedText)
                .font(.system(size: 10, weight: .light, design: .serif))
                .frame(minHeight: 300)
                
        case .photoLayout, .mixed:
            // Editable photo layout page with drag/resize/rotate/delete
            ZStack {
                // Page dimensions for layout positioning
                let pageWidth: CGFloat = flipbookPageWidth
                let pageHeight: CGFloat = flipbookPageHeight
                
                VStack(alignment: .leading, spacing: 12) {
                    // Title editor if present
                    if let title = page.title {
                        TextField("", text: $editedTitle)
                            .font(.system(size: 12, weight: .regular, design: .serif))
                            .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                            .textCase(.uppercase)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 4)
                            .background(Color.clear)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(Color(red: 200/255, green: 190/255, blue: 180/255).opacity(0.5))
                                    .offset(y: 12),
                                alignment: .bottom
                            )
                    }
                    
                    // Text editor if present (for mixed pages)
                    if let text = page.text {
                        TextEditor(text: $editedText)
                            .font(.custom("Baskerville", size: 6))
                            .foregroundColor(Color(red: 90/255, green: 90/255, blue: 90/255))
                            .lineSpacing(4)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(red: 250/255, green: 248/255, blue: 243/255).opacity(0.3))
                            )
                    }
                    
                    Spacer()
                }
                .padding()
                
                // Render editable photo layouts
                if let layouts = page.photoLayouts, !layouts.isEmpty {
                    ForEach(layouts.indices, id: \.self) { index in
                        let layout = layouts[index]
                        EditablePhotoLayoutView(
                            layout: Binding(
                                get: { layouts[index] },
                                set: { newLayout in
                                    updateLayout(at: index, with: newLayout, in: page)
                                }
                            ),
                            pageWidth: pageWidth,
                            pageHeight: pageHeight,
                            isSelected: selectedLayoutId == layout.id,
                            onSelect: {
                                selectedLayoutId = layout.id
                            },
                            onDelete: {
                                layoutToDelete = layout.id
                                showDeleteLayoutConfirmation = true
                            },
                            onAddPhoto: {
                                photoToAddToLayout = layout.id
                                showPhotoSourcePicker = true
                            }
                        )
                    }
                }
            }
            .frame(width: flipbookPageWidth, height: flipbookPageHeight)
            .alert("Delete Photo Layout", isPresented: $showDeleteLayoutConfirmation) {
                Button("Delete", role: .destructive) {
                    if let layoutId = layoutToDelete {
                        deleteLayout(layoutId, from: page)
                    }
                }
                Button("Cancel", role: .cancel) {
                    layoutToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this photo layout?")
            }
        }
    }
    
    // MARK: - Photo Layout Helper Functions
    private func updateLayout(at index: Int, with newLayout: PhotoLayout, in page: FlipPage) {
        guard currentViewedIndex >= 0 && currentViewedIndex < expandedPages.count else { return }
        guard var layouts = expandedPages[currentViewedIndex].photoLayouts,
              index < layouts.count else { return }
        
        layouts[index] = newLayout
        expandedPages[currentViewedIndex].photoLayouts = layouts
        
        // Sync back to original pages array
        if currentViewedIndex < originalIndexMap.count {
            let originalIndex = originalIndexMap[currentViewedIndex]
            if originalIndex >= 0 && originalIndex < pages.count {
                pages[originalIndex].photoLayouts = layouts
            }
        }
    }
    
    private func deleteLayout(_ layoutId: UUID, from page: FlipPage) {
        guard currentViewedIndex >= 0 && currentViewedIndex < expandedPages.count else { return }
        guard var layouts = expandedPages[currentViewedIndex].photoLayouts else { return }
        
        layouts.removeAll { $0.id == layoutId }
        expandedPages[currentViewedIndex].photoLayouts = layouts.isEmpty ? nil : layouts
        
        // Sync back to original pages array
        if currentViewedIndex < originalIndexMap.count {
            let originalIndex = originalIndexMap[currentViewedIndex]
            if originalIndex >= 0 && originalIndex < pages.count {
                pages[originalIndex].photoLayouts = layouts.isEmpty ? nil : layouts
            }
        }
        
        selectedLayoutId = nil
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    private func addPhotoToLayout(_ layoutId: UUID, image: UIImage, in page: FlipPage) {
        guard currentViewedIndex >= 0 && currentViewedIndex < expandedPages.count else { return }
        guard var layouts = expandedPages[currentViewedIndex].photoLayouts,
              let index = layouts.firstIndex(where: { $0.id == layoutId }) else { return }
        
        // Convert to base64
        if let imageData = image.jpegData(compressionQuality: 0.7) {
            let base64String = "data:image/jpeg;base64," + imageData.base64EncodedString()
            layouts[index].imageData = base64String
            
            expandedPages[currentViewedIndex].photoLayouts = layouts
            
            // Sync back to original pages array
            if currentViewedIndex < originalIndexMap.count {
                let originalIndex = originalIndexMap[currentViewedIndex]
                if originalIndex >= 0 && originalIndex < pages.count {
                    pages[originalIndex].photoLayouts = layouts
                }
            }
            
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
        
        photoToAddToLayout = nil
    }
    
}

// MARK: - Photo Layout Display View
struct PhotoLayoutDisplayView: View {
    let layout: PhotoLayout
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let scaleFactor: CGFloat
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            // Frame background
            RoundedRectangle(cornerRadius: layout.borderStyle == .polaroid ? 0 : 8 * scaleFactor)
                .fill(layout.borderStyle.color)
                .frame(
                    width: layout.frame.width * scaleFactor,
                    height: layout.frame.height * scaleFactor
                )
                .shadow(
                    color: layout.borderStyle.hasShadow ? Color.black.opacity(0.2) : .clear,
                    radius: layout.borderStyle.hasShadow ? 5 * scaleFactor : 0,
                    x: 0,
                    y: 2 * scaleFactor
                )
            
            // Photo or placeholder
            if let imageData = layout.imageData,
               let data = Data(base64Encoded: imageData.replacingOccurrences(of: "data:image/jpeg;base64,", with: "")),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: layout.frame.width * scaleFactor,
                        height: layout.frame.height * scaleFactor
                    )
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: layout.borderStyle == .polaroid ? 0 : 4 * scaleFactor))
            } else {
                // Placeholder
                VStack(spacing: 8 * scaleFactor) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24 * scaleFactor))
                        .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255).opacity(0.3))
                    
                    Text("Tap to add photo")
                        .font(.system(size: 10 * scaleFactor))
                        .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255).opacity(0.5))
                }
                .frame(
                    width: layout.frame.width * scaleFactor,
                    height: layout.frame.height * scaleFactor
                )
                .background(Color.white.opacity(0.8))
            }
        }
        .frame(
            width: layout.frame.width * scaleFactor,
            height: layout.frame.height * scaleFactor
        )
        .position(
            x: layout.frame.midX * scaleFactor,
            y: layout.frame.midY * scaleFactor
        )
        .rotationEffect(.degrees(layout.rotation))
        .overlay(
            RoundedRectangle(cornerRadius: 8 * scaleFactor)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2 * scaleFactor)
        )
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Editable Photo Layout View
struct EditablePhotoLayoutView: View {
    @Binding var layout: PhotoLayout
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onAddPhoto: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // Frame background
            RoundedRectangle(cornerRadius: layout.borderStyle == .polaroid ? 0 : 8)
                .fill(layout.borderStyle.color)
                .frame(width: layout.frame.width, height: layout.frame.height)
                .shadow(
                    color: layout.borderStyle.hasShadow ? Color.black.opacity(0.2) : .clear,
                    radius: layout.borderStyle.hasShadow ? 5 : 0,
                    x: 0,
                    y: 2
                )
            
            // Photo or placeholder
            if let imageData = layout.imageData,
               let data = Data(base64Encoded: imageData.replacingOccurrences(of: "data:image/jpeg;base64,", with: "")),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: layout.frame.width, height: layout.frame.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: layout.borderStyle == .polaroid ? 0 : 4))
            } else {
                // Placeholder
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255).opacity(0.3))
                    
                    Text("Tap to add photo")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255).opacity(0.5))
                }
                .frame(width: layout.frame.width, height: layout.frame.height)
                .background(Color.white.opacity(0.8))
            }
        }
        .frame(width: layout.frame.width, height: layout.frame.height)
        .position(
            x: layout.frame.midX + dragOffset.width,
            y: layout.frame.midY + dragOffset.height
        )
        .rotationEffect(.degrees(layout.rotation))
        .overlay(
            Group {
                if isSelected {
                    // Selection border
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: layout.frame.width + 4, height: layout.frame.height + 4)
                    
                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.red)
                            .background(Circle().fill(Color.white))
                    }
                    .position(
                        x: layout.frame.minX - 12,
                        y: layout.frame.minY - 12
                    )
                }
            }
        )
        .gesture(
            TapGesture()
                .onEnded { _ in
                    onSelect()
                    if layout.imageData == nil {
                        onAddPhoto()
                    }
                }
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    if isSelected {
                        isDragging = true
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if isSelected {
                        // Update layout position
                        var newFrame = layout.frame
                        newFrame.origin.x += value.translation.width
                        newFrame.origin.y += value.translation.height
                        
                        // Constrain to page boundaries
                        let margin: CGFloat = 10
                        newFrame.origin.x = max(margin, min(newFrame.origin.x, pageWidth - newFrame.width - margin))
                        newFrame.origin.y = max(margin, min(newFrame.origin.y, pageHeight - newFrame.height - margin))
                        
                        layout.frame = newFrame
                        dragOffset = .zero
                        isDragging = false
                    }
                }
        )
    }
}

// MARK: - FlipbookView Wrapper
struct FlipbookViewWithWebView: View {
    let pages: [FlipPage]
    @Binding var currentPage: Int
    @Binding var webView: WKWebView?
    let isKidsBook: Bool
    let onReady: (() -> Void)?
    let onFlip: ((Int) -> Void)?
    let onPageTap: ((Int) -> Void)?
    let onPhotoFrameTap: ((Int, String, Int) -> Void)?
    let onPhotoFrameMoved: ((Int, String, CGFloat, CGFloat) -> Void)?
    
    var body: some View {
        FlipbookView(
            pages: pages,
            currentPage: $currentPage,
            webView: $webView,
            isKidsBook: isKidsBook,
            onReady: onReady,
            onFlip: onFlip,
            onPageTap: onPageTap,
            onPhotoFrameTap: onPhotoFrameTap,
            onPhotoFrameMoved: onPhotoFrameMoved
        )
        .onAppear {
            // WebView will be set by FlipbookView internally
        }
    }
}

// MARK: - Preview
struct StorybookView_Previews: PreviewProvider {
    static var previews: some View {
        StorybookView()
            .environmentObject(ProfileViewModel())
    }
}
