import SwiftUI
import WebKit



// MARK: - Main Storybook View
struct StorybookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileVM: ProfileViewModel
    @StateObject private var storyVM = StoryPageViewModel()

    @State private var currentPage = 0
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [UIImage] = []
    @State private var flipbookReady = false
    @State private var useFallback = false
    @State private var flipbookError = false
    @State private var webView: WKWebView?
    @State private var flipbookPages: [FlipPage] = []
    @State private var showingUserContent = false

    // Sample pages for when user hasn't generated content yet
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
    
    // NEW: Generate FlipPage content from real story data
    private func generateFlipbookContent() {
        // Check if we have a generated storybook for this profile
        if storyVM.hasGeneratedStorybook && !storyVM.pageItems.isEmpty {
            // Convert PageItems to FlipPages using the enhanced system
            flipbookPages = storyVM.generateFlipPages(from: storyVM.pageItems)
            showingUserContent = true
            print("StorybookView: Using REAL user-generated content with \(flipbookPages.count) pages")
        } else {
            // Use enhanced sample pages as fallback
            flipbookPages = FlipPage.samplePages
            showingUserContent = false
            print("StorybookView: Using enhanced sample pages with \(flipbookPages.count) pages (no user content yet)")
        }
    }

    var body: some View {
        NavigationView {
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

                    GeometryReader { geo in
                        let bookSize = calculateBookSize(for: geo.size)
                        
                        VStack(spacing: 0) {
                            // Flipbook preview with real content
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
                                // Enhanced Flipbook implementation with real content
                                ZStack {
                                    FlipbookView(
                                        pages: flipbookPages,
                                        currentPage: $currentPage,
                                        onReady: {
                                            print("StorybookView: Enhanced flipbook ready!")
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
                                        }
                                    )
                                    .frame(width: bookSize.width, height: bookSize.height)
                                    .background(Color.red.opacity(0.3)) // DEBUG: Show the frame
                                    
                                    // Show indicator if using user content
                                    if showingUserContent {
                                        VStack {
                                            HStack {
                                                Text("Your Book")
                                                    .font(.caption)
                                                    .padding(4)
                                                    .background(Color.green.opacity(0.8))
                                                    .foregroundColor(.white)
                                                    .cornerRadius(4)
                                                Spacer()
                                            }
                                            Spacer()
                                        }
                                        .padding(8)
                                    }
                                }
                                .onAppear {
                                    print("StorybookView: Enhanced flipbook view appeared")
                                    print("StorybookView: Geometry size: \(geo.size)")
                                    print("StorybookView: Calculated book size: \(bookSize)")
                                    print("StorybookView: Flipbook pages count: \(flipbookPages.count)")
                                    print("StorybookView: Showing user content: \(showingUserContent)")
                                    
                                    // Set a timeout to fallback if flipbook doesn't load
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        if !flipbookReady || flipbookError {
                                            print("StorybookView: Flipbook timeout or error - falling back to native")
                                            useFallback = true
                                        }
                                    }
                                }
                            }

                            Spacer()

                            if flipbookPages.count > 1 {
                                Text("Swipe to flip pages")
                                    .font(Tokens.Typography.hint)
                                    .foregroundColor(Tokens.ink.opacity(0.6))
                                    .padding(.top, Tokens.bookSpacing)
                                    .padding(.bottom, Tokens.buttonSpacing)
                            }

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
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerSheet(
                isPresented: $showPhotoPicker,
                onPhotosSelected: { photos in
                    selectedPhotos = photos
                }
            )
        }
        .onAppear { 
            currentPage = 0
            // Load storybook content for current profile
            storyVM.loadStorybookForProfile(profileVM.selectedProfile.id)
            generateFlipbookContent()
        }
        .onChange(of: profileVM.selectedProfile.id) { _, _ in
            // Reload content when profile changes
            storyVM.loadStorybookForProfile(profileVM.selectedProfile.id)
            generateFlipbookContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh content when app comes to foreground (e.g., returning from StoryPage)
            storyVM.loadStorybookForProfile(profileVM.selectedProfile.id)
            generateFlipbookContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Additional refresh when app becomes active
            storyVM.loadStorybookForProfile(profileVM.selectedProfile.id)
            generateFlipbookContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .storybookContentGenerated)) { _ in
            // Immediate refresh when new content is generated
            print("StorybookView: Received storybook content generated notification")
            storyVM.loadStorybookForProfile(profileVM.selectedProfile.id)
            generateFlipbookContent()
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
                Text(showingUserContent ? "Your Storybook" : "Create your book")
                    .font(Tokens.Typography.title)
                    .foregroundColor(Tokens.ink)

                Text(showingUserContent ? "Your memories in a beautiful book" : "Flip through a finished book")
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
                Text(showingUserContent ? "Create new book" : "Create your own book")
                    .font(Tokens.Typography.button)
                    .foregroundColor(Tokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule().fill(Color.clear)
                    )
                    .primaryGradientOutline(lineWidth: Tokens.gradientStrokeWidth)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showingUserContent ? "Create new book" : "Create your own book")

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
}

// MARK: - Preview
struct StorybookView_Previews: PreviewProvider {
    static var previews: some View {
        StorybookView()
            .environmentObject(ProfileViewModel())
    }
}
