import SwiftUI
import PhotosUI
import Combine
import RevenueCat
import RevenueCatUI

// Enhanced color definitions for book-like appearance
struct StoryPageLocalColors {
    let softCream = Color(red: 0.98, green: 0.96, blue: 0.89)
    let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    let defaultBlack = Color.black
    let defaultGray = Color.gray
    let defaultRed = Color.red
    let defaultWhite = Color.white
    let arrowColor = Color.white.opacity(0.9)
    let subtleControlBackground = Color.black.opacity(0.07)
    let shadowColor = Color.black.opacity(0.15)
    let bookFrameFill = Color.white.opacity(0.95)
    let bookFrameStroke = Color.gray.opacity(0.3)
    let fullScreenOverlayBackground = Color.black.opacity(0.85)
    
    // Book-specific colors - elegant and clean
    let bookPageBackground = Color(red: 0.99, green: 0.97, blue: 0.94) // Warm paper white
    let bookTextColor = Color(red: 0.2, green: 0.2, blue: 0.2) // Soft black for readability
    let chapterTitleColor = Color(red: 0.4, green: 0.3, blue: 0.2) // Elegant brown
    let pageNumberColor = Color(red: 0.5, green: 0.5, blue: 0.5) // Subtle gray
    let decorativeElementColor = Color(red: 0.6, green: 0.4, blue: 0.3) // Warm accent
}

// Enhanced font system with distinct styles
extension Font {
    static func storyPageSerifFont(size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }
    
    // Kids book fonts - clean and readable (1/3 smaller)
    static func kidsBookTitleFont(size: CGFloat) -> Font {
        .custom("Georgia-Bold", size: size / 3.0) // Made 1/3 smaller
    }
    
    static func kidsBookBodyFont(size: CGFloat) -> Font {
        .custom("Georgia", size: size / 3.0) // Made 1/3 smaller
    }
    
    // Professional vertical book fonts - elegant and "liney"
    static func professionalTitleFont(size: CGFloat) -> Font {
        .custom("Times New Roman", size: size) // More elegant, traditional book font
    }
    
    static func professionalBodyFont(size: CGFloat) -> Font {
        .custom("Times New Roman", size: size) // Consistent with title
    }
    
    static func professionalChapterFont(size: CGFloat) -> Font {
        .custom("Times New Roman", size: size).weight(.medium) // Slightly heavier for headers
    }
}

// Main StoryPage implementation
struct StoryPage: View {
    @State private var userGender: String = ""
    @State private var headshotImage: UIImage?
    @State private var grandparentName: String = ""
    @State private var showProfileSetup: Bool = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = StoryPageViewModel()
    
    @State private var headshotPickerItem: PhotosPickerItem?
    @State private var gender: String = ""
    @EnvironmentObject var profileVM: ProfileViewModel
    @State private var userRace: String = ""
    @StateObject private var subscriptionManager = RCSubscriptionManager.shared
    
    let localColors = StoryPageLocalColors()
    
    @State private var currentPageIndex = 0
    @State private var showSettings = false
    @State private var selectedImageForFullScreen: UIImage? = nil
    @State private var hasRequestedGeneration = false
    
    // Progress simulation
    @State private var fakeProgress: Double = 0
    @State private var realProgress: Double = 0
    @State private var cancellableTimer: AnyCancellable?
    
    // NEW: Download and regenerate functionality
    @State private var showDownloadSuccess = false
    @State private var showRegenerateConfirmation = false
    @State private var isDownloading = false
    
    // NEW: Paywall state - exactly like MemoirView
    @State private var showPaywall = false
    
    // NEW: Tooltip state for subscription status
    @State private var showSubscriptionTooltip = false
    
    private var displayProgress: Double {
        if realProgress > 0.05 && realProgress > fakeProgress {
            return realProgress
        }
        return max(fakeProgress, realProgress)
    }
    
    // NEW: Subscription check - exactly like MemoirView
    private var isSubscribed: Bool {
        subscriptionManager.activeTier != nil
    }
    
    @ViewBuilder
    private func storybookContentView(
        bookFrameWidth: CGFloat,
        bookContentHeightInsideFrame: CGFloat
    ) -> some View {
        if vm.isLoading {
            VStack(spacing: 12) {
                ProgressView(value: displayProgress)
                    .progressViewStyle(
                        LinearProgressViewStyle(tint: localColors.terracotta)
                    )
                    .frame(height: 6)
                    .padding(.horizontal, 40)
                    .animation(.linear(duration: 0.1), value: displayProgress)

                Text("\(Int(displayProgress * 100))%")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(localColors.defaultGray)
            }
        } else if let error = vm.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: error.contains("Maximum images reached") || error.contains("Not enough images") ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(error.contains("Maximum images reached") || error.contains("Not enough images") ? .orange : localColors.defaultRed.opacity(0.7))
                
                Text(error)
                    .font(.storyPageSerifFont(size: 16))
                    .multilineTextAlignment(.center)
                    .foregroundColor(error.contains("Maximum images reached") || error.contains("Not enough images") ? .orange : localColors.defaultRed)
                    .padding(.horizontal, 5)
                
                if error.contains("Maximum images reached") || error.contains("Not enough images") {
                    // Show subscription status
                    VStack(spacing: 8) {
                        Text("Images remaining: \(subscriptionManager.remainingAllowance)/50")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                        
                        if let tier = subscriptionManager.activeTier {
                            Text("Subscription: \(tier.displayName)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.top, 8)
                } else {
                    Button("Try Creating Again") {
                        generateStorybookWithPaywallCheck()
                    }
                    .font(.headline)
                    .foregroundColor(localColors.terracotta)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(localColors.terracotta.opacity(0.15))
                    .cornerRadius(10)
                }
            }
            .padding(20)
        } else if hasRequestedGeneration && !vm.pageItems.isEmpty {
            // Determine aspect ratio based on art style - FIXED LOGIC
            let isKidsBook = vm.currentArtStyle == .kidsBook
            let bookAspectRatio: CGFloat = isKidsBook ? (9.0 / 16.0) : (4.0 / 3.0) // HORIZONTAL for kids (9:16 inverted), VERTICAL for others (4:3)
            
            ZStack {
                TabView(selection: $currentPageIndex) {
                    ForEach(vm.pageItems.indices, id: \.self) { idx in
                        pageView(
                            for: vm.pageItems[idx],
                            at: idx,
                                frameWidth: bookFrameWidth * 0.9,
                            frameHeight: (bookFrameWidth * 0.9) * bookAspectRatio
                            )
                            .tag(idx)
                            .onTapGesture {
                            if case .illustration(let image, _) = vm.pageItems[idx] {
                                selectedImageForFullScreen = image
                            }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(
                    width: bookFrameWidth * 0.9,
                    height: (bookFrameWidth * 0.9) * bookAspectRatio
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if vm.pageItems.count > 1 {
                    HStack {
                        Button {
                            if currentPageIndex > 0 {
                                withAnimation(.easeInOut) { currentPageIndex -= 1 }
                            }
                        } label: {
                            Image(systemName: "arrow.left.circle.fill")
                                .shadow(radius: 3)
                        }
                        .disabled(currentPageIndex == 0)
                        .opacity(currentPageIndex == 0 ? 0.3 : 1.0)

                        Spacer()

                        Button {
                            if currentPageIndex < vm.pageItems.count - 1 {
                                withAnimation(.easeInOut) { currentPageIndex += 1 }
                            }
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .shadow(radius: 3)
                        }
                        .disabled(currentPageIndex == vm.pageItems.count - 1)
                        .opacity(currentPageIndex == vm.pageItems.count - 1 ? 0.3 : 1.0)
                    }
                    .font(.system(size: 40, weight: .thin))
                    .foregroundColor(localColors.arrowColor)
                    .padding(.horizontal, bookFrameWidth * 0.02)
                    .frame(width: bookFrameWidth * 0.95)
                }
            }
            .frame(
                width: bookFrameWidth * 0.9,
                height: (bookFrameWidth * 0.9) * bookAspectRatio
            )
        } else {
            VStack(spacing: 12) {
                Text("Your storybook awaits!")
                    .font(.storyPageSerifFont(size: 18))
                    .foregroundColor(localColors.defaultBlack.opacity(0.9))
                Text("Tap below to bring this profile's memories to life.")
                    .font(.system(size: 14))
                    .foregroundColor(localColors.defaultGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Button(action: {
                    showProfileSetup = true
                }) {
                    Text("Create My Storybook")
                        .font(.headline)
                        .foregroundColor(localColors.defaultWhite)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(localColors.terracotta)
                        .clipShape(Capsule())
                        .shadow(
                            color: localColors.terracotta.opacity(0.4),
                            radius: 5, y: 3
                        )
                }
                .disabled(vm.isLoading)
                .padding(.top, 10)
            }
            .padding()
        }
    }

    private func resetGenerationState() {
        // Don't clear vm.pageItems or vm.images - let persistence handle this
        vm.errorMessage = nil
        currentPageIndex = 0
        fakeProgress = 0
        realProgress = 0
        vm.progress = 0
        cancellableTimer?.cancel()
        vm.isLoading = false
        // Don't reset hasRequestedGeneration - let it persist
    }
        
        private func generateStorybookWithPaywallCheck() {
        let pagesToAttempt = vm.expectedPageCount()

            guard pagesToAttempt > 0 else {
                print("StoryPage: Attempting to generate 0 pages. Aborting.")
                vm.errorMessage = "Please select a valid number of pages to generate."
                return
            }
            
            // NEW: Check for active subscription first - same logic as MemoirView
            guard isSubscribed else {
                print("StoryPage: No active subscription. Showing paywall.")
                vm.isLoading = false
                hasRequestedGeneration = false
                showPaywall = true  // ← Simple paywall trigger like MemoirView
                return
            }
            
            // NEW: Check if user has reached image limit
            if subscriptionManager.hasReachedImageLimit {
                print("StoryPage: Image limit reached. Remaining: \(subscriptionManager.remainingAllowance)")
                vm.isLoading = false
                hasRequestedGeneration = false
                let renewalDate = subscriptionManager.getRenewalDateString()
                vm.errorMessage = "Maximum images reached (50). Your allowance will reset on \(renewalDate)."
                return
            }
            
            // Check if user has enough remaining allowance for the requested images
            if subscriptionManager.canGenerate(pages: pagesToAttempt) {
                print("StoryPage: Check successful. Proceeding with generation of \(pagesToAttempt) pages.")
                startActualGenerationProcess(pagesExpected: pagesToAttempt)
            } else {
                print("StoryPage: Insufficient allowance. Remaining: \(subscriptionManager.remainingAllowance), Requested: \(pagesToAttempt)")
                vm.isLoading = false
                hasRequestedGeneration = false
                let renewalDate = subscriptionManager.getRenewalDateString()
                vm.errorMessage = "Not enough images remaining (\(subscriptionManager.remainingAllowance) left). Your allowance will reset on \(renewalDate)."
            }
        }
        
        private func startActualGenerationProcess(pagesExpected: Int) {
            resetGenerationState()
            hasRequestedGeneration = true
            vm.isLoading = true
            
            let fakeIncrementPerTick = 0.004
            let targetFakeProgress = 0.4
            
            cancellableTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { _ in
                if fakeProgress < targetFakeProgress && !Task.isCancelled {
                    fakeProgress += fakeIncrementPerTick
                    if fakeProgress >= targetFakeProgress {
                        fakeProgress = targetFakeProgress
                        cancellableTimer?.cancel()
                    }
                } else {
                    cancellableTimer?.cancel()
                }
            }
            
            let currentProfileID = profileVM.selectedProfile.id
            Task {
                await vm.generateStorybook(forProfileID: currentProfileID)
                
                await MainActor.run {
                    cancellableTimer?.cancel()
                    
                    if vm.errorMessage == nil && !vm.images.isEmpty {
                        let actualImagesGenerated = vm.images.count
                        if actualImagesGenerated > 0 {
                            subscriptionManager.consume(pages: actualImagesGenerated)
                            print("StoryPage: Consumed \(actualImagesGenerated) images.")
                        }
                        self.realProgress = 1.0
                        self.fakeProgress = 1.0
                    } else {
                        print("StoryPage: Gen failed/no images. Error: \(vm.errorMessage ?? "N/A").")
                        self.realProgress = 0.0
                        self.fakeProgress = 0.0
                    }
                    if vm.isLoading { print("Warning: vm.isLoading is still true post-generation.")}
                }
            }
        }

    var body: some View {
        NavigationStack {
            ZStack {
                localColors.softCream
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // UPDATED HEADER with download button
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(localColors.defaultBlack.opacity(0.7))
                                .padding(10)
                                .background(localColors.subtleControlBackground)
                                .clipShape(Circle())
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text("Your Storybook")
                                .font(.storyPageSerifFont(size: 22))
                                .fontWeight(.medium)
                                .foregroundColor(localColors.defaultBlack.opacity(0.8))
                            
                            // NEW: Clickable subscription status indicator with tooltip
                            if subscriptionManager.hasActiveSubscription {
                                Button(action: {
                                    showSubscriptionTooltip = true
                                    // Auto-hide after 3 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        showSubscriptionTooltip = false
                                    }
                                }) {
                                    Text("\(subscriptionManager.remainingAllowance)/50 images")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(subscriptionManager.remainingAllowance <= 5 ? .red : .gray)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        Spacer()
                        
                        HStack(spacing: 12) {
                            // NEW: Download button (only show when storybook exists)
                            if hasRequestedGeneration && !vm.pageItems.isEmpty {
                                Button(action: downloadStorybook) {
                                    HStack(spacing: 4) {
                                        if isDownloading {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .progressViewStyle(CircularProgressViewStyle(tint: localColors.defaultBlack.opacity(0.7)))
                                        } else {
                                            Image(systemName: showDownloadSuccess ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                                .font(.system(size: 18, weight: .medium))
                                        }
                                    }
                                    .foregroundColor(showDownloadSuccess ? .green : localColors.defaultBlack.opacity(0.7))
                                    .padding(10)
                                    .background(localColors.subtleControlBackground)
                                    .clipShape(Circle())
                                }
                                .disabled(isDownloading)
                                .scaleEffect(showDownloadSuccess ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showDownloadSuccess)
                            }
                            
                            Button { showSettings = true } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(localColors.defaultBlack.opacity(0.7))
                                    .padding(10)
                                    .background(localColors.subtleControlBackground)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 5)
                    .padding(.bottom, 10)

                    // STORYBOOK CONTENT
                    GeometryReader { geo in
                        let bookFrameWidth = geo.size.width * 0.92
                        let isKidsBook = vm.currentArtStyle == .kidsBook
                        // FIXED: Proper aspect ratio calculation
                        let bookAspectRatio: CGFloat = isKidsBook ? (9.0 / 16.0) : (4.0 / 3.0) // HORIZONTAL for kids, VERTICAL for others
                        let bookContentAreaWidth = bookFrameWidth * 0.92
                        let bookContentHeightInsideFrame = bookContentAreaWidth * bookAspectRatio
                        let verticalPad: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 30 : 20
                        let bookFrameHeight = bookContentHeightInsideFrame + (verticalPad * 2)

                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(localColors.bookFrameFill)
                                .frame(width: bookFrameWidth, height: bookFrameHeight)
                                .shadow(color: localColors.shadowColor, radius: 12, x: 0, y: 6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(localColors.bookFrameStroke, lineWidth: 1.5)
                                )

                            storybookContentView(
                                bookFrameWidth: bookContentAreaWidth,
                                bookContentHeightInsideFrame: bookContentHeightInsideFrame
                            )
                            .frame(
                                width: bookContentAreaWidth,
                                height: bookContentHeightInsideFrame
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height / 2
                        )
                    }
                    
                    // NEW: Regenerate button (only show when storybook exists)
                    if hasRequestedGeneration && !vm.pageItems.isEmpty && !vm.isLoading {
                        VStack(spacing: 12) {
                            Button(action: { showRegenerateConfirmation = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Regenerate Storybook")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(localColors.terracotta)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(localColors.terracotta.opacity(0.15))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(localColors.terracotta.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 5)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(profileVM)
                    .environmentObject(subscriptionManager)
            }
            .sheet(isPresented: $showProfileSetup, onDismiss: {
                generateStorybookWithPaywallCheck()
            }) {
                ProfileSetupView(
                    headshotImage: $headshotImage,
                    name: $grandparentName,
                    race: $userRace,
                    gender: $userGender,
                    onGenerate: { }
                )
                .environmentObject(profileVM)
            }
            .overlay(
                FullScreenImageView(
                    selectedImage: $selectedImageForFullScreen,
                    colors: localColors
                )
            )
            .alert("Download Successful!", isPresented: $showDownloadSuccess) {
                Button("OK") { }
            } message: {
                Text("Your storybook has been saved to your device.")
            }
            .alert("Regenerate Storybook?", isPresented: $showRegenerateConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Regenerate", role: .destructive) {
                    regenerateStorybook()
                }
            } message: {
                Text("This will clear your current storybook and create a new one. This action cannot be undone.")
            }
            .fullScreenCover(isPresented: $showPaywall) {
                GeometryReader { geo in
                    PaywallView(displayCloseButton: true)
                        .frame(maxWidth: .infinity)
                        .ignoresSafeArea()
                        .edgesIgnoringSafeArea(.all)
                }
            }
            .onAppear {
                // Load persisted storybook when view appears
                vm.loadStorybookForProfile(profileVM.selectedProfile.id)
                
                if headshotImage == nil,
                   let test = UIImage(named: "old") {
                    headshotImage = test
                    vm.subjectPhoto = test
                }

                Task { @MainActor in
                    if vm.styleTilePublic == nil,
                       let style = UIImage(named: "kidsref") {
                        vm.styleTile = style
                    }
                }

                Task { await subscriptionManager.refreshCustomerInfo() }
            }
            .onChange(of: profileVM.selectedProfile.id) { newProfileID in
                // Load storybook for new profile, don't reset
                vm.loadStorybookForProfile(newProfileID)
                
                // Update hasRequestedGeneration based on whether we have content
                hasRequestedGeneration = vm.hasGeneratedStorybook
            }
            .onChange(of: vm.progress) { newApiProgress in
                // existing progress-tracking logic
            }
            .onChange(of: vm.isLoading) { isLoading in
                // existing loading-state logic
            }
            .onChange(of: headshotImage) { newShot in
                vm.subjectPhoto = newShot
            }
        }
        .overlay(
            // NEW: Subscription tooltip overlay
            Group {
                if showSubscriptionTooltip {
                    VStack {
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Image Generation Limit")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text("Each subscription includes 50 AI-generated images per billing period. This counter shows how many you have remaining.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(12)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 80) // Position below header
                        
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.easeInOut(duration: 0.3), value: showSubscriptionTooltip)
                }
            }
        )
    }
    
    // NEW: Download functionality
    private func downloadStorybook() {
        isDownloading = true
        
        Task {
            if let pdfURL = vm.downloadStorybook() {
                // Share the PDF
                await MainActor.run {
                    let activityVC = UIActivityViewController(activityItems: [pdfURL], applicationActivities: nil)
                    
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = scene.windows.first,
                       let rootVC = window.rootViewController {
                        
                        // Handle iPad presentation
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = window
                            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                            popover.permittedArrowDirections = []
                        }
                        
                        rootVC.present(activityVC, animated: true)
                    }
                    
                    isDownloading = false
                    showDownloadSuccess = true
                    
                    // Reset success state after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        showDownloadSuccess = false
                    }
                }
            } else {
                await MainActor.run {
                    isDownloading = false
                    // Could show error alert here
                }
            }
        }
    }
    
    // NEW: Regenerate functionality
    private func regenerateStorybook() {
        vm.clearCurrentStorybook()
        hasRequestedGeneration = false
        showSettings = true // Open settings so user can adjust parameters
    }
}

// MARK: - Page View Selection Logic
extension StoryPage {
    @ViewBuilder
    private func pageView(for item: StoryPageViewModel.PageItem, at index: Int, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        let isKidsBook = vm.currentArtStyle == .kidsBook
        
        switch item {
        case .illustration(let image, let caption):
            if isKidsBook {
                // Kids book layout - horizontal/landscape
                KidsBookIllustrationPage(
                    image: image,
                    caption: caption,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight,
                    pageNumber: index + 1
                )
            } else {
                // Vertical book layout (realistic, custom, cartoon) - exactly like reference image
                VerticalBookIllustrationPage(
                    image: image,
                    caption: caption,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight,
                    pageNumber: index + 1,
                    totalPages: vm.pageItems.count
                )
            }
            
        case .textPage(let pageIndex, let total, let text):
            if isKidsBook {
                // Kids book text page - horizontal
                KidsBookTextPage(
                    index: pageIndex,
                    total: total,
                    text: text,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight,
                    pageNumber: index + 1
                )
            } else {
                // Vertical book text page
                VerticalBookTextPage(
                    index: pageIndex,
                    total: total,
                    text: text,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight,
                    pageNumber: index + 1
                )
            }
            
        case .qrCode(_, let url):
            EnhancedQRCodePage(
                url: url,
                frameWidth: frameWidth,
                frameHeight: frameHeight,
                pageNumber: index + 1,
                isKidsBook: isKidsBook
            )
        }
    }
}

// MARK: - Kids Book Style Pages (Landscape/Horizontal) - FIXED FONTS
struct KidsBookIllustrationPage: View {
    let image: UIImage
    let caption: String
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let pageNumber: Int
    
    private let colors = StoryPageLocalColors()
    
    var body: some View {
        ZStack {
            // Clean book page background
            colors.bookPageBackground
            
            // Full page image - clean and simple
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: frameWidth, height: frameHeight)
                .clipped()
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            // Subtle page number at bottom - 1/3 smaller font
            VStack {
                Spacer()
                Text("\(pageNumber)")
                    .font(.kidsBookBodyFont(size: frameHeight * 0.09)) // Using the 1/3 smaller font function
                    .foregroundColor(colors.pageNumberColor.opacity(0.6))
                    .padding(.bottom, frameHeight * 0.02)
            }
        )
    }
}

struct KidsBookTextPage: View {
    let index: Int
    let total: Int
    let text: String
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let pageNumber: Int
    
    private let colors = StoryPageLocalColors()
    
    var body: some View {
        ZStack {
            // Clean book page background
            colors.bookPageBackground
            
            VStack(spacing: frameHeight * 0.04) {
                // Simple, elegant header - 1/3 smaller font
                Text("Memory")
                    .font(.kidsBookTitleFont(size: frameHeight * 0.24)) // Using the 1/3 smaller font function
                    .foregroundColor(colors.chapterTitleColor)
                    .padding(.top, frameHeight * 0.06)
                
                // Text content with elegant typography - 1/3 smaller font
                ScrollView {
                    Text(text)
                        .font(.kidsBookBodyFont(size: frameHeight * 0.15)) // Using the 1/3 smaller font function
                        .lineSpacing(frameHeight * 0.015)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(colors.bookTextColor)
                        .padding(.horizontal, frameWidth * 0.08)
                }
                .frame(maxHeight: frameHeight * 0.75)
                
                Spacer()
                
                // Clean page number - 1/3 smaller font
                Text("\(pageNumber)")
                    .font(.kidsBookBodyFont(size: frameHeight * 0.09)) // Using the 1/3 smaller font function
                    .foregroundColor(colors.pageNumberColor)
                    .padding(.bottom, frameHeight * 0.03)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Vertical Book Style Pages (Realistic/Custom/Cartoon) - Professional and elegant
struct VerticalBookIllustrationPage: View {
    let image: UIImage
    let caption: String
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let pageNumber: Int
    let totalPages: Int
    
    private let colors = StoryPageLocalColors()
    
    var body: some View {
        ZStack {
            // Book page background - exactly like reference
            colors.bookPageBackground
            
            VStack(spacing: 0) {
                // Top section with title and QR code - exactly like reference image
                HStack(alignment: .top) {
                    // Left side - Title section
                    VStack(alignment: .leading, spacing: frameHeight * 0.008) {
                        Text("Memories of Achievement:")
                            .font(.professionalChapterFont(size: frameHeight * 0.025)) // Smaller, more elegant
                            .foregroundColor(colors.chapterTitleColor)
                        
                        Text("A Special Memory")
                            .font(.professionalBodyFont(size: frameHeight * 0.02)) // Professional book size
                            .foregroundColor(colors.bookTextColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                    
                    // Right side - QR code (small, top right)
                    VStack {
                        Image(uiImage: .qrCode(from: "https://memoirai.com", size: frameHeight * 0.06))
                            .interpolation(.none)
                            .resizable()
                            .frame(width: frameHeight * 0.06, height: frameHeight * 0.06)
                    }
                }
                .padding(.horizontal, frameWidth * 0.06)
                .padding(.top, frameHeight * 0.04)
                
                // Main image - positioned exactly like reference
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: frameHeight * 0.45)
                    .padding(.horizontal, frameWidth * 0.06)
                    .padding(.top, frameHeight * 0.02)
                
                // Caption text below image - exactly like reference layout with smaller font
                VStack(alignment: .leading, spacing: frameHeight * 0.01) {
                    Text(caption)
                        .font(.professionalBodyFont(size: frameHeight * 0.018)) // Real book size - small and elegant
                        .lineSpacing(frameHeight * 0.005)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(colors.bookTextColor)
                }
                .padding(.horizontal, frameWidth * 0.06)
                .padding(.top, frameHeight * 0.025)
                
                Spacer()
                
                // Bottom page numbers - exactly like reference with smaller font
                HStack {
                    Text("\(pageNumber)")
                        .font(.professionalBodyFont(size: frameHeight * 0.015)) // Small professional page numbers
                        .foregroundColor(colors.pageNumberColor)
                    
                    Spacer()
                    
                    Text("\(pageNumber + 1)")
                        .font(.professionalBodyFont(size: frameHeight * 0.015))
                        .foregroundColor(colors.pageNumberColor)
                }
                .padding(.horizontal, frameWidth * 0.06)
                .padding(.bottom, frameHeight * 0.03)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colors.bookFrameStroke.opacity(0.3), lineWidth: 0.5)
        )
    }
}

struct VerticalBookTextPage: View {
    let index: Int
    let total: Int
    let text: String
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let pageNumber: Int
    
    private let colors = StoryPageLocalColors()
    
    var body: some View {
        ZStack {
            // Book page background
            colors.bookPageBackground
            
            VStack(spacing: 0) {
                // Header section with professional, smaller font
                VStack(alignment: .leading, spacing: frameHeight * 0.015) {
                    Text("Chapter \(index)")
                        .font(.professionalChapterFont(size: frameHeight * 0.025)) // Smaller, professional
                        .foregroundColor(colors.chapterTitleColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, frameWidth * 0.06)
                .padding(.top, frameHeight * 0.05)
                
                // Text content with real book typography - small and elegant
                ScrollView {
                    VStack(alignment: .leading, spacing: frameHeight * 0.015) {
                        Text(text)
                            .font(.professionalBodyFont(size: frameHeight * 0.018)) // Real book size - small and elegant
                            .lineSpacing(frameHeight * 0.006) // Tight line spacing like real books
                            .multilineTextAlignment(.leading)
                            .foregroundColor(colors.bookTextColor)
                    }
                    .padding(.horizontal, frameWidth * 0.06)
                }
                .frame(maxHeight: frameHeight * 0.8)
                
                Spacer()
                
                // Page number at bottom - small and professional
                Text("\(pageNumber)")
                    .font(.professionalBodyFont(size: frameHeight * 0.015))
                    .foregroundColor(colors.pageNumberColor)
                    .padding(.bottom, frameHeight * 0.03)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colors.bookFrameStroke.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Enhanced QR Code Page
struct EnhancedQRCodePage: View {
    let url: URL
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let pageNumber: Int
    let isKidsBook: Bool
    
    private let colors = StoryPageLocalColors()
    private var qrSide: CGFloat { min(frameWidth, frameHeight) * 0.3 }
    
    var body: some View {
        ZStack {
            colors.bookPageBackground
            
            VStack(spacing: frameHeight * 0.05) {
                // Header with appropriate font for each style - 1/3 smaller for kids book
                Text("Listen to This Memory")
                    .font(isKidsBook ? .kidsBookTitleFont(size: frameHeight * 0.24) : .professionalChapterFont(size: frameHeight * 0.025)) // 1/3 smaller for kids
                    .foregroundColor(colors.chapterTitleColor)
                    .padding(.top, frameHeight * 0.08)
                
                // QR Code with clean styling
                Image(uiImage: .qrCode(from: url.absoluteString, size: qrSide))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: qrSide, height: qrSide)
                    .padding(frameHeight * 0.02)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(colors.decorativeElementColor.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: colors.shadowColor.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Description with appropriate font size - 1/3 smaller for kids book
                VStack(spacing: frameHeight * 0.02) {
                    Text("Scan this code with your phone's camera to hear the original audio recording of this memory.")
                        .font(isKidsBook ? .kidsBookBodyFont(size: frameHeight * 0.12) : .professionalBodyFont(size: frameHeight * 0.018)) // 1/3 smaller for kids
                        .multilineTextAlignment(.center)
                        .foregroundColor(colors.bookTextColor.opacity(0.8))
                        .padding(.horizontal, frameWidth * 0.1)
                }
                
                Spacer()
                
                // Page number with appropriate font - 1/3 smaller for kids book
                Text("\(pageNumber)")
                    .font(isKidsBook ? .kidsBookBodyFont(size: frameHeight * 0.09) : .professionalBodyFont(size: frameHeight * 0.015)) // 1/3 smaller for kids
                    .foregroundColor(colors.pageNumberColor)
                    .padding(.bottom, frameHeight * 0.03)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colors.bookFrameStroke.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Supporting Views
    struct FullScreenImageView: View {
        @Binding var selectedImage: UIImage?
    let colors: StoryPageLocalColors
        
        var body: some View {
            if let image = selectedImage {
                ZStack {
                    colors.fullScreenOverlayBackground
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedImage = nil
                            }
                        }
                    
                    VStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(16)
                            .padding(30)
                            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedImage = nil
                            }
                        }) {
                            Text("Close")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.9))
                            .foregroundColor(colors.terracotta)
                                .cornerRadius(12)
                                .shadow(radius: 3)
                        }
                        .padding(.bottom, 40)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeInOut(duration: 0.3), value: selectedImage != nil)
            }
        }
    }
    
    // MARK: - Preview
    struct StoryPage_Previews: PreviewProvider {
        static var previews: some View {
            let dummyProfileVM = ProfileViewModel()
            StoryPage()
                .environmentObject(dummyProfileVM)
    }
}
