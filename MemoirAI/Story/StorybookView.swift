import SwiftUI
import WebKit

// MARK: - Main Storybook View
struct StorybookView: View {
    @Environment(\.dismiss) private var dismiss
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

    // Sample pages for the finished book preview
    private let samplePages = MockBookPage.samplePages
    private let flipbookPages = FlipPage.samplePages
    
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
                // Warm parchment gradient background
                LinearGradient(
                    colors: [Tokens.bgPrimary, Tokens.bgWash],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // Download button in top-right
                VStack {
                    HStack {
                        Spacer()
                        Button(action: downloadBook) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Tokens.ink.opacity(0.7))
                                .background(Circle().fill(Color.white.opacity(0.9)))
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 50)
                    }
                    Spacer()
                }

                VStack(spacing: 0) {
                    headerView

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
            ZoomedPageView(pageIndex: zoomedPageIndex, pages: flipbookPages)
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Tokens.ink.opacity(0.7))
                    .padding(10)
                    .background(Tokens.bgWash)
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: Tokens.headerSpacing) {
                Text("Create your book")
                    .font(Tokens.Typography.title)
                    .foregroundColor(Tokens.ink)

                Text("Flip through a finished book")
                    .font(Tokens.Typography.subtitle)
                    .foregroundColor(Tokens.ink.opacity(0.7))
            }

            Spacer()

            // Spacer to balance back button
            Color.clear
                .frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }

    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        VStack(spacing: Tokens.buttonSpacing) {
            // Primary: gradient-outline pill (navigates to creation flow)
            NavigationLink(destination: StoryPage().environmentObject(profileVM)) {
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
struct ZoomedPageView: View {
    let pageIndex: Int
    let pages: [FlipPage]
    @Environment(\.dismiss) private var dismiss
    
    var currentPage: FlipPage? {
        guard pageIndex >= 0 && pageIndex < pages.count else { return nil }
        return pages[pageIndex]
    }
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Close button header
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }
                    .padding()
                }
                
                // Page content
                ScrollView {
                    if let page = currentPage {
                        VStack(alignment: .center, spacing: 24) {
                            // Handle different page types
                            switch page.type {
                            case .cover:
                                // Cover page display
                                VStack(spacing: 16) {
                                    Text(page.title ?? "Life Stories")
                                        .font(.system(size: 36, weight: .medium, design: .serif))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                    
                                    if let caption = page.caption {
                                        Text(caption)
                                            .font(.system(size: 20, weight: .light, design: .serif))
                                            .italic()
                                            .foregroundColor(.white.opacity(0.8))
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .padding(.vertical, 60)
                                
                            case .text, .leftBars:
                                // Text page display
                                VStack(alignment: .leading, spacing: 20) {
                                    if let title = page.title {
                                        Text(title)
                                            .font(.system(size: 28, weight: .medium, design: .serif))
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    
                                    if let text = page.text {
                                        Text(text)
                                            .font(.system(size: 18, weight: .light, design: .serif))
                                            .foregroundColor(.white.opacity(0.95))
                                            .lineSpacing(10)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    
                                    if let caption = page.caption {
                                        Text(caption)
                                            .font(.system(size: 16, weight: .light, design: .serif))
                                            .italic()
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                
                            case .rightPhoto, .mixed:
                                // Photo page display
                                VStack(spacing: 20) {
                                    if let title = page.title {
                                        Text(title)
                                            .font(.system(size: 28, weight: .medium, design: .serif))
                                            .foregroundColor(.white)
                                    }
                                    
                                    // Display image if available
                                    if let imageName = page.imageName {
                                        Image(imageName)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxHeight: 400)
                                            .cornerRadius(8)
                                    }
                                    
                                    if let caption = page.caption {
                                        Text(caption)
                                            .font(.system(size: 16, weight: .light, design: .serif))
                                            .italic()
                                            .foregroundColor(.white.opacity(0.8))
                                            .multilineTextAlignment(.center)
                                    }
                                    
                                    if let text = page.text {
                                        Text(text)
                                            .font(.system(size: 18, weight: .light, design: .serif))
                                            .foregroundColor(.white.opacity(0.95))
                                            .lineSpacing(10)
                                    }
                                }
                                
                            case .html:
                                // HTML page (fallback)
                                Text(page.text ?? "")
                                    .font(.system(size: 18, weight: .light, design: .serif))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    } else {
                        // Error state
                        Text("Page not found")
                            .font(.system(size: 20, weight: .medium, design: .serif))
                            .foregroundColor(.white.opacity(0.5))
                            .padding()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
