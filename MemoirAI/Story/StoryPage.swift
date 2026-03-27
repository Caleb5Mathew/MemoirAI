import SwiftUI
import PhotosUI
import Combine
import RevenueCat
import RevenueCatUI
import CoreData

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

// MARK: - Book Font Style Per Art Style
enum BookFontStyle {
    case kidsBook    // Professional serif fonts
    case comic       // Bold serif fonts
    case realistic   // Elegant serif fonts
    case custom      // Clean serif fonts
    
    init(artStyle: ArtStyle) {
        switch artStyle {
        case .kidsBook: self = .kidsBook
        case .comic: self = .comic
        case .realistic: self = .realistic
        case .custom: self = .custom
        }
    }
    
    // Title font at ~3.5% of frame height for proper book typography
    func titleFont(for frameHeight: CGFloat) -> Font {
        let size = frameHeight * 0.035  // ~28pt at 792pt, ~21pt at 612pt
        switch self {
        case .kidsBook:  return .custom("TimesNewRomanPS-BoldMT", size: 18) ?? .system(size: 18, weight: .bold, design: .serif)
        case .comic:     return .system(size: size, weight: .heavy, design: .serif)
        case .realistic: return .custom("Georgia-Bold", size: size) ?? .system(size: size, weight: .bold, design: .serif)
        case .custom:    return .system(size: size, weight: .semibold, design: .serif)
        }
    }
    
    // Body font at ~2.0% of frame height for proper book typography
    func bodyFont(for frameHeight: CGFloat) -> Font {
        let size = frameHeight * 0.020  // ~16pt at 792pt, ~12pt at 612pt
        switch self {
        case .kidsBook:  return .custom("TimesNewRomanPSMT", size: 12) ?? .system(size: 12, weight: .regular, design: .serif)
        case .comic:     return .system(size: size, weight: .semibold, design: .serif)
        case .realistic: return .custom("Georgia", size: size) ?? .system(size: size, weight: .regular, design: .serif)
        case .custom:    return .system(size: size, weight: .regular, design: .serif)
        }
    }
    
    // Page number font at ~1.5% of frame height
    func pageNumberFont(for frameHeight: CGFloat) -> Font {
        let size = frameHeight * 0.015  // ~12pt at 792pt, ~9pt at 612pt
        switch self {
        case .kidsBook:  return .custom("TimesNewRomanPSMT", size: 10) ?? .system(size: 10, weight: .regular, design: .serif)
        case .comic:     return .system(size: size, weight: .regular, design: .serif)
        case .realistic: return .custom("Georgia", size: size) ?? .system(size: size, weight: .regular, design: .serif)
        case .custom:    return .system(size: size, weight: .regular, design: .serif)
        }
    }
}

// MARK: - QR Watermark Component
/// QR code overlay for illustration pages. Use `topInset` to keep it below the Kids book title bar.
struct QRWatermark: View {
    let memoryID: UUID
    /// When non-zero (e.g. Kids book bar height), QR sits below this so it doesn't overlap the top bar.
    var topInset: CGFloat = 0
    private let qrSide: CGFloat = 60
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: topInset)
            HStack {
                Spacer()
                // Frosted background for visibility on any image (black, white, etc.)
                Image(uiImage: StoryPageViewModel.qrCode(
                    from: "memoirai://memory/\(memoryID.uuidString)",
                    size: qrSide
                ))
                .interpolation(.none)
                .resizable()
                .frame(width: qrSide, height: qrSide)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.trailing, 12)
            .padding(.top, 8)
            Spacer()
        }
    }
}

// Enhanced font system with distinct styles
extension Font {
    static func storyPageSerifFont(size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }
    
    // Kids book fonts - Times New Roman 12pt for publisher standard (11×8.5" print)
    static func kidsBookTitleFont(for frameHeight: CGFloat) -> Font {
        return .custom("TimesNewRomanPS-BoldMT", size: 18) ?? .system(size: 18, weight: .bold, design: .serif)
    }
    
    static func kidsBookBodyFont(for frameHeight: CGFloat) -> Font {
        return .custom("TimesNewRomanPSMT", size: 12) ?? .system(size: 12, weight: .regular, design: .serif)
    }
    
    static func kidsBookPageNumberFont(for frameHeight: CGFloat) -> Font {
        return .custom("TimesNewRomanPSMT", size: 10) ?? .system(size: 10, weight: .regular, design: .serif)
    }
    
    // Professional vertical book fonts - elegant serif fonts
    static func professionalTitleFont(for frameHeight: CGFloat) -> Font {
        let size = frameHeight * 0.035
        return .custom("Georgia-Bold", size: size) ?? .system(size: size, weight: .bold, design: .serif)
    }
    
    static func professionalBodyFont(for frameHeight: CGFloat) -> Font {
        let size = frameHeight * 0.020
        return .custom("Georgia", size: size) ?? .system(size: size, weight: .regular, design: .serif)
    }
    
    static func professionalChapterFont(for frameHeight: CGFloat) -> Font {
        let size = frameHeight * 0.025
        return .custom("Georgia-Bold", size: size) ?? .system(size: size, weight: .semibold, design: .serif)
    }
    
    static func professionalPageNumberFont(for frameHeight: CGFloat) -> Font {
        let size = frameHeight * 0.015
        return .custom("Georgia", size: size) ?? .system(size: size, weight: .regular, design: .serif)
    }
}

// Main StoryPage implementation
struct StoryPage: View {
    @State private var userGender: String = ""
    @State private var headshotImage: UIImage?
    @State private var grandparentName: String = ""
    @State private var showProfileSetup: Bool = false
    @State private var didCompleteProfileSetup: Bool = false // Track if user completed setup or just exited
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
    @State private var showGallery = false
    @State private var selectedImageForFullScreen: UIImage? = nil
    @State private var hasRequestedGeneration = false
    @State private var showPageDetail = false
    @State private var detailPageIndex = 0
    
    // Progress simulation
    @State private var fakeProgress: Double = 0
    @State private var realProgress: Double = 0
    @State private var cancellableTimer: AnyCancellable?
    
    // NEW: Download and regenerate functionality
    @State private var showDownloadSuccess = false
    @State private var showRegenerateConfirmation = false
    @State private var isDownloading = false
    
    // Track actual preview dimensions for accurate PDF generation
    @State private var actualPreviewWidth: CGFloat = 0
    @State private var actualPreviewHeight: CGFloat = 0
    
    // NEW: Paywall state - exactly like MemoirView
    @State private var showPaywall = false
    
    // NEW: Tooltip state for subscription status
    @State private var showSubscriptionTooltip = false
    
    // Incomplete memories banner
    @State private var incompleteCount: Int = 0
    @State private var navigateToRecent: Bool = false
    @State private var showIncompleteMemoriesAlert: Bool = false
    
    // Image editing state
    @State private var showImageEditSheet: Bool = false
    @State private var editingImageIndex: Int? = nil
    @State private var editRevisionText: String = ""

    // Order book sheet
    @State private var orderBookRecordForSheet: BookVersionRecord?
    @State private var isOrderPreparing = false
    @State private var orderNotReadyAlert = false
    
    @Environment(\.managedObjectContext) private var context
    
    // ETA tracking
    @State private var totalEstimatedSeconds: Int = 0
    @State private var generationStart: Date? = nil
    @State private var etaTick: Int = 0
    @State private var etaTimer: AnyCancellable?
    
    private var displayProgress: Double {
        if realProgress > 0.05 && realProgress > fakeProgress {
            return realProgress
        }
        return max(fakeProgress, realProgress)
    }
    
    // Human-readable remaining time string with dynamic adjustment
    private var etaString: String {
        guard vm.isLoading, let start = generationStart else { return "" }
        let elapsed = Int(Date().timeIntervalSince(start))
        
        // If we have real progress > 10%, calculate ETA based on actual speed
        if realProgress > 0.1 {
            let estimatedTotal = Int(Double(elapsed) / realProgress)
            let remaining = max(0, estimatedTotal - elapsed)
            let mins = remaining / 60
            let secs = remaining % 60
            return "About \(mins)m \(secs)s remaining"
        } else {
            // Use initial estimate
            let remaining = max(0, totalEstimatedSeconds - elapsed)
            let mins = remaining / 60
            let secs = remaining % 60
            return "Estimated time: \(mins)m \(secs)s remaining"
        }
    }
    
    // NEW: Subscription check - exactly like MemoirView
    private var isSubscribed: Bool {
        subscriptionManager.activeTier != nil
    }
    
    // MARK: - Incomplete Memories Banner Component
    @ViewBuilder
    private func incompleteMemoriesBanner() -> some View {
        if incompleteCount > 0 {
            HStack(spacing: 8) { // Reduced spacing
                // Subtle icon badge
                HStack(spacing: 4) { // Reduced spacing
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(localColors.terracotta)
                    
                    Text("\(incompleteCount)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(localColors.terracotta)
                }
                .padding(.horizontal, 8) // Reduced padding
                .padding(.vertical, 6)
                .background(localColors.terracotta.opacity(0.1))
                .cornerRadius(8)
                .fixedSize()
                
                // Clean text - Allow full flexibility
                Text("\(incompleteCount == 1 ? "memory" : "memories") can be enhanced")
                    .font(.system(size: 13))
                    .foregroundColor(localColors.defaultGray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7) // Allow more shrinking if needed
                    .layoutPriority(1) // Prioritize text width
                
                Spacer(minLength: 0)
                
                // Subtle action button
                Button(action: { navigateToRecent = true }) {
                    Text("Enhance")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(localColors.terracotta)
                        .padding(.horizontal, 10) // Reduced padding
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .stroke(localColors.terracotta.opacity(0.3), lineWidth: 1)
                                .background(Capsule().fill(localColors.terracotta.opacity(0.05)))
                        )
                }
                .fixedSize()
            }
            .padding(.horizontal, 12) // Reduced outer padding
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(localColors.terracotta.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }
    
    @ViewBuilder
    private func storybookContentView(
        bookFrameWidth: CGFloat,
        bookContentHeightInsideFrame: CGFloat
    ) -> some View {
        if vm.isLoading {
            makeLoadingView()
        } else if let error = vm.errorMessage {
            makeErrorView(error: error)
        } else if hasRequestedGeneration && !vm.pageItems.isEmpty {
            makeBookContent(bookFrameWidth: bookFrameWidth, bookContentHeightInsideFrame: bookContentHeightInsideFrame)
        } else {
            makeEmptyStateView()
        }
    }
    
    @ViewBuilder
    private func makeLoadingView() -> some View {
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
            
            // Show current status and memory being processed
            if !vm.currentStatus.isEmpty {
                Text(vm.currentStatus)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(localColors.terracotta)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            if !etaString.isEmpty {
                Text(etaString)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Text("Please keep the app open while we generate your storybook.")
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.8))
        }
    }
    
    @ViewBuilder
    private func makeErrorView(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: error.contains("Maximum images reached") || error.contains("Not enough images") ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(error.contains("Maximum images reached") || error.contains("Not enough images") ? .orange : localColors.defaultRed.opacity(0.7))
            
            Text(error)
                .font(.storyPageSerifFont(size: 16))
                .multilineTextAlignment(.center)
                .foregroundColor(error.contains("Maximum images reached") || error.contains("Not enough images") ? .orange : localColors.defaultRed)
                .padding(.horizontal, 5)
                .fixedSize(horizontal: false, vertical: true)
            
            if error.contains("Maximum images reached") || error.contains("Not enough images") {
                // Show subscription status
                VStack(spacing: 8) {
                    Text("Images remaining: \(subscriptionManager.remainingAllowance)/100")
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
    }
    
    @ViewBuilder
    private func makeBookContent(bookFrameWidth: CGFloat, bookContentHeightInsideFrame: CGFloat) -> some View {
        let bookAspectRatio = vm.currentPrintSpec.aspectRatio
        let contentWidth = bookFrameWidth * 0.9
        let contentHeight = contentWidth / bookAspectRatio
        
        ZStack {
            makeTabViewContent(
                bookFrameWidth: bookFrameWidth,
                bookAspectRatio: bookAspectRatio,
                contentWidth: contentWidth,
                contentHeight: contentHeight,
                printSpec: vm.currentPrintSpec
            )
            
            makeLoadingOverlays(
                contentWidth: contentWidth,
                contentHeight: contentHeight
            )
            
            makeNavigationButtons(bookFrameWidth: bookFrameWidth)
        }
        .onAppear {
            // Capture actual preview dimensions for PDF generation
            actualPreviewWidth = contentWidth
            actualPreviewHeight = contentHeight
        }
        .frame(width: contentWidth, height: contentHeight)
    }
    
    @ViewBuilder
    private func makeTabViewContent(
        bookFrameWidth: CGFloat,
        bookAspectRatio: CGFloat,
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        printSpec: BookPrintSpec
    ) -> some View {
        TabView(selection: $currentPageIndex) {
            ForEach(vm.pageItems.indices, id: \.self) { idx in
                let renderScale = min(
                    contentWidth / max(printSpec.widthPt, 1),
                    contentHeight / max(printSpec.heightPt, 1)
                )
                pageView(
                    for: vm.pageItems[idx],
                    at: idx,
                    frameWidth: printSpec.widthPt,
                    frameHeight: printSpec.heightPt
                )
                .frame(width: printSpec.widthPt, height: printSpec.heightPt)
                .scaleEffect(renderScale, anchor: .center)
                .frame(width: contentWidth, height: contentHeight)
                .tag(idx)
                .onTapGesture {
                    detailPageIndex = idx
                    showPageDetail = true
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: contentWidth, height: contentHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private func handleImageTap(at idx: Int) {
        if case .illustration = vm.pageItems[idx] {
            // Check if this image is being edited
            if vm.isEditingImage(at: idx) {
                // Don't open edit sheet if already editing
                return
            }
            // Open edit sheet
            editingImageIndex = idx
            showImageEditSheet = true
        }
    }
    
    @ViewBuilder
    private func makeLoadingOverlays(contentWidth: CGFloat, contentHeight: CGFloat) -> some View {
        ForEach(vm.pageItems.indices, id: \.self) { idx in
            if vm.isEditingImage(at: idx) && currentPageIndex == idx {
                makeLoadingOverlay()
                    .transition(.opacity)
            }
        }
    }
    
    @ViewBuilder
    private func makeLoadingOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: localColors.terracotta))
                    .scaleEffect(1.2)
                
                Text("Updating image...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(localColors.defaultBlack)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: localColors.shadowColor, radius: 8, x: 0, y: 4)
            )
        }
    }
    
    @ViewBuilder
    private func makeNavigationButtons(bookFrameWidth: CGFloat) -> some View {
        if vm.pageItems.count > 1 {
            HStack {
                makePreviousButton()
                Spacer()
                makeNextButton()
            }
            .font(.system(size: 40, weight: .thin))
            .foregroundColor(localColors.arrowColor)
            .padding(.horizontal, bookFrameWidth * 0.02)
            .frame(width: bookFrameWidth * 0.95)
        }
    }
    
    @ViewBuilder
    private func makePreviousButton() -> some View {
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
    }
    
    @ViewBuilder
    private func makeNextButton() -> some View {
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
    
    @ViewBuilder
    private func makeEmptyStateView() -> some View {
        VStack(spacing: 0) {
            // Flexible space to center the content
            Spacer()
            
            // Main centered content
            VStack(spacing: 16) {
                // Banner sits directly above the text
                if incompleteCount > 0 {
                    incompleteMemoriesBanner()
                        .padding(.bottom, 4) // Slight spacing between banner and title
                }
                
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
                .accessibilityIdentifier("createStorybookButton")
                .disabled(vm.isLoading)
            }
            
            // Flexible space to center the content
            Spacer()
        }
        .padding()
    }

    private func resetGenerationState() {
        // Don't clear vm.pageItems or vm.images - let persistence handle this
        vm.errorMessage = nil
        currentPageIndex = 0
        fakeProgress = 0
        realProgress = 0
        vm.progress = 0
        cancellableTimer?.cancel()
        etaTimer?.cancel()
        vm.isLoading = false
        // Don't reset hasRequestedGeneration - let it persist
    }
        
    private func generateStorybookWithPaywallCheck() {
        var pagesToAttempt = vm.expectedPageCount()
        
        // Debug: Print current free preview status
        FreePreviewConfig.printStatus()

        // ─────────────────────────────────────────────────────────────
        // FREE PREVIEW LOGIC – non-subscribers get limited free images (tracked via iCloud KV store)
        if !isSubscribed {
            let remaining = FreePreviewConfig.freeImagesRemaining
            
            // 1️⃣ No free images left → block generation entirely
            if !FreePreviewConfig.canGenerateFreePreview {
                vm.errorMessage = "You have already used your free preview. Subscribe to unlock unlimited storybooks."
                vm.isLoading = false
                hasRequestedGeneration = false
                return
            }
            
            // 2️⃣ Limit to remaining free images (e.g., if they have 2 left, only allow 2)
            // Always generate just 1 at a time for free users to track accurately
            pagesToAttempt = 1
            print("StoryPage: Free user - using 1 image (remaining: \(remaining)/\(FreePreviewConfig.maxPagesWithoutSubscription))")
        }

        guard pagesToAttempt > 0 else {
            vm.errorMessage = "Please select at least 1 memory to generate."
            return
        }
        
        // If subscribed, block when allowance insufficient
        if isSubscribed && pagesToAttempt > subscriptionManager.remainingAllowance {
            vm.isLoading = false
            hasRequestedGeneration = false
            let renewalDate = subscriptionManager.getRenewalDateString()
            vm.errorMessage = "You need \(pagesToAttempt) images but only have \(subscriptionManager.remainingAllowance) remaining. Your allowance resets on \(renewalDate)."
            return
        }
        
        // ✨ Warn about large generations but still allow them
        if subscriptionManager.isLargeGeneration(pages: pagesToAttempt) {
            print("⚠️ StoryPage: Large generation requested (\(pagesToAttempt) images). User was warned in settings.")
        }
        
        print("StoryPage: Generation approved. Proceeding with \(pagesToAttempt) memories.")
        startActualGenerationProcess(pagesExpected: pagesToAttempt)
    }
        
    private func startActualGenerationProcess(pagesExpected: Int) {
        resetGenerationState()
        hasRequestedGeneration = true
        vm.isLoading = true
        
        // Estimate – Nano Banana (Gemini) is faster than DALL-E
        // Estimate ~8s per image for Nano Banana, ~15s for LLM processing per memory
        // Total: ~23s per memory (includes scene extraction, title/character extraction, and image generation)
        totalEstimatedSeconds = pagesExpected * 23
        generationStart = Date()
        etaTimer?.cancel()
        etaTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in etaTick += 1 } // ticks every second to refresh UI
        
        // Fake progress provides immediate feedback while real progress loads
        // Set to 15% to show activity without over-promising
        let fakeIncrementPerTick = 0.0025
        let targetFakeProgress = 0.15
        
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
        let finalPageCount = pagesExpected // Pass the adjusted page count
        let wasSubscribed = isSubscribed // Capture subscription state before async
        
        Task {
            await vm.generateStorybook(
                forProfileID: currentProfileID,
                profileName: profileVM.selectedProfile.name,
                overridePageCount: finalPageCount
            )
            
            await MainActor.run {
                cancellableTimer?.cancel()
                
                if vm.errorMessage == nil && !vm.images.isEmpty {
                    let actualImagesGenerated = vm.images.count
                    if actualImagesGenerated > 0 {
                        if wasSubscribed {
                            // Subscribed users: deduct from monthly allowance
                            subscriptionManager.consume(pages: actualImagesGenerated)
                            print("StoryPage: Consumed \(actualImagesGenerated) images from subscription.")
                        } else {
                            // Free users: increment free preview counter (stored in iCloud + UserDefaults)
                            FreePreviewConfig.incrementFreeImagesUsed(by: actualImagesGenerated)
                            print("StoryPage: Consumed \(actualImagesGenerated) free preview image(s). Remaining: \(FreePreviewConfig.freeImagesRemaining)")
                        }
                    }
                    self.realProgress = 1.0
                    self.fakeProgress = 1.0
                    etaTimer?.cancel()
                } else {
                    print("StoryPage: Gen failed/no images. Error: \(vm.errorMessage ?? "N/A").")
                    self.realProgress = 0.0
                    self.fakeProgress = 0.0
                    etaTimer?.cancel()
                    // Note: We don't consume free preview images on failure
                }
                if vm.isLoading { print("Warning: vm.isLoading is still true post-generation.")}
            }
        }
    }

    var body: some View {
        let mainContent = makeMainContent()
        
        return NavigationStack {
            mainContent
                .navigationBarHidden(true)
        }
        .addAllSheetsAndModifiers(
            showSettings: $showSettings,
            showProfileSetup: $showProfileSetup,
            showGallery: $showGallery,
            showImageEditSheet: $showImageEditSheet,
            showPaywall: $showPaywall,
            showDownloadSuccess: $showDownloadSuccess,
            showRegenerateConfirmation: $showRegenerateConfirmation,
            showIncompleteMemoriesAlert: $showIncompleteMemoriesAlert,
            navigateToRecent: $navigateToRecent,
            editingImageIndex: $editingImageIndex,
            editRevisionText: $editRevisionText,
            selectedImageForFullScreen: $selectedImageForFullScreen,
            incompleteCount: incompleteCount,
            didCompleteProfileSetup: $didCompleteProfileSetup,
            headshotImage: $headshotImage,
            grandparentName: $grandparentName,
            userRace: $userRace,
            userGender: $userGender,
            profileVM: profileVM,
            subscriptionManager: subscriptionManager,
            vm: vm,
            localColors: localColors,
            generateStorybookWithPaywallCheck: generateStorybookWithPaywallCheck,
            regenerateStorybook: regenerateStorybook,
            updateIncompleteCount: updateIncompleteCount,
            hasRequestedGeneration: $hasRequestedGeneration,
            showSubscriptionTooltip: $showSubscriptionTooltip,
            actualPreviewWidth: $actualPreviewWidth,
            actualPreviewHeight: $actualPreviewHeight,
            realProgress: $realProgress,
            showPageDetail: $showPageDetail,
            detailPageIndex: $detailPageIndex
        )
        .sheet(item: $orderBookRecordForSheet) { record in
            OrderBookView(book: record)
        }
        .alert("Book PDF Still Preparing", isPresented: $orderNotReadyAlert) {
            Button("Retry") {
                orderBookTapped()
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your book PDF is still being generated — this usually takes 1–2 minutes after your storybook is created. Tap Retry to check again.")
        }
    }
    
    @ViewBuilder
    private func makeMainContent() -> some View {
        ZStack {
            localColors.softCream
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                makeHeader()
                makeStorybookContentArea()
                makeOrderBookButton()
                makeRegenerateButton()
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 5)
            }
        }
    }
    
    @ViewBuilder
    private func makeHeader() -> some View {
        HStack {
            makeBackButton()
            Spacer()
            makeTitleSection()
            Spacer()
            makeHeaderButtons()
        }
        .padding(.horizontal)
        .padding(.top, 5)
        .padding(.bottom, 10)
    }
    
    @ViewBuilder
    private func makeBackButton() -> some View {
        Button(action: { dismiss() }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(localColors.defaultBlack.opacity(0.7))
                .padding(10)
                .background(localColors.subtleControlBackground)
                .clipShape(Circle())
        }
    }
    
    @ViewBuilder
    private func makeTitleSection() -> some View {
        VStack(spacing: 2) {
            Text("Your Storybook")
                .font(.storyPageSerifFont(size: 22))
                .fontWeight(.medium)
                .foregroundColor(localColors.defaultBlack.opacity(0.8))
            
            if subscriptionManager.hasActiveSubscription {
                makeSubscriptionButton()
            }
        }
    }
    
    @ViewBuilder
    private func makeSubscriptionButton() -> some View {
        Button(action: {
            showSubscriptionTooltip = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                showSubscriptionTooltip = false
            }
        }) {
            Text("\(subscriptionManager.remainingAllowance)/100 images")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(subscriptionManager.remainingAllowance <= 5 ? .red : .gray)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private func makeHeaderButtons() -> some View {
        HStack(spacing: 12) {
            makeGalleryButton()
            if hasRequestedGeneration && !vm.pageItems.isEmpty {
                makeDownloadButton()
            }
            makeSettingsButton()
        }
    }
    
    @ViewBuilder
    private func makeGalleryButton() -> some View {
        Button { showGallery = true } label: {
            Image(systemName: "books.vertical")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(localColors.defaultBlack.opacity(0.7))
                .padding(10)
                .background(localColors.subtleControlBackground)
                .clipShape(Circle())
        }
    }
    
    @ViewBuilder
    private func makeDownloadButton() -> some View {
        Button(action: downloadStorybook) {
            HStack(spacing: 4) {
                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: localColors.defaultBlack.opacity(0.7)))
                } else {
                    Image(systemName: showDownloadSuccess ? "checkmark.circle.fill" : "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                }
            }
            .foregroundColor(showDownloadSuccess ? .green : localColors.defaultBlack.opacity(0.7))
            .padding(10)
            .background(localColors.subtleControlBackground)
            .clipShape(Circle())
        }
        .accessibilityIdentifier("downloadStorybookButton")
        .disabled(isDownloading)
        .scaleEffect(showDownloadSuccess ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showDownloadSuccess)
    }
    
    @ViewBuilder
    private func makeSettingsButton() -> some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(localColors.defaultBlack.opacity(0.7))
                .padding(10)
                .background(localColors.subtleControlBackground)
                .clipShape(Circle())
        }
        .accessibilityIdentifier("storybookSettingsButton")
    }
    
    @ViewBuilder
    private func makeStorybookContentArea() -> some View {
        GeometryReader { geo in
            makeBookFrame(geo: geo)
        }
    }
    
    @ViewBuilder
    private func makeBookFrame(geo: GeometryProxy) -> some View {
        let printSpec = vm.currentPrintSpec
        let exportAspectRatio = printSpec.aspectRatio
        
        // Scale to fit screen while maintaining exact export aspect ratio
        let maxWidth = geo.size.width * 0.92
        let maxHeight = geo.size.height * 0.75
        let scaledWidth = min(maxWidth, maxHeight * exportAspectRatio)
        let scaledHeight = scaledWidth / exportAspectRatio
        
        // Use scaled dimensions for display (matches export aspect ratio exactly)
        let bookFrameWidth = scaledWidth
        let bookContentAreaWidth = scaledWidth * 0.92
        let bookContentHeightInsideFrame = scaledHeight * 0.92
        let verticalPad: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 30 : 20
        let bookFrameHeight = bookContentHeightInsideFrame + (verticalPad * 2)
        let bookFrameX = geo.size.width / 2
        let bookFrameY = geo.size.height / 2
        let bookFrameTop = bookFrameY - (bookFrameHeight / 2)
        
        ZStack {
            makeBookPreviewBox(
                bookFrameWidth: bookFrameWidth,
                bookFrameHeight: bookFrameHeight,
                bookContentAreaWidth: bookContentAreaWidth,
                bookContentHeightInsideFrame: bookContentHeightInsideFrame,
                bookFrameX: bookFrameX,
                bookFrameY: bookFrameY
            )
        }
    }
    
    @ViewBuilder
    private func makeBookPreviewBox(
        bookFrameWidth: CGFloat,
        bookFrameHeight: CGFloat,
        bookContentAreaWidth: CGFloat,
        bookContentHeightInsideFrame: CGFloat,
        bookFrameX: CGFloat,
        bookFrameY: CGFloat
    ) -> some View {
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
            .onAppear {
                actualPreviewWidth = bookContentAreaWidth
                actualPreviewHeight = bookContentHeightInsideFrame
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .position(x: bookFrameX, y: bookFrameY)
    }
    
    // REMOVED: Yellow hazard warning icon during/after generation
    // The enhancement banner at the top (before generation) is sufficient
    @ViewBuilder
    private func makeIncompleteMemoriesButton(
        bookFrameWidth: CGFloat,
        bookFrameX: CGFloat,
        bookFrameTop: CGFloat
    ) -> some View {
        EmptyView()
    }
    
    @ViewBuilder
    private func makeOrderBookButton() -> some View {
        if hasRequestedGeneration && !vm.pageItems.isEmpty {
            VStack(spacing: 8) {
                Button(action: orderBookTapped) {
                    HStack(spacing: 10) {
                        if isOrderPreparing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text(vm.isBookOrderable ? "Order Printed Copy" : "Preparing for print...")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.white)
                    .background(localColors.terracotta)
                    .clipShape(Capsule())
                }
                .disabled(isOrderPreparing || !vm.isBookOrderable)
                .padding(.horizontal, 24)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
    }

    private func orderBookTapped() {
        guard !isOrderPreparing else { return }
        isOrderPreparing = true
        Task {
            _ = await vm.fetchCurrentBookVersionRecord()
            await MainActor.run {
                isOrderPreparing = false
                if vm.isBookOrderable, let record = vm.currentBookVersionRecord {
                    orderBookRecordForSheet = record
                } else {
                    orderNotReadyAlert = true
                }
            }
        }
    }

    @ViewBuilder
    private func makeRegenerateButton() -> some View {
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
    
    // NEW: Download functionality
    private func downloadStorybook() {
        isDownloading = true
        
        Task {
            let report = vm.makePrintParityReport(
                previewWidth: actualPreviewWidth > 0 ? actualPreviewWidth : vm.currentPrintSpec.widthPt,
                previewHeight: actualPreviewHeight > 0 ? actualPreviewHeight : vm.currentPrintSpec.heightPt
            )
            for note in report.notes {
                print("🧪 Print parity check: \(note)")
            }
            
            // Pass actual preview dimensions for pixel-perfect PDF
            guard let pdfURL = vm.downloadStorybook(
                previewWidth: actualPreviewWidth > 0 ? actualPreviewWidth : nil,
                previewHeight: actualPreviewHeight > 0 ? actualPreviewHeight : nil
            ) else {
                await MainActor.run { isDownloading = false }
                return
            }

            await MainActor.run {
                let activityVC = UIActivityViewController(activityItems: [pdfURL], applicationActivities: nil)

                activityVC.completionWithItemsHandler = { _, completed, _, _ in
                    self.isDownloading = false
                    if completed {
                        self.showDownloadSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.showDownloadSuccess = false
                        }
                    }
                }

                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = scene.windows.first,
                   let rootVC = window.rootViewController {
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = window
                        popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    rootVC.present(activityVC, animated: true)
                } else {
                    self.isDownloading = false
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
    
    // MARK: – Helper to count memories needing enhancement
    private func updateIncompleteCount() {
        // Refresh context to ensure we have latest data
        context.refreshAllObjects()
        
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = MemoryUserScope.profilePredicate(profileID: profileVM.selectedProfile.id)
        if let all = try? context.fetch(request) {
            // Check for any memories that have text but don't have character details
            // This is simpler than isIncomplete which requires character keywords
            let unenhanced = all.filter { memory in
                // Must have text content (at least 5 chars to be meaningful)
                guard let text = memory.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count > 5 else {
                    return false
                }
                
                // Check if character details exist (in Core Data or UserDefaults)
                if let detailsString = memory.value(forKey: "characterDetails") as? String, !detailsString.isEmpty {
                    // Try to parse - if it has characters, it's enhanced
                    if let data = detailsString.data(using: .utf8),
                       let details = try? JSONDecoder().decode(CharacterDetails.self, from: data),
                       !details.characters.isEmpty {
                        return false // Has details, so it's enhanced
                    }
                }
                
                // Check UserDefaults backup
                if let memoryId = memory.id?.uuidString,
                   let backupString = UserDefaults.standard.string(forKey: "characterDetails_\(memoryId)"),
                   !backupString.isEmpty,
                   let data = backupString.data(using: .utf8),
                   let details = try? JSONDecoder().decode(CharacterDetails.self, from: data),
                   !details.characters.isEmpty {
                    return false // Has details, so it's enhanced
                }
                
                // No character details found - memory is unenhanced
                return true
            }
            
            incompleteCount = unenhanced.count
            
            // Debug logging
            print("🔍 StoryPage: Found \(all.count) total memories")
            print("🔍 StoryPage: Found \(incompleteCount) unenhanced memories")
            for mem in unenhanced.prefix(5) {
                print("  - Unenhanced: \(mem.prompt ?? "No prompt") | Text: \(mem.text?.prefix(50) ?? "none")...")
            }
        } else {
            print("❌ StoryPage: Failed to fetch memories")
            incompleteCount = 0
        }
    }
}

// MARK: - Page View Selection Logic
extension StoryPage {
    @ViewBuilder
    private func pageView(for item: StoryPageViewModel.PageItem, at index: Int, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        let isKidsBook = vm.currentArtStyle == .kidsBook
        
        switch item {
        case .illustration(let image, let memoryID, let title):
            makeIllustrationPage(
                image: image,
                memoryID: memoryID,
                title: title,
                index: index,
                frameWidth: frameWidth,
                frameHeight: frameHeight,
                isKidsBook: isKidsBook
            )
            
        case .textPage(let pageIndex, let total, let text, let title, let subtitle, let memoryID):
            makeTextPage(
                pageIndex: pageIndex,
                total: total,
                text: text,
                title: title,
                subtitle: subtitle,
                memoryID: memoryID,
                index: index,
                frameWidth: frameWidth,
                frameHeight: frameHeight,
                isKidsBook: isKidsBook
            )
        }
    }
    
    @ViewBuilder
    private func makeIllustrationPage(image: UIImage, memoryID: UUID, title: String?, index: Int, frameWidth: CGFloat, frameHeight: CGFloat, isKidsBook: Bool) -> some View {
        let isEditing = vm.isEditingImage(at: index)
        
        Group {
            if isKidsBook {
                KidsBookIllustrationPage(
                    image: image,
                    memoryID: memoryID,
                    title: title,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight,
                    pageNumber: index + 1
                )
            } else {
                VerticalBookIllustrationPage(
                    image: image,
                    memoryID: memoryID,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight,
                    pageNumber: index + 1,
                    totalPages: vm.pageItems.count
                )
            }
        }
        .overlay(
            // QR Watermark — on Kids book, inset below title bar so it sits on the picture only
            QRWatermark(
                memoryID: memoryID,
                topInset: isKidsBook ? frameHeight * 0.065 + 6 : 0
            )
        )
        .overlay(
            // Loading indicator overlay when editing
            Group {
                if isEditing {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            
                            Text("Updating image...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.7))
                        )
                    }
                }
            }
        )
    }
    
    @ViewBuilder
    private func makeTextPage(pageIndex: Int, total: Int, text: String, title: String?, subtitle: String?, memoryID: UUID, index: Int, frameWidth: CGFloat, frameHeight: CGFloat, isKidsBook: Bool) -> some View {
        let fontStyle = BookFontStyle(artStyle: vm.currentArtStyle)
        
        Group {
            if isKidsBook {
                KidsBookTextPage(
                    index: pageIndex,
                    total: total,
                    text: text,
                    title: title,
                    subtitle: subtitle,
                    memoryID: memoryID,
                    fontStyle: fontStyle,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight,
                    pageNumber: index + 1
                )
            } else {
                VerticalBookTextPage(
                    index: pageIndex,
                    total: total,
                    text: text,
                    title: title,
                    subtitle: subtitle,
                    memoryID: memoryID,
                    fontStyle: fontStyle,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight,
                    pageNumber: index + 1
                )
            }
        }
        .overlay(
            // QR Watermark
            QRWatermark(memoryID: memoryID)
        )
    }
}

// MARK: - Kids Book Style Pages (Landscape/Horizontal) - FIXED FONTS
struct KidsBookIllustrationPage: View {
    let image: UIImage
    let memoryID: UUID
    let title: String?
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let pageNumber: Int
    
    private let colors = StoryPageLocalColors()
    private var barHeight: CGFloat { frameHeight * 0.065 }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar: memory title left, page number right
            HStack {
                Text(title ?? "Memory")
                    .font(.kidsBookTitleFont(for: frameHeight))
                    .foregroundColor(colors.chapterTitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("\(pageNumber)")
                    .font(.kidsBookPageNumberFont(for: frameHeight))
                    .foregroundColor(colors.pageNumberColor)
            }
            .padding(.horizontal, frameWidth * 0.08)
            .frame(height: barHeight)
            .frame(maxWidth: .infinity)
            .background(colors.bookPageBackground)
            
            // Full page illustration
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: frameWidth, height: frameHeight - barHeight)
                .clipped()
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct KidsBookTextPage: View {
    let index: Int
    let total: Int
    let text: String
    let title: String?
    let subtitle: String?
    let memoryID: UUID
    let fontStyle: BookFontStyle
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let pageNumber: Int
    
    private let colors = StoryPageLocalColors()
    private var barHeight: CGFloat { frameHeight * 0.07 }
    // Book-like margins for 11×8.5" print: ~0.5" top/bottom, ~0.75" sides
    private var topMargin: CGFloat { frameHeight * 0.065 }
    private var bottomMargin: CGFloat { frameHeight * 0.065 }
    private var sideMargin: CGFloat { frameWidth * 0.085 }
    private var rightMargin: CGFloat { frameWidth * 0.105 }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: topMargin)
            
            // Header bar: title left, page number right
            HStack {
                Text(title ?? "Memory")
                    .font(fontStyle.titleFont(for: frameHeight))
                    .foregroundColor(colors.chapterTitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("\(pageNumber)")
                    .font(fontStyle.pageNumberFont(for: frameHeight))
                    .foregroundColor(colors.pageNumberColor)
            }
            .padding(.horizontal, sideMargin)
            .frame(height: barHeight)
            .frame(maxWidth: .infinity)
            .background(colors.bookPageBackground)
            
            // Body text with book-like spacing below header
            Text(text)
                .font(fontStyle.bodyFont(for: frameHeight))
                .lineSpacing(12)
                .multilineTextAlignment(.leading)
                .foregroundColor(colors.bookTextColor)
                .padding(.leading, sideMargin)
                .padding(.trailing, rightMargin)
                .padding(.top, frameHeight * 0.045)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .lineLimit(nil)
            
            Spacer().frame(height: bottomMargin)
        }
        .frame(width: frameWidth, height: frameHeight)
        .background(colors.bookPageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Vertical Book Style Pages (Realistic/Custom/Cartoon) - Professional and elegant
struct VerticalBookIllustrationPage: View {
    let image: UIImage
    let memoryID: UUID
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
                Spacer()
                
                // Main image - centered
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: frameHeight * 0.85)
                    .padding(.horizontal, frameWidth * 0.06)
                
                Spacer()
                
                // Bottom page numbers - exactly like reference with smaller font
                HStack {
                    Text("\(pageNumber)")
                        .font(.professionalPageNumberFont(for: frameHeight))
                        .foregroundColor(colors.pageNumberColor)
                    
                    Spacer()
                    
                    if pageNumber < totalPages {
                        Text("\(pageNumber + 1)")
                            .font(.professionalPageNumberFont(for: frameHeight))
                            .foregroundColor(colors.pageNumberColor)
                    }
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
    let title: String?
    let subtitle: String?
    let memoryID: UUID
    let fontStyle: BookFontStyle
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let pageNumber: Int
    
    private let colors = StoryPageLocalColors()
    
    var body: some View {
        ZStack {
            // Book page background
            colors.bookPageBackground
            
            VStack(spacing: 0) {
                // Header section with title on first page
                if let title = title {
                    VStack(alignment: .leading, spacing: frameHeight * 0.015) {
                        Text(title)
                            .font(fontStyle.titleFont(for: frameHeight))
                            .foregroundColor(colors.chapterTitleColor)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let subtitle = subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: max(12, frameHeight * 0.021), weight: .regular))
                                .foregroundColor(colors.chapterTitleColor.opacity(0.7))
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.leading, frameWidth * 0.06)
                    .padding(.trailing, frameWidth * 0.10) // Extra right padding to avoid QR code
                    .padding(.top, frameHeight * 0.05)
                }
                
                // Text content with art-style appropriate typography (fixed height, no scroll)
                VStack(alignment: .leading, spacing: frameHeight * 0.015) {
                    Text(text)
                        .font(fontStyle.bodyFont(for: frameHeight))
                        .lineSpacing(frameHeight * 0.006) // Tight line spacing like real books
                        .multilineTextAlignment(.leading)
                        .foregroundColor(colors.bookTextColor)
                }
                .padding(.leading, frameWidth * 0.06)
                .padding(.trailing, frameWidth * 0.10) // Extra right padding to avoid QR code
                .frame(maxWidth: .infinity, maxHeight: frameHeight * 0.75, alignment: .topLeading)
                .lineLimit(nil)
                
                Spacer()
                
                // Page number at bottom - small and professional
                Text("\(pageNumber)")
                    .font(fontStyle.pageNumberFont(for: frameHeight))
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
                // Header with appropriate font for each style
                Text("Listen to This Memory")
                    .font(isKidsBook ? .kidsBookTitleFont(for: frameHeight) : .professionalChapterFont(for: frameHeight))
                    .foregroundColor(colors.chapterTitleColor)
                    .padding(.top, frameHeight * 0.08)
                
                // QR Code with clean styling
                Image(uiImage: .memoirQRCode(from: url.absoluteString, size: qrSide))
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
                
                // Description with appropriate font size
                VStack(spacing: frameHeight * 0.02) {
                    Text("Scan this code with your phone's camera to hear the original audio recording of this memory.")
                        .font(isKidsBook ? .kidsBookBodyFont(for: frameHeight) : .professionalBodyFont(for: frameHeight))
                        .multilineTextAlignment(.center)
                        .foregroundColor(colors.bookTextColor.opacity(0.8))
                        .padding(.horizontal, frameWidth * 0.1)
                }
                
                Spacer()
                
                // Page number with appropriate font
                Text("\(pageNumber)")
                    .font(isKidsBook ? .kidsBookBodyFont(for: frameHeight) : .professionalPageNumberFont(for: frameHeight))
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
    
    // MARK: - Image Edit Sheet
    struct ImageEditSheet: View {
        let imageIndex: Int
        @Binding var revisionText: String
        @Binding var isPresented: Bool
        let onSend: (String) -> Void
        let isEditing: Bool
        
        @FocusState private var isTextFieldFocused: Bool
        @State private var isSendPressed: Bool = false
        
        private var trimmedRevisionText: String {
            revisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        private var canSend: Bool {
            !trimmedRevisionText.isEmpty && !isEditing
        }
        
        private func sendRevision() {
            guard canSend else { return }
            let payload = trimmedRevisionText
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSend(payload)
        }
        
        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Describe the changes you want...", text: $revisionText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(.leading, 4)
                        .focused($isTextFieldFocused)
                        .lineLimit(1...3)
                        .disabled(isEditing)
                        .submitLabel(.send)
                        .onSubmit {
                            sendRevision()
                        }
                    
                    // Send button
                    Button(action: {
                        sendRevision()
                    }) {
                        ZStack {
                            if isEditing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.95)))
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(canSend ? localColors.terracotta : Color.gray.opacity(0.45))
                        .clipShape(Circle())
                        .scaleEffect(isSendPressed ? 0.92 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isSendPressed)
                        .animation(.easeInOut(duration: 0.15), value: canSend)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                        isSendPressed = pressing
                    }, perform: {})
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .background(Color.clear)
            .onAppear {
                // Auto-focus text field when sheet appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextFieldFocused = true
                }
            }
        }
        
        private let localColors = StoryPageLocalColors()
    }
    
    // MARK: - Preview
    struct StoryPage_Previews: PreviewProvider {
        static var previews: some View {
            let dummyProfileVM = ProfileViewModel()
            StoryPage()
                .environmentObject(dummyProfileVM)
        }
    }


// MARK: - Extension for Modifiers
extension View {
    @ViewBuilder
    func addAllSheetsAndModifiers(
        showSettings: Binding<Bool>,
        showProfileSetup: Binding<Bool>,
        showGallery: Binding<Bool>,
        showImageEditSheet: Binding<Bool>,
        showPaywall: Binding<Bool>,
        showDownloadSuccess: Binding<Bool>,
        showRegenerateConfirmation: Binding<Bool>,
        showIncompleteMemoriesAlert: Binding<Bool>,
        navigateToRecent: Binding<Bool>,
        editingImageIndex: Binding<Int?>,
        editRevisionText: Binding<String>,
        selectedImageForFullScreen: Binding<UIImage?>,
        incompleteCount: Int,
        didCompleteProfileSetup: Binding<Bool>,
        headshotImage: Binding<UIImage?>,
        grandparentName: Binding<String>,
        userRace: Binding<String>,
        userGender: Binding<String>,
        profileVM: ProfileViewModel,
        subscriptionManager: RCSubscriptionManager,
        vm: StoryPageViewModel,
        localColors: StoryPageLocalColors,
        generateStorybookWithPaywallCheck: @escaping () -> Void,
        regenerateStorybook: @escaping () -> Void,
        updateIncompleteCount: @escaping () -> Void,
        hasRequestedGeneration: Binding<Bool>,
        showSubscriptionTooltip: Binding<Bool>,
        actualPreviewWidth: Binding<CGFloat>,
        actualPreviewHeight: Binding<CGFloat>,
        realProgress: Binding<Double>,
        showPageDetail: Binding<Bool>,
        detailPageIndex: Binding<Int>
    ) -> some View {
        let withSheets = addSheets(
            showSettings: showSettings,
            showProfileSetup: showProfileSetup,
            showGallery: showGallery,
            showImageEditSheet: showImageEditSheet,
            showPaywall: showPaywall,
            navigateToRecent: navigateToRecent,
            editingImageIndex: editingImageIndex,
            editRevisionText: editRevisionText,
            didCompleteProfileSetup: didCompleteProfileSetup,
            headshotImage: headshotImage,
            grandparentName: grandparentName,
            userRace: userRace,
            userGender: userGender,
            profileVM: profileVM,
            subscriptionManager: subscriptionManager,
            vm: vm,
            selectedImageForFullScreen: selectedImageForFullScreen,
            localColors: localColors,
            generateStorybookWithPaywallCheck: generateStorybookWithPaywallCheck,
            hasRequestedGeneration: hasRequestedGeneration,
            showPageDetail: showPageDetail,
            detailPageIndex: detailPageIndex
        )
        
        let withAlerts = withSheets.addAlerts(
            showDownloadSuccess: showDownloadSuccess,
            showRegenerateConfirmation: showRegenerateConfirmation,
            showIncompleteMemoriesAlert: showIncompleteMemoriesAlert,
            navigateToRecent: navigateToRecent,
            incompleteCount: incompleteCount,
            regenerateStorybook: regenerateStorybook
        )
        
        let withLifecycle = withAlerts.addLifecycleModifiers(
            profileVM: profileVM,
            vm: vm,
            subscriptionManager: subscriptionManager,
            headshotImage: headshotImage,
            hasRequestedGeneration: hasRequestedGeneration,
            updateIncompleteCount: updateIncompleteCount,
            realProgress: realProgress
        )
        
        withLifecycle.addOverlays(
            showSubscriptionTooltip: showSubscriptionTooltip
        )
    }
    
    @ViewBuilder
    private func addSheets(
        showSettings: Binding<Bool>,
        showProfileSetup: Binding<Bool>,
        showGallery: Binding<Bool>,
        showImageEditSheet: Binding<Bool>,
        showPaywall: Binding<Bool>,
        navigateToRecent: Binding<Bool>,
        editingImageIndex: Binding<Int?>,
        editRevisionText: Binding<String>,
        didCompleteProfileSetup: Binding<Bool>,
        headshotImage: Binding<UIImage?>,
        grandparentName: Binding<String>,
        userRace: Binding<String>,
        userGender: Binding<String>,
        profileVM: ProfileViewModel,
        subscriptionManager: RCSubscriptionManager,
        vm: StoryPageViewModel,
        selectedImageForFullScreen: Binding<UIImage?>,
        localColors: StoryPageLocalColors,
        generateStorybookWithPaywallCheck: @escaping () -> Void,
        hasRequestedGeneration: Binding<Bool>,
        showPageDetail: Binding<Bool>,
        detailPageIndex: Binding<Int>
    ) -> some View {
        self
            .background(
                NavigationLink(
                    destination: RecentMemoriesView().environmentObject(profileVM),
                    isActive: navigateToRecent
                ) {
                    EmptyView()
                }
            )
            .sheet(isPresented: showSettings) {
                SettingsView()
                    .environmentObject(profileVM)
                    .environmentObject(subscriptionManager)
            }
            .sheet(isPresented: showProfileSetup, onDismiss: {
                if didCompleteProfileSetup.wrappedValue {
                    generateStorybookWithPaywallCheck()
                    didCompleteProfileSetup.wrappedValue = false
                }
            }) {
                ProfileSetupView(
                    headshotImage: headshotImage,
                    name: grandparentName,
                    race: userRace,
                    gender: userGender,
                    onGenerate: {
                        didCompleteProfileSetup.wrappedValue = true
                    }
                )
                .environmentObject(profileVM)
                .environmentObject(subscriptionManager)
            }
            .sheet(isPresented: showGallery) {
                StorybookGalleryView(onBookSelected: { record, legacyBook in
                    showGallery.wrappedValue = false
                    if let legacyBook {
                        vm.loadHistoricBook(legacyBook)
                    } else {
                        vm.loadBookVersionRecord(record)
                    }
                    hasRequestedGeneration.wrappedValue = true
                })
                    .environmentObject(profileVM)
            }
            .overlay(
                FullScreenImageView(
                    selectedImage: selectedImageForFullScreen,
                    colors: localColors
                )
            )
            .sheet(isPresented: showImageEditSheet) {
                if let index = editingImageIndex.wrappedValue {
                    ImageEditSheet(
                        imageIndex: index,
                        revisionText: editRevisionText,
                        isPresented: showImageEditSheet,
                        onSend: { revisionText in
                            Task {
                                await vm.editImage(at: index, revisionPrompt: revisionText)
                            }
                        },
                        isEditing: vm.isEditingImage(at: index)
                    )
                    .presentationDetents([.height(152)])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(vm.isEditingImage(at: index))
                }
            }
            .onChange(of: vm.imageEditingStates) { _, _ in
                if let index = editingImageIndex.wrappedValue, !vm.isEditingImage(at: index) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        editRevisionText.wrappedValue = ""
                        editingImageIndex.wrappedValue = nil
                        showImageEditSheet.wrappedValue = false
                    }
                }
            }
            .fullScreenCover(isPresented: showPaywall) {
                makePaywallFallback()
            }
            .fullScreenCover(isPresented: showPageDetail) {
                StoryPageDetailView(
                    initialPageIndex: detailPageIndex.wrappedValue,
                    vm: vm,
                    artStyle: vm.currentArtStyle,
                    printSpec: vm.currentPrintSpec,
                    onRequestImageEdit: {
                        showPageDetail.wrappedValue = false
                        editingImageIndex.wrappedValue = $0
                        showImageEditSheet.wrappedValue = true
                    }
                )
            }
    }
    
    @ViewBuilder
    private func addAlerts(
        showDownloadSuccess: Binding<Bool>,
        showRegenerateConfirmation: Binding<Bool>,
        showIncompleteMemoriesAlert: Binding<Bool>,
        navigateToRecent: Binding<Bool>,
        incompleteCount: Int,
        regenerateStorybook: @escaping () -> Void
    ) -> some View {
        self
            .alert("Download Successful!", isPresented: showDownloadSuccess) {
                Button("OK") { }
            } message: {
                Text("Your storybook has been saved to your device.")
            }
            .alert("Regenerate Storybook?", isPresented: showRegenerateConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Regenerate", role: .destructive) {
                    regenerateStorybook()
                }
            } message: {
                Text("This will clear your current storybook and create a new one. This action cannot be undone.")
            }
            .alert("Enhance Memories for Better Images", isPresented: showIncompleteMemoriesAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Enhance Now") {
                    navigateToRecent.wrappedValue = true
                }
            } message: {
                Text("You have \(incompleteCount) \(incompleteCount == 1 ? "memory" : "memories") that can be enhanced with character details for better AI-generated images.")
            }
    }
    
    @ViewBuilder
    private func addLifecycleModifiers(
        profileVM: ProfileViewModel,
        vm: StoryPageViewModel,
        subscriptionManager: RCSubscriptionManager,
        headshotImage: Binding<UIImage?>,
        hasRequestedGeneration: Binding<Bool>,
        updateIncompleteCount: @escaping () -> Void,
        realProgress: Binding<Double>
    ) -> some View {
        self
            .onAppear {
                vm.loadStorybookForProfile(profileVM.selectedProfile.id, name: profileVM.selectedProfile.name)
                
                if headshotImage.wrappedValue == nil,
                   let test = UIImage(named: "old") {
                    headshotImage.wrappedValue = test
                    vm.subjectPhoto = test
                }

                Task { @MainActor in
                    if vm.styleTilePublic == nil,
                       let style = UIImage(named: "kidsref") {
                        vm.styleTile = style
                    }
                }

                Task { await subscriptionManager.refreshCustomerInfo() }
                updateIncompleteCount()
            }
            .onChange(of: profileVM.selectedProfile.id) { _, newProfileID in
                vm.loadStorybookForProfile(newProfileID, name: profileVM.selectedProfile.name)
                hasRequestedGeneration.wrappedValue = vm.hasGeneratedStorybook
                updateIncompleteCount()
            }
            .onChange(of: vm.progress) { _, newProgress in
                // Sync realProgress with vm.progress for accurate progress bar
                realProgress.wrappedValue = newProgress
            }
            .onChange(of: vm.isLoading) { _, _ in }
            .onChange(of: headshotImage.wrappedValue) { _, newShot in
                if let shot = newShot {
                    vm.subjectPhoto = shot
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .memorySaved)) { _ in
                updateIncompleteCount()
            }
    }
    
    @ViewBuilder
    private func addOverlays(
        showSubscriptionTooltip: Binding<Bool>
    ) -> some View {
        self
            .overlay(
                Group {
                    if showSubscriptionTooltip.wrappedValue {
                        makeSubscriptionTooltip()
                    }
                }
            )
    }
    
    @ViewBuilder
    private func makePaywallFallback() -> some View {
        Group {
            if RCSubscriptionManager.shared.offerings?.current?.availablePackages.isEmpty == false {
                PaywallView(displayCloseButton: true)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Subscription Temporarily Unavailable")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Please try again later or contact support.")
                        .multilineTextAlignment(.center)
                    
                    Button("Close") {
                        // Close handled by binding
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding()
                .background(Color.white)
            }
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private func makeSubscriptionTooltip() -> some View {
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
            .padding(.top, 80)
            
            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
