import SwiftUI
import WebKit

// MARK: - Main Storybook View
struct StorybookView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var profileVM: ProfileViewModel

    @State private var currentPage = 0
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [UIImage] = []
    @State private var flipbookReady = false
    @State private var useFallback = false
    @State private var flipbookError = false
    @State private var webView: WKWebView?
    @State private var showZoomedPage = false
    @State private var zoomedPageIndex: Int = 0
    @State private var flipbookPages = FlipPage.samplePages

    // Sample pages for the finished book preview
    private let samplePages = MockBookPage.samplePages
    
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
                                        onReady: {
                                            print("StorybookView: Flipbook ready!")
                                            flipbookReady = true
                                        },
                                        onFlip: { pageIndex in
                                            print("StorybookView: Page flipped to \(pageIndex)")
                                            if pageIndex == -1 {
                                                // Error occurred
                                                print("StorybookView: Flipbook error detected, falling back to native")
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
                                    
                                    // Debug overlay removed to prevent layout interference
                                }
                                .onAppear {
                                    print("StorybookView: Flipbook view appeared")
                                    print("StorybookView: Geometry size: \(geo.size)")
                                    print("StorybookView: Calculated book size: \(bookSize)")
                                    
                                    // DEBUG: Check if FlipbookView is getting proper space
                                    print("StorybookView: FlipbookView frame should be: \(bookSize)")
                                    
                                    // Set a timeout to fallback if flipbook doesn't load
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { // Reduced timeout for faster fallback
                                        if !flipbookReady || flipbookError {
                                            print("StorybookView: Flipbook timeout or error - falling back to native")
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
        .fullScreenCover(isPresented: $showZoomedPage) {
            PageZoomView(pageIndex: zoomedPageIndex, pages: $flipbookPages)
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
        // Trigger JavaScript PDF download
        if let webView = webView {
            webView.evaluateJavaScript("window.downloadPDF()")
        }
    }
}

// MARK: - Zoomed Page View
struct PageZoomView: View {
    let pageIndex: Int
    @Binding var pages: [FlipPage]
    @Environment(\.presentationMode) var presentationMode
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedText: String = ""
    @State private var editedCaption: String = ""
    
    var currentPage: FlipPage? {
        guard pageIndex >= 0 && pageIndex < pages.count else { return nil }
        return pages[pageIndex]
    }
    
    // Check if this is a continued page based on previous pages having the same title
    var isContinuedPage: Bool {
        guard pageIndex > 0,
              let currentTitle = currentPage?.title,
              let previousTitle = pages[pageIndex - 1].title else { return false }
        return currentTitle == previousTitle
    }
    
    // Get the displayed text for this page (approximately 150 words if it's a text page)
    var displayedText: String {
        guard let fullText = currentPage?.text else { return "" }
        
        // If it's a text page, we need to calculate which portion to show
        // Based on the JavaScript splitting at ~150 words
        let wordsPerPage = 150
        let words = fullText.split(separator: " ")
        
        if words.count <= wordsPerPage {
            // Short text, show all
            return fullText
        }
        
        // Calculate which "page" of text this is
        var pageNumber = 0
        for i in 0..<pageIndex {
            if pages[i].title == currentPage?.title {
                pageNumber += 1
            }
        }
        
        let startIndex = pageNumber * wordsPerPage
        let endIndex = min(startIndex + wordsPerPage, words.count)
        
        if startIndex >= words.count {
            return fullText // Fallback to full text if calculation is off
        }
        
        let pageWords = words[startIndex..<endIndex]
        return pageWords.joined(separator: " ")
    }
    
    var body: some View {
        ZStack {
            // Soft blur background with parchment color
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
            
            VStack(spacing: 0) {
                // Navigation header
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Tokens.ink.opacity(0.8))
                            .background(Circle().fill(Color.white.opacity(0.9)))
                    }
                    .padding()
                    
                    Spacer()
                    
                    if !isEditing {
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
                        .padding()
                    } else {
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
                                // TODO: Implement saving changes back to the page model
                                // This would require passing a binding or callback to update the pages array
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
                }
                
                // Page content - displayed like the actual book page
                GeometryReader { geo in
                    ScrollView {
                        if let page = currentPage {
                            // Book page appearance
                            VStack {
                                ZStack {
                                    // Page background with realistic paper texture
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(red: 250/255, green: 248/255, blue: 243/255)) // Paper color
                                        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                                    
                                    // Page content with proper book formatting
                                    VStack(alignment: .leading, spacing: 0) {
                                        if isEditing {
                                            // Edit mode
                                            editablePageContent(page: page)
                                        } else {
                                            // Display mode - exactly as it appears in the book
                                            displayPageContent(page: page)
                                        }
                                    }
                                    .padding(40) // Book page margins
                                }
                                .frame(width: min(geo.size.width * 0.85, 500)) // Max width for readability
                                .frame(minHeight: geo.size.height * 0.7)
                                .padding(.vertical, 40)
                                
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .onAppear {
            if let page = currentPage {
                editedTitle = page.title ?? ""
                editedText = displayedText // Use the displayed text, not full text
                editedCaption = page.caption ?? ""
            }
        }
    }
    
    // MARK: - Display Page Content (Read-only)
    @ViewBuilder
    private func displayPageContent(page: FlipPage) -> some View {
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
            VStack(alignment: .leading, spacing: 12) {
                if let title = page.title {
                    // Show title with different styling for continued pages
                    if isContinuedPage {
                        VStack(spacing: 4) {
                            Text(title)
                                .font(.system(size: 8, weight: .regular, design: .serif)) // Smaller for continued
                                .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                                .textCase(.uppercase)
                                .kerning(0.5)
                                .frame(maxWidth: .infinity)
                            Text("(continued)")
                                .font(.system(size: 6, weight: .light, design: .serif))
                                .italic()
                                .foregroundColor(Color(red: 122/255, green: 122/255, blue: 122/255))
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.bottom, 8)
                    } else {
                        Text(title)
                            .font(.system(size: 12, weight: .regular, design: .serif))
                            .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                            .textCase(.uppercase)
                            .kerning(0.5)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8)
                    }
                }
                
                // Use the calculated displayed text instead of full text
                Text(displayedText)
                    .font(.system(size: 10, weight: .light, design: .serif)) // Slightly larger for readability in zoom
                    .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
        case .rightPhoto, .mixed:
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
            
        case .html:
            Text(page.text ?? "")
                .font(.system(size: 6, weight: .light, design: .serif))
                .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
        }
    }
    
    // MARK: - Editable Page Content
    @ViewBuilder
    private func editablePageContent(page: FlipPage) -> some View {
        switch page.type {
        case .cover:
            VStack(spacing: 16) {
                Spacer()
                TextField("", text: $editedTitle)
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
                    .background(Color.clear)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(red: 200/255, green: 190/255, blue: 180/255).opacity(0.5))
                            .offset(y: 20),
                        alignment: .bottom
                    )
                
                TextField("", text: $editedCaption)
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .italic()
                    .foregroundColor(Color(red: 122/255, green: 122/255, blue: 122/255))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                    .background(Color.clear)
                Spacer()
            }
            
        case .text, .leftBars:
            VStack(alignment: .leading, spacing: 12) {
                // Title with book-like editing
                TextField("", text: $editedTitle)
                    .font(.system(size: isContinuedPage ? 8 : 12, weight: .regular, design: .serif))
                    .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                    .background(
                        Color(red: 250/255, green: 248/255, blue: 243/255).opacity(0.5)
                    )
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(red: 200/255, green: 190/255, blue: 180/255))
                            .offset(y: 15),
                        alignment: .bottom
                    )
                
                // Text editor styled like book page
                TextEditor(text: $editedText)
                    .font(.system(size: 10, weight: .light, design: .serif))
                    .foregroundColor(Color(red: 58/255, green: 58/255, blue: 58/255))
                    .lineSpacing(4)
                    .padding(8)
                    .background(Color.clear)
                    .frame(minHeight: 300)
                    .scrollContentBackground(.hidden) // iOS 16+ to hide default background
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
        }
    }
    
}

// MARK: - FlipbookView Wrapper
struct FlipbookViewWithWebView: View {
    let pages: [FlipPage]
    @Binding var currentPage: Int
    @Binding var webView: WKWebView?
    let onReady: (() -> Void)?
    let onFlip: ((Int) -> Void)?
    let onPageTap: ((Int) -> Void)?
    
    var body: some View {
        FlipbookView(
            pages: pages,
            currentPage: $currentPage,
            onReady: onReady,
            onFlip: onFlip,
            onPageTap: onPageTap
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
