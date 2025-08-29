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
    @State private var showGallery = false
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
    
    // Human-readable remaining time string
    private var etaString: String {
        guard vm.isLoading, totalEstimatedSeconds > 0, let start = generationStart else { return "" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let remaining = max(0, totalEstimatedSeconds - elapsed)
        let mins = remaining / 60
        let secs = remaining % 60
        return "Estimated time: \(mins)m \(secs)s remaining"
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

                if !etaString.isEmpty {
                    Text(etaString)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Text("Please keep the app open while we generate your storybook.")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.8))
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
                    .fixedSize(horizontal: false, vertical: true)
                
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
                .onAppear {
                    // Capture actual preview dimensions for PDF generation
                    actualPreviewWidth = bookFrameWidth * 0.9
                    actualPreviewHeight = (bookFrameWidth * 0.9) * bookAspectRatio
                }
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
                // Incomplete memories banner
                if incompleteCount > 0 {
                    VStack(spacing:6){
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName:"exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .padding(.top,2)
                            Text("You have \(incompleteCount) memories that can be enhanced for better images.")
                                .font(.system(size:13))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(action:{ navigateToRecent = true }){
                            Text("Enhance Now")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(localColors.defaultWhite)
                                .padding(.horizontal,14).padding(.vertical,6)
                                .background(Color.orange)
                                .cornerRadius(8)
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
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
        etaTimer?.cancel()
        vm.isLoading = false
        // Don't reset hasRequestedGeneration - let it persist
    }
        
    private func generateStorybookWithPaywallCheck() {
        var pagesToAttempt = vm.expectedPageCount()

        // Auto-adjust to 1 image for free tier users
        if !isSubscribed {
            pagesToAttempt = FreePreviewConfig.maxPagesWithoutSubscription // Always use 1 for free users
            print("StoryPage: Free user - automatically using \(pagesToAttempt) image for generation")
        }

        guard pagesToAttempt > 0 else {
            vm.errorMessage = "Please select at least 1 memory to generate."
            return
        }
        
        // ─────────────────────────────────────────────────────────────
        // FREE PREVIEW LOGIC – non-subscribers get ONE lifetime preview (tracked via iCloud KV store)
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.synchronize() // ensure freshest value
        let freePreviewUsed = UserDefaults.standard.bool(forKey: "memoirai_freeBookUsed") || cloudStore.bool(forKey: "memoirai_freeBookUsed")

        if !isSubscribed {
            // 1️⃣ Already consumed → block generation entirely
            if freePreviewUsed {
                vm.errorMessage = "You have already used your free preview. Subscribe to unlock unlimited storybooks."
                vm.isLoading = false
                hasRequestedGeneration = false
                return
            }

            // 2️⃣ No need to check page count anymore since we auto-set it to 1
            // The validation is kept for safety but should never trigger
            if pagesToAttempt > FreePreviewConfig.maxPagesWithoutSubscription {
                // This should never happen now, but keep as safety check
                pagesToAttempt = FreePreviewConfig.maxPagesWithoutSubscription
            }
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
        
        // Estimate – assume ~12 s per image (OpenAI round-trip); tweak as needed
        totalEstimatedSeconds = pagesExpected * 12
        generationStart = Date()
        etaTimer?.cancel()
        etaTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in etaTick += 1 } // ticks every second to refresh UI
        
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
        let finalPageCount = pagesExpected // Pass the adjusted page count
        Task {
            await vm.generateStorybook(forProfileID: currentProfileID, overridePageCount: finalPageCount)
            
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
                    etaTimer?.cancel()
                } else {
                    print("StoryPage: Gen failed/no images. Error: \(vm.errorMessage ?? "N/A").")
                    self.realProgress = 0.0
                    self.fakeProgress = 0.0
                    etaTimer?.cancel()
                }
                if vm.isLoading { print("Warning: vm.isLoading is still true post-generation.")}
            }
        }
        
        // Mark free preview as consumed for non-subscribers (local + iCloud)
        if !isSubscribed {
            UserDefaults.standard.set(true, forKey: "memoirai_freeBookUsed")
            UserDefaults.standard.synchronize()
            let cloudStore = NSUbiquitousKeyValueStore.default
            cloudStore.set(true, forKey: "memoirai_freeBookUsed")
            cloudStore.synchronize()
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
                            // Gallery button (opens list of past books)
                            Button { showGallery = true } label: {
                                Image(systemName: "books.vertical")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(localColors.defaultBlack.opacity(0.7))
                                    .padding(10)
                                    .background(localColors.subtleControlBackground)
                                    .clipShape(Circle())
                            }
                            
                            // NEW: Download button (only show when storybook exists)
                            if hasRequestedGeneration && !vm.pageItems.isEmpty {
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
                            .onAppear {
                                // Capture actual dimensions for PDF generation
                                actualPreviewWidth = bookContentAreaWidth
                                actualPreviewHeight = bookContentHeightInsideFrame
                            }
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
            // Hidden nav link to RecentMemoriesView for enhance flow
            NavigationLink(destination: RecentMemoriesView().environmentObject(profileVM), isActive: $navigateToRecent) { EmptyView() }
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
            .sheet(isPresented: $showGallery) {
                StorybookGalleryView()
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
                // Add error handling around PaywallView
                Group {
                    if RCSubscriptionManager.shared.offerings?.current?.availablePackages.isEmpty == false {
                        PaywallView(displayCloseButton: true)
                    } else {
                        // Fallback view when paywall can't load
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
                                showPaywall = false
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
                
                updateIncompleteCount()
            }
            .onChange(of: profileVM.selectedProfile.id) { newProfileID in
                // Load storybook for new profile, don't reset
                vm.loadStorybookForProfile(newProfileID)
                
                // Update hasRequestedGeneration based on whether we have content
                hasRequestedGeneration = vm.hasGeneratedStorybook
                
                updateIncompleteCount()
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
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "profileID == %@", profileVM.selectedProfile.id as CVarArg)
        if let all = try? context.fetch(request) {
            incompleteCount = all.filter { $0.isIncomplete }.count
        }
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
