import SwiftUI
import UIKit
import PhotosUI
import Combine
import RevenueCat
import RevenueCatUI
import CoreData

// MARK: - Storybook headshot
/// The user's home-page profile photo is the default generation headshot; the
/// setup sheet still lets them replace it per run.
private enum StorybookHeadshotOverride {
    static func resolvedHeadshot(profilePhotoData: Data?) -> UIImage? {
        guard let data = profilePhotoData, let image = UIImage(data: data) else { return nil }
        return image
    }
}

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

// MARK: - Page Detail Presentation
/// Identifiable payload for `.fullScreenCover(item:)` so the detail view always
/// receives the tapped page index (a Bool-driven cover can capture stale state).
struct PageDetailRequest: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let startInEditMode: Bool
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
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @Environment(\.storybookScreenEntry) private var storybookScreenEntry
    @State private var userRace: String = ""
    @StateObject private var subscriptionManager = RCSubscriptionManager.shared
    
    let localColors = StoryPageLocalColors()
    
    @State private var currentPageIndex = 0
    @State private var showSettings = false
    @State private var showGallery = false
    @State private var selectedImageForFullScreen: UIImage? = nil
    @State private var hasRequestedGeneration = false
    @State private var pageDetailRequest: PageDetailRequest? = nil
    @State private var showCoverEditor = false
    @State private var showCoverArtEditSheet = false
    @State private var coverArtEditPanel: BookCoverFlatPanel = .front
    @State private var coverArtEditRevisionText = ""
    @State private var showCoverPDFMissingAlert = false
    
    // NEW: Download and regenerate functionality
    @State private var showDownloadSuccess = false
    @State private var showRegenerateConfirmation = false
    @State private var isDownloading = false
    @State private var isRegenerationFlow = false
    
    // Track actual preview dimensions for accurate PDF generation
    @State private var actualPreviewWidth: CGFloat = 0
    @State private var actualPreviewHeight: CGFloat = 0
    
    // NEW: Paywall state - exactly like MemoirView
    @State private var showPaywall = false
    
    // NEW: Tooltip state for subscription status
    @State private var showSubscriptionTooltip = false
    
    // Incomplete memories banner
    @State private var incompleteCount: Int = 0
    @State private var animateIncompleteMemoriesGlow = false
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
    @State private var orderNotReadyAlertTitle = "Book PDF Still Preparing"
    @State private var orderNotReadyAlertMessage = ""
    @State private var showSkippedMemoriesExplanation = false
    @ObservedObject private var printOrderCart = OrderCartStore.shared
    @State private var debugSessionID: String = String(UUID().uuidString.prefix(8))
    /// When free preview is exhausted, tutorial may allow one bonus image (tracked separately from `FreePreviewConfig`).
    @State private var pendingTutorialBonusGeneration: Bool = false
    
    @Environment(\.managedObjectContext) private var context
    
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
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        Color.orange,
                                        Color.yellow,
                                        Color.red.opacity(0.8),
                                        Color.orange
                                    ]),
                                    center: .center,
                                    angle: .degrees(animateIncompleteMemoriesGlow ? 360 : 0)
                                ),
                                lineWidth: 3
                            )
                    )
            )
            .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
            .onAppear {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    animateIncompleteMemoriesGlow = true
                }
            }
        }
    }
    
    @ViewBuilder
    private func storybookContentView(
        bookFrameWidth: CGFloat,
        bookContentHeightInsideFrame: CGFloat
    ) -> some View {
        if vm.isLoading {
            makeLoadingView()
        } else if vm.isLoadingGalleryBook {
            makeOpeningLibraryBookView()
        } else if hasRequestedGeneration && !vm.pageItems.isEmpty && vm.requiresVisualReadyGate && !vm.isVisualBookReady {
            makeFinalizingAssetsView()
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
            // One continuous bar for the whole pipeline — cloud illustration AND on-device
            // finalizing — so it never switches to an indeterminate spinner and appears stuck.
            ProgressView(value: vm.overallProgress)
                .progressViewStyle(
                    LinearProgressViewStyle(tint: localColors.terracotta)
                )
                .frame(height: 6)
                .padding(.horizontal, 40)
                .animation(.linear(duration: 0.3), value: vm.overallProgress)

            Text("\(Int(vm.overallProgress * 100))%")
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

            if !vm.etaDisplayText.isEmpty {
                Text(vm.etaDisplayText)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Text("Generating in the cloud. You can close the app and come back, and we’ll keep working on your storybook.")
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.8))
        }
    }

    @ViewBuilder
    private func makeFinalizingAssetsView() -> some View {
        VStack(spacing: 12) {
            ProgressView(value: vm.overallProgress)
                .progressViewStyle(
                    LinearProgressViewStyle(tint: localColors.terracotta)
                )
                .frame(height: 6)
                .padding(.horizontal, 40)
                .animation(.linear(duration: 0.3), value: vm.overallProgress)
            Text("Finalizing cover and print assets…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(localColors.terracotta)
            if !vm.etaDisplayText.isEmpty {
                Text(vm.etaDisplayText)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Text("Your book will appear once the final AI cover is fully ready.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    /// Shown in the book preview while a My Library selection downloads/applies (avoids empty-state flash).
    @ViewBuilder
    private func makeOpeningLibraryBookView() -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: localColors.terracotta))
                .scaleEffect(1.15)
            Text("Opening your book…")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(localColors.terracotta)
            Text("Loading pages and illustrations from the cloud.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
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
                    regenerateStorybook()
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
            ForEach(Array(vm.pageItems.enumerated()), id: \.element.id) { idx, item in
                let renderScale = min(
                    contentWidth / max(printSpec.widthPt, 1),
                    contentHeight / max(printSpec.heightPt, 1)
                )
                pageView(
                    for: item,
                    at: idx,
                    frameWidth: printSpec.widthPt,
                    frameHeight: printSpec.heightPt
                )
                .frame(width: printSpec.widthPt, height: printSpec.heightPt)
                .scaleEffect(renderScale, anchor: .center)
                .frame(width: contentWidth, height: contentHeight)
                .tag(idx)
                .onTapGesture {
                    pageDetailRequest = PageDetailRequest(pageIndex: idx, startInEditMode: false)
                }
            }
        }
        .id(vm.tabViewCoverRefreshIdentity)
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
        .allowsHitTesting(false)
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
            Spacer()

            VStack(spacing: 16) {
                if incompleteCount > 0 {
                    incompleteMemoriesBanner()
                        .padding(.bottom, 4)
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
                .tutorialAnchor(.storybookCreate)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { tutorialCoordinator.reportAnchor(.storybookCreate, rect: geo.frame(in: .global)) }
                            .onChange(of: geo.frame(in: .global)) { _, f in tutorialCoordinator.reportAnchor(.storybookCreate, rect: f) }
                    }
                )
                .accessibilityIdentifier("createStorybookButton")
                .disabled(vm.isLoading || vm.isUploadingToCloud)
            }

            Spacer()
        }
        .padding()
    }

    private func resetGenerationState() {
        // Don't clear vm.pageItems - let persistence handle this
        vm.errorMessage = nil
        currentPageIndex = 0
        vm.progress = 0
        vm.isLoading = false
        // Don't reset hasRequestedGeneration - let it persist
    }
        
    private func generateStorybookWithPaywallCheck() {
        var pagesToAttempt = vm.expectedPageCount()
        
        // Debug: Print current free preview status
        FreePreviewConfig.printStatus()

        // ─────────────────────────────────────────────────────────────
        // FREE PREVIEW LOGIC – non-subscribers get limited free images (tracked via iCloud KV store)
        pendingTutorialBonusGeneration = false
        if !isSubscribed {
            let remaining = FreePreviewConfig.freeImagesRemaining
            let profileID = profileVM.selectedProfile.id

            if FreePreviewConfig.canGenerateFreePreview {
                // Always generate just 1 at a time for free users to track accurately
                pagesToAttempt = 1
                print("StoryPage: Free user - using 1 image (remaining: \(remaining)/\(FreePreviewConfig.maxPagesWithoutSubscription))")
            } else if tutorialCoordinator.canUseTutorialBonusGeneration(isSubscribed: false, profileID: profileID) {
                pagesToAttempt = 1
                pendingTutorialBonusGeneration = true
                print("StoryPage: Tutorial bonus — 1 image while free preview exhausted")
            } else {
                vm.errorMessage = "You have already used your free preview. Subscribe to unlock unlimited storybooks."
                vm.isLoading = false
                hasRequestedGeneration = false
                return
            }
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
        // `pagesToAttempt` is the settings / allowance cap for illustrated pages this run, not the DB memory count.
        if subscriptionManager.isLargeGeneration(pages: pagesToAttempt) {
            print("⚠️ StoryPage: Large generation requested (\(pagesToAttempt) illustrated pages cap). User was warned in settings.")
        }
        
        print("StoryPage: Generation approved. Up to \(pagesToAttempt) illustrated pages this run (eligible memories are ranked and may be fewer).")
        startActualGenerationProcess(pagesExpected: pagesToAttempt)
    }
        
    private func startActualGenerationProcess(pagesExpected: Int) {
        if vm.isLoading || vm.isUploadingToCloud {
            print("StoryPage: startActualGenerationProcess ignored — isLoading=\(vm.isLoading) isUploadingToCloud=\(vm.isUploadingToCloud)")
            return
        }
        resetGenerationState()
        hasRequestedGeneration = true
        vm.isLoading = true

        let currentProfileID = profileVM.selectedProfile.id
        let finalPageCount = pagesExpected // Pass the adjusted page count
        let wasSubscribed = isSubscribed // Capture subscription state before async
        let useTutorialBonus = pendingTutorialBonusGeneration
        
        Task { @MainActor in
            vm.syncFaceDescriptionFromProfile(profileVM.selectedProfile)
            await vm.generateStorybook(
                forProfileID: currentProfileID,
                profileName: profileVM.selectedProfile.name,
                overridePageCount: finalPageCount,
                profileEthnicity: profileVM.selectedProfile.ethnicity
            )

            // Cloud generation: `generateStorybook` returns immediately after
            // kicking off the Firestore job — actual completion happens later
            // via the cloud listener.  Wait until the VM has finished
            // finalizing (or hit an error) before deciding whether to consume
            // the user's free-preview / tutorial / subscription allowance.
            for await stillLoading in vm.$isLoading.values {
                if !stillLoading { break }
            }

            if vm.errorMessage == nil && vm.storybookGeneratedIllustrationCount > 0 {
                let actualImagesGenerated = vm.storybookGeneratedIllustrationCount
                if actualImagesGenerated > 0 {
                    if wasSubscribed {
                        // Subscribed users: deduct from monthly allowance
                        subscriptionManager.consume(pages: actualImagesGenerated)
                        print("StoryPage: Consumed \(actualImagesGenerated) images from subscription.")
                    } else if useTutorialBonus {
                        tutorialCoordinator.consumeTutorialBonus(profileID: currentProfileID)
                        print("StoryPage: Consumed tutorial bonus image (free preview was exhausted).")
                    } else {
                        // Free users: increment free preview counter (stored in iCloud + UserDefaults)
                        FreePreviewConfig.incrementFreeImagesUsed(by: actualImagesGenerated)
                        print("StoryPage: Consumed \(actualImagesGenerated) free preview image(s). Remaining: \(FreePreviewConfig.freeImagesRemaining)")
                    }
                    if tutorialCoordinator.isTutorialActive {
                        tutorialCoordinator.completeTutorial(profileID: currentProfileID)
                    }
                }
            } else {
                print("StoryPage: Cloud generation finished without illustrations. Error: \(vm.errorMessage ?? "N/A").")
                // Note: We don't consume free preview images on failure
            }
            self.pendingTutorialBonusGeneration = false
        }
    }

    var body: some View {
        let mainContent = makeMainContent()
        
        return NavigationStack {
            mainContent
                .navigationBarHidden(true)
                .onAppear {
                    tutorialCoordinator.setVisibleScreen(.storyPage)
                    tutorialCoordinator.onStoryPageAppeared(profileID: profileVM.selectedProfile.id)
                    tutorialCoordinator.reloadBonusState(profileID: profileVM.selectedProfile.id)
                }
                .onDisappear {
                    tutorialCoordinator.clearAnchor(.storybookCreate)
                    if tutorialCoordinator.visibleScreen == .storyPage {
                        tutorialCoordinator.setVisibleScreen(.unknown)
                    }
                }
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
            onProfileSetupDismissed: handleProfileSetupDismiss,
            regenerateStorybook: regenerateStorybook,
            updateIncompleteCount: updateIncompleteCount,
            hasRequestedGeneration: $hasRequestedGeneration,
            showSubscriptionTooltip: $showSubscriptionTooltip,
            actualPreviewWidth: $actualPreviewWidth,
            actualPreviewHeight: $actualPreviewHeight,
            pageDetailRequest: $pageDetailRequest,
            showCoverEditor: $showCoverEditor,
            storybookScreenEntry: storybookScreenEntry
        )
        .sheet(isPresented: $showCoverArtEditSheet) {
            CoverArtEditSheet(
                panel: coverArtEditPanel,
                revisionText: $coverArtEditRevisionText,
                isPresented: $showCoverArtEditSheet,
                onSend: { text in
                    Task {
                        await vm.editCoverPanel(coverArtEditPanel, revisionPrompt: text)
                    }
                },
                isEditing: vm.isEditingCoverArt(for: coverArtEditPanel),
                onEditTitleBlurb: {
                    showCoverArtEditSheet = false
                    showCoverEditor = true
                }
            )
            .presentationDetents([PresentationDetent.height(196)])
            .presentationDragIndicator(Visibility.visible)
        }
        .onChange(of: vm.coverPanelEditing) { oldVal, newVal in
            if oldVal != nil && newVal == nil && showCoverArtEditSheet {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    coverArtEditRevisionText = ""
                    showCoverArtEditSheet = false
                }
            }
        }
        .alert("Print cover not ready", isPresented: $showCoverPDFMissingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Wait until your cover PDF has finished generating and synced, then try again. You can also open the book from My Library once the cover appears there.")
        }
        .fullScreenCover(item: $orderBookRecordForSheet) { record in
            OrderBookView(book: record)
        }
        .alert(orderNotReadyAlertTitle, isPresented: $orderNotReadyAlert) {
            Button("Retry") {
                orderBookTapped()
            }
            Button("Contact Support") {
                SupportContact.contact {
                    // No Mail client available — reuse this same alert to confirm the clipboard fallback
                    // (deferred a tick since SwiftUI is already dismissing this presentation).
                    DispatchQueue.main.async {
                        orderNotReadyAlertTitle = "Email Copied"
                        orderNotReadyAlertMessage = "We couldn't open Mail, so we copied \(SupportContact.email) to your clipboard."
                        orderNotReadyAlert = true
                    }
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(orderNotReadyAlertMessage)
        }
        .sheet(isPresented: $showSkippedMemoriesExplanation) {
            skippedMemoriesExplanationContent
        }
        // Loading UI: only `makeOpeningLibraryBookView()` (terra cotta) inside `storybookContentView` — do not stack `GalleryBookLoadingOverlay` here or text duplicates.
        .animation(.easeInOut(duration: 0.2), value: vm.isLoadingGalleryBook)
    }

    private var skippedMemoriesExplanationContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(vm.skippedMemoriesNoticeSummary)
                        .font(.body)
                        .foregroundColor(.primary)

                    ForEach(vm.skippedMemoriesDuringGeneration) { skipped in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(skipped.memoryLabel)
                                .font(.headline)
                            Text(skipped.detail)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(localColors.softCream.opacity(0.6))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .background(localColors.softCream.ignoresSafeArea())
            .navigationTitle("Illustration notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSkippedMemoriesExplanation = false
                    }
                }
            }
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
                makeBottomActionArea()
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 5)
            }
        }
    }
    
    @ViewBuilder
    private func makeHeader() -> some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top) {
                makeBackButton()
                Spacer()
                makeHeaderButtons()
            }

            makeTitleSection()
                .frame(maxWidth: 250, alignment: .top)
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
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundColor(localColors.defaultBlack.opacity(0.8))
                .tracking(-0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
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
        VStack(spacing: 8) {
            if hasGeneratedStorybook, !vm.skippedMemoriesDuringGeneration.isEmpty {
                Button {
                    showSkippedMemoriesExplanation = true
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(10)
                        .background(localColors.subtleControlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Some memories were not illustrated")
                .accessibilityHint("Shows which memories were skipped when the storybook was created")
            }

            if hasGeneratedStorybook {
                makeDownloadButton()
                makePrintCartButton()
            } else {
                makeSettingsButton()
            }

            makeGalleryButton()
        }
        .frame(minWidth: 44)
    }

    /// Opens the same print-order sheet as **Print** (cart + checkout live here).
    @ViewBuilder
    private func makePrintCartButton() -> some View {
        Button(action: orderBookTapped) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bag.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(localColors.defaultBlack.opacity(0.7))
                    .padding(10)
                    .background(localColors.subtleControlBackground)
                    .clipShape(Circle())

                if printOrderCart.totalLineCount > 0 {
                    Text("\(printOrderCart.totalLineCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(localColors.terracotta))
                        .offset(x: 10, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Print order and cart")
    }

    private var hasGeneratedStorybook: Bool {
        hasRequestedGeneration && !vm.pageItems.isEmpty
    }
    
    @ViewBuilder
    private func makeGalleryButton() -> some View {
        Button {
            print("🧭 StoryPage[\(debugSessionID)] gallery button tapped; opening library")
            showGallery = true
        } label: {
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
        let isEmptyState = !vm.isLoading && vm.errorMessage == nil && (!hasRequestedGeneration || vm.pageItems.isEmpty)
        
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
        // Nudge empty-state card slightly upward so it visually centers with header controls.
        let emptyStateVerticalOffset: CGFloat = isEmptyState ? -18 : 0
        let bookFrameY = (geo.size.height / 2) + emptyStateVerticalOffset
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
    private func makeBottomActionArea() -> some View {
        if hasRequestedGeneration && !vm.pageItems.isEmpty && !vm.isLoading && (!vm.requiresVisualReadyGate || vm.isVisualBookReady) {
            VStack(spacing: 14) {
                Button(action: handleCurrentPageEditTapped) {
                    HStack(spacing: 7) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                        Text("Edit")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(localColors.terracotta)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(localColors.terracotta.opacity(0.14))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(localColors.terracotta.opacity(0.25), lineWidth: 1)
                    )
                }

                HStack(spacing: 10) {
                    Button(action: { showRegenerateConfirmation = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .medium))
                            Text("Regenerate")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(localColors.terracotta)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(localColors.terracotta.opacity(0.15))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(localColors.terracotta.opacity(0.3), lineWidth: 1)
                        )
                    }

                    Button(action: orderBookTapped) {
                        HStack(spacing: 8) {
                            if isOrderPreparing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: "printer")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            Text("Order")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(minWidth: 112)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(localColors.terracotta)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Order")
                    .disabled(isOrderPreparing)
                    .opacity(isOrderPreparing ? 0.7 : 1.0)
                }
                .frame(maxWidth: 360)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
    }

    private func orderBookTapped() {
        guard !isOrderPreparing else { return }
        isOrderPreparing = true
        Task {
            _ = await vm.fetchCurrentBookVersionRecord()
            let versionId = vm.currentBookVersionRecord?.bookVersionId ?? vm.lastSyncedBookVersionId
            if !vm.isBookOrderable, let id = versionId {
                let r = vm.currentBookVersionRecord
                let needsInteriorPDF =
                    r == nil
                    || r?.renderStatus != BookRenderStatus.rendered.rawValue
                    || r?.pdfURL == nil
                if needsInteriorPDF {
                    _ = await FirestoreSyncService.shared.fetchOrGenerateBookPDF(
                        bookVersionId: id,
                        timeoutSeconds: 60
                    )
                    _ = await vm.fetchCurrentBookVersionRecord()
                }
            }
            await MainActor.run {
                isOrderPreparing = false
                if vm.isBookOrderable, let record = vm.currentBookVersionRecord {
                    orderBookRecordForSheet = record
                } else {
                    if let record = vm.currentBookVersionRecord {
                        let copy = Self.orderNotReadyAlertCopy(for: record)
                        orderNotReadyAlertTitle = copy.title
                        orderNotReadyAlertMessage = copy.message
                        print(
                            "🧭 StoryPage print blocked: " +
                            "renderStatus=\(record.renderStatus), " +
                            "hasPDF=\(record.pdfURL != nil), " +
                            "hasCover=\(record.coverURL != nil), " +
                            "pageCount=\(record.pageCount), " +
                            "renderError=\(record.renderError ?? "nil")"
                        )
                    } else {
                        orderNotReadyAlertTitle = "Book Not Ready"
                        orderNotReadyAlertMessage = "We could not load this book’s print status. Check your connection and tap Retry."
                    }
                    orderNotReadyAlert = true
                }
            }
        }
    }

    private static func orderNotReadyAlertCopy(for record: BookVersionRecord) -> (title: String, message: String) {
        if record.renderStatus != BookRenderStatus.rendered.rawValue {
            return (
                "Book Still Processing",
                "The print server is still assembling your interior PDF. This can take a few minutes on slower connections. Tap Retry to check again."
            )
        }
        if record.pdfURL == nil {
            return (
                "Interior PDF Still Preparing",
                "Your book’s printable interior is not ready yet. Tap Retry to trigger another check. This usually finishes within a couple of minutes."
            )
        }
        if record.coverURL == nil {
            return (
                "Cover Still Preparing",
                "Your cover file is still being prepared for print. Tap Retry in a moment. If this persists, open the book from the gallery and try Order again."
            )
        }
        return (
            "Book Not Ready for Order",
            "Something unexpected prevented checkout. Tap Retry, or contact support if this continues."
        )
    }

    private func handleCurrentPageEditTapped() {
        guard currentPageIndex >= 0, currentPageIndex < vm.pageItems.count else { return }

        if case .textPage(_, _, _, _, _, let memoryID) = vm.pageItems[currentPageIndex] {
            if memoryID == BookInteriorAnchor.titlePageMemoryId {
                if vm.hasPrintCoverPDF {
                    coverArtEditPanel = .front
                    coverArtEditRevisionText = ""
                    showCoverArtEditSheet = true
                } else {
                    showCoverPDFMissingAlert = true
                }
                return
            }
            if memoryID == BookInteriorAnchor.closingPageMemoryId {
                if vm.hasPrintCoverPDF {
                    coverArtEditPanel = .back
                    coverArtEditRevisionText = ""
                    showCoverArtEditSheet = true
                } else {
                    showCoverPDFMissingAlert = true
                }
                return
            }
        }

        switch vm.pageItems[currentPageIndex] {
        case .illustration, .textPage:
            pageDetailRequest = PageDetailRequest(pageIndex: currentPageIndex, startInEditMode: true)
        }
    }
    
    private func handleProfileSetupDismiss() {
        if didCompleteProfileSetup {
            // Only clear after the user completes the setup+settings flow for regeneration.
            if isRegenerationFlow {
                vm.clearCurrentStorybook()
                hasRequestedGeneration = false
            }
            generateStorybookWithPaywallCheck()
            didCompleteProfileSetup = false
        }
        isRegenerationFlow = false
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
        // Route through the same setup path as first-time creation:
        // ProfileSetupView -> Review Settings -> Save & Generate.
        isRegenerationFlow = true
        didCompleteProfileSetup = false
        showProfileSetup = true
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

    /// Instruction-based edit for print cover PDF panels (front / back), matching interior `ImageEditSheet` UX.
    struct CoverArtEditSheet: View {
        let panel: BookCoverFlatPanel
        @Binding var revisionText: String
        @Binding var isPresented: Bool
        let onSend: (String) -> Void
        let isEditing: Bool
        let onEditTitleBlurb: () -> Void

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

        private var panelTitle: String {
            panel == .front ? "Edit front cover art" : "Edit back cover art"
        }

        private let localColors = StoryPageLocalColors()

        var body: some View {
            VStack(spacing: 0) {
                Text(panelTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                HStack(spacing: 10) {
                    TextField("Describe the changes you want...", text: $revisionText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(.leading, 4)
                        .focused($isTextFieldFocused)
                        .lineLimit(1...3)
                        .disabled(isEditing)
                        .submitLabel(.send)
                        .onSubmit { sendRevision() }

                    Button(action: { sendRevision() }) {
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
                .padding(.top, 8)
                .padding(.bottom, 8)

                Button(action: onEditTitleBlurb) {
                    Text("Edit book title & back cover text")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(localColors.terracotta)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
            }
            .background(Color.clear)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextFieldFocused = true
                }
            }
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
        let isPrecomposed = vm.isPrecomposedIllustration(memoryID: memoryID)
        
        Group {
            if isPrecomposed {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: frameWidth, height: frameHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
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
                        title: title,
                        fontStyle: BookFontStyle(artStyle: vm.currentArtStyle),
                        frameWidth: frameWidth,
                        frameHeight: frameHeight,
                        pageNumber: index + 1,
                        totalPages: vm.pageItems.count
                    )
                }
            }
        }
        .overlay {
            if !isPrecomposed {
                // QR Watermark — below illustration title bar (kids + portrait both use barHeight 6.5%)
                QRWatermark(
                    memoryID: memoryID,
                    topInset: frameHeight * 0.065 + 6
                )
            }
        }
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
                    .allowsHitTesting(false)
                }
            }
        )
        .overlay {
            if vm.needsCloudIllustrationReload(memoryID: memoryID) {
                VStack {
                    Spacer()
                    if vm.isCloudIllustrationRetrying(memoryID: memoryID) {
                        ProgressView("Loading…")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Button {
                            vm.retryCloudIllustrationLoad(memoryID: memoryID)
                        } label: {
                            Text("Retry")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 12)
                                .background(localColors.terracotta)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                        .frame(height: max(frameHeight * 0.06, 16))
                }
            }
        }
    }
    
    @ViewBuilder
    private func makeTextPage(pageIndex: Int, total: Int, text: String, title: String?, subtitle: String?, memoryID: UUID, index: Int, frameWidth: CGFloat, frameHeight: CGFloat, isKidsBook: Bool) -> some View {
        let fontStyle = BookFontStyle(artStyle: vm.currentArtStyle)
        let fallbackFrontCover = MemoirCoverFrontPage(
            title: (title ?? vm.bookDisplayTitle).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Memoir" : (title ?? vm.bookDisplayTitle),
            subtitle: text,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            isKidsBook: isKidsBook
        )

        let fallbackBackCover = MemoirCoverBackPage(
            subtitle: subtitle,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )

        if memoryID == BookInteriorAnchor.titlePageMemoryId {
            if let pdfURL = printCoverPDFURL() {
                RemotePDFThumbnailView(
                    url: pdfURL,
                    targetSize: CGSize(width: max(frameWidth, 200), height: max(frameHeight, 200)),
                    layout: vm.currentBookVersionRecord?.coverFlatLayoutKind ?? .kidsBook(pageCount: max(1, vm.pageItems.count)),
                    panel: .front,
                    cacheRevision: vm.currentBookVersionRecord?.coverThumbnailCacheRevision ?? "",
                    cacheIdentity: vm.currentBookVersionRecord?.coverStoragePath ?? ""
                ) {
                    TitleCoverLoadingPlaceholder(frameWidth: frameWidth, frameHeight: frameHeight)
                }
                .frame(width: frameWidth, height: frameHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let rasterURL = rasterCoverDisplayURL() {
                AsyncImage(url: rasterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        TitleCoverLoadingPlaceholder(frameWidth: frameWidth, frameHeight: frameHeight)
                    case .failure:
                        fallbackFrontCover
                    @unknown default:
                        TitleCoverLoadingPlaceholder(frameWidth: frameWidth, frameHeight: frameHeight)
                    }
                }
                .frame(width: frameWidth, height: frameHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                fallbackFrontCover
            }
        } else if memoryID == BookInteriorAnchor.closingPageMemoryId {
            if let pdfURL = printCoverPDFURL() {
                RemotePDFThumbnailView(
                    url: pdfURL,
                    targetSize: CGSize(width: max(frameWidth, 200), height: max(frameHeight, 200)),
                    layout: vm.currentBookVersionRecord?.coverFlatLayoutKind ?? .kidsBook(pageCount: max(1, vm.pageItems.count)),
                    panel: .back,
                    cacheRevision: vm.currentBookVersionRecord?.coverThumbnailCacheRevision ?? "",
                    cacheIdentity: vm.currentBookVersionRecord?.coverStoragePath ?? ""
                ) {
                    TitleCoverLoadingPlaceholder(frameWidth: frameWidth, frameHeight: frameHeight)
                }
                .frame(width: frameWidth, height: frameHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let rasterURL = rasterCoverDisplayURL() {
                AsyncImage(url: rasterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        TitleCoverLoadingPlaceholder(frameWidth: frameWidth, frameHeight: frameHeight)
                    case .failure:
                        fallbackBackCover
                    @unknown default:
                        TitleCoverLoadingPlaceholder(frameWidth: frameWidth, frameHeight: frameHeight)
                    }
                }
                .frame(width: frameWidth, height: frameHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                fallbackBackCover
            }
        } else {
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
                QRWatermark(memoryID: memoryID)
            )
        }
    }

    private func printCoverPDFURL() -> URL? {
        vm.currentBookVersionRecord?.printCoverPDFURL
    }

    /// When `printCoverPDFURL` is nil but `coverURL` is an http(s) raster, match `OrderBookView` so the in-book cover matches checkout preview.
    private func rasterCoverDisplayURL() -> URL? {
        guard let raw = vm.currentBookVersionRecord?.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard shouldAttemptRemoteRasterCoverImage(urlString: raw) else { return nil }
        return URL(string: raw)
    }

    private func shouldAttemptRemoteRasterCoverImage(urlString: String) -> Bool {
        let lower = urlString.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        if lower.contains(".pdf") { return false }
        return true
    }
}

struct GalleryBookLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.4)
                Text("Opening your book…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
        }
        .allowsHitTesting(true)
    }
}

struct StorybookCoverEditorSheet: View {
    @ObservedObject var vm: StoryPageViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var titleDraft: String = ""
    @State private var pitchDraft: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Book Title")) {
                    TextField("Memoir title", text: $titleDraft)
                        .textInputAutocapitalization(.words)
                }
                Section(header: Text("Back Cover Blurb"),
                        footer: Text("Shown on the back cover of the printed book.")) {
                    TextEditor(text: $pitchDraft)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Edit Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.bookDisplayTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        vm.backCoverPitch = pitchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            titleDraft = vm.bookDisplayTitle
            pitchDraft = vm.backCoverPitch
        }
    }
}

private struct TitleCoverLoadingPlaceholder: View {
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    private let paper = Color(red: 0.965, green: 0.94, blue: 0.89)

    var body: some View {
        ZStack {
            paper
            ProgressView()
                .scaleEffect(1.05)
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            // Top bar: memory title left, page number right (vertically centered in the bar)
            HStack(alignment: .center) {
                Text(title ?? "Memory")
                    .font(.kidsBookTitleFont(for: frameHeight))
                    .foregroundColor(colors.chapterTitleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    // Serif cap height leaves empty space above glyphs; nudge down so the bar feels vertically balanced.
                    .offset(y: max(1, barHeight * 0.1))
                Spacer()
                Text("\(pageNumber)")
                    .font(.kidsBookPageNumberFont(for: frameHeight))
                    .foregroundColor(colors.pageNumberColor)
            }
            .padding(.horizontal, frameWidth * 0.08)
            .padding(.vertical, barHeight * 0.1)
            .frame(maxWidth: .infinity, minHeight: barHeight, alignment: .center)
            .background(colors.bookPageBackground)

            // Full page illustration fills remaining space
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            
            // Header bar: title left, page number right (vertically centered in the bar)
            HStack(alignment: .center) {
                Text(title ?? "")
                    .font(fontStyle.titleFont(for: frameHeight))
                    .foregroundColor(colors.chapterTitleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .offset(y: max(1, barHeight * 0.1))
                Spacer()
                Text("\(pageNumber)")
                    .font(fontStyle.pageNumberFont(for: frameHeight))
                    .foregroundColor(colors.pageNumberColor)
            }
            .padding(.horizontal, sideMargin)
            .padding(.vertical, barHeight * 0.1)
            .frame(maxWidth: .infinity, minHeight: barHeight, alignment: .center)
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
    /// LLM / short memory title for the top bar (same role as kids book illustration header).
    let title: String?
    let fontStyle: BookFontStyle
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let pageNumber: Int
    let totalPages: Int
    
    private let colors = StoryPageLocalColors()
    private var barHeight: CGFloat { frameHeight * 0.065 }
    private var headerTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Memory" : t
    }
    
    var body: some View {
        ZStack {
            // Book page background - exactly like reference
            colors.bookPageBackground
            
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text(headerTitle)
                        .font(fontStyle.titleFont(for: frameHeight))
                        .foregroundColor(colors.chapterTitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .offset(y: max(1, barHeight * 0.1))
                    Spacer()
                    Text("\(pageNumber)")
                        .font(fontStyle.pageNumberFont(for: frameHeight))
                        .foregroundColor(colors.pageNumberColor)
                }
                .padding(.horizontal, frameWidth * 0.06)
                .padding(.vertical, barHeight * 0.1)
                .frame(maxWidth: .infinity, minHeight: barHeight, alignment: .center)
                .background(colors.bookPageBackground)

                Spacer()
                
                // Main image - centered
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: frameHeight * 0.78)
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
                .environmentObject(TutorialCoordinator.shared)
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
        onProfileSetupDismissed: @escaping () -> Void,
        regenerateStorybook: @escaping () -> Void,
        updateIncompleteCount: @escaping () -> Void,
        hasRequestedGeneration: Binding<Bool>,
        showSubscriptionTooltip: Binding<Bool>,
        actualPreviewWidth: Binding<CGFloat>,
        actualPreviewHeight: Binding<CGFloat>,
        pageDetailRequest: Binding<PageDetailRequest?>,
        showCoverEditor: Binding<Bool>,
        storybookScreenEntry: StorybookScreenEntry
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
            onProfileSetupDismissed: onProfileSetupDismissed,
            hasRequestedGeneration: hasRequestedGeneration,
            pageDetailRequest: pageDetailRequest,
            showCoverEditor: showCoverEditor
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
            storybookScreenEntry: storybookScreenEntry
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
        onProfileSetupDismissed: @escaping () -> Void,
        hasRequestedGeneration: Binding<Bool>,
        pageDetailRequest: Binding<PageDetailRequest?>,
        showCoverEditor: Binding<Bool>
    ) -> some View {
        self
            .background(
                NavigationLink(
                    destination: RecentMemoriesView(prioritizeEnhanceCandidates: true).environmentObject(profileVM),
                    isActive: navigateToRecent
                ) {
                    EmptyView()
                }
            )
            .fullScreenCover(isPresented: showGallery, onDismiss: {
                print("🧭 StoryPage gallery cover dismissed")
            }) {
                StorybookGalleryView(onBookSelected: { record, legacyBook in
                    print("🧭 StoryPage gallery selection received: id=\(record.bookVersionId), source=\(record.source), pages=\(record.pageCount)")
                    hasRequestedGeneration.wrappedValue = true
                    vm.loadGalleryBook(record: record, legacyBook: legacyBook)
                    // Dismiss next run loop so `isLoadingGalleryBook` can publish and the story view can show loading under/after the cover.
                    DispatchQueue.main.async {
                        showGallery.wrappedValue = false
                    }
                })
                .environmentObject(profileVM)
            }
            .onChange(of: showGallery.wrappedValue) { oldValue, newValue in
                print("🧭 StoryPage showGallery changed: \(oldValue) -> \(newValue)")
            }
            .sheet(isPresented: showSettings) {
                SettingsView()
                    .environmentObject(profileVM)
                    .environmentObject(subscriptionManager)
            }
            .sheet(isPresented: showProfileSetup, onDismiss: {
                onProfileSetupDismissed()
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
                    .presentationDetents([PresentationDetent.height(152)])
                    .presentationDragIndicator(Visibility.visible)
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
            .fullScreenCover(item: pageDetailRequest) { request in
                StoryPageDetailView(
                    initialPageIndex: request.pageIndex,
                    vm: vm,
                    artStyle: vm.currentArtStyle,
                    printSpec: vm.currentPrintSpec,
                    startEditingOnAppear: request.startInEditMode,
                    onRequestImageEdit: {
                        pageDetailRequest.wrappedValue = nil
                        editingImageIndex.wrappedValue = $0
                        showImageEditSheet.wrappedValue = true
                    }
                )
            }
            .sheet(isPresented: showCoverEditor) {
                StorybookCoverEditorSheet(vm: vm)
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
        storybookScreenEntry: StorybookScreenEntry
    ) -> some View {
        self
            .onAppear {
                print("🧭 StoryPage lifecycle onAppear; profile=\(profileVM.selectedProfile.id.uuidString), hasGenerated=\(vm.hasGeneratedStorybook), hasRequested=\(hasRequestedGeneration.wrappedValue), pageItems=\(vm.pageItems.count), entry=\(storybookScreenEntry)")
                StorybookSeenTracker.shared.setStoryPageVisible(true)
                StorybookSeenTracker.shared.consumePendingRouteAsSeen()
                if let bookId = vm.currentBookVersionRecord?.bookVersionId {
                    StorybookSeenTracker.shared.markCompletedSeen(jobId: bookId)
                }
                Task { @MainActor in
                    let resuming = await vm.resumeInProgressGenerationIfMarkerExists(
                        profileID: profileVM.selectedProfile.id,
                        profileName: profileVM.selectedProfile.name,
                        profileEthnicity: profileVM.selectedProfile.ethnicity
                    )
                    if resuming {
                        hasRequestedGeneration.wrappedValue = true
                    } else {
                        vm.loadStorybookForProfile(
                            profileVM.selectedProfile.id,
                            name: profileVM.selectedProfile.name,
                            profileEthnicity: profileVM.selectedProfile.ethnicity
                        )
                        hasRequestedGeneration.wrappedValue = vm.hasGeneratedStorybook
                    }
                }
                
                if let image = StorybookHeadshotOverride.resolvedHeadshot(profilePhotoData: profileVM.selectedProfile.photoData) {
                    headshotImage.wrappedValue = image
                    vm.subjectPhoto = image
                } else {
                    headshotImage.wrappedValue = nil
                    vm.subjectPhoto = nil
                }
                vm.syncFaceDescriptionFromProfile(profileVM.selectedProfile)

                Task { @MainActor in
                    if vm.styleTilePublic == nil,
                       let style = UIImage(named: "kidsref") {
                        vm.styleTile = style
                    }
                }

                Task { await subscriptionManager.refreshCustomerInfo() }
                updateIncompleteCount()
            }
            .onDisappear {
                print("🧭 StoryPage lifecycle onDisappear; hasRequested=\(hasRequestedGeneration.wrappedValue), pageItems=\(vm.pageItems.count)")
                StorybookSeenTracker.shared.setStoryPageVisible(false)
            }
            .onChange(of: vm.currentBookVersionRecord?.bookVersionId) { _, newBookId in
                // Displaying a finished book (job id == book version id) counts as seeing it,
                // so the launch auto-route stops force-opening it.
                if let newBookId {
                    StorybookSeenTracker.shared.markCompletedSeen(jobId: newBookId)
                }
            }
            .onChange(of: profileVM.selectedProfile.id) { _, newProfileID in
                print("🧭 StoryPage profile changed to \(newProfileID.uuidString); reloading storybook")
                Task { @MainActor in
                    let resuming = await vm.resumeInProgressGenerationIfMarkerExists(
                        profileID: profileVM.selectedProfile.id,
                        profileName: profileVM.selectedProfile.name,
                        profileEthnicity: profileVM.selectedProfile.ethnicity
                    )
                    if resuming {
                        hasRequestedGeneration.wrappedValue = true
                    } else {
                        vm.loadStorybookForProfile(
                            newProfileID,
                            name: profileVM.selectedProfile.name,
                            profileEthnicity: profileVM.selectedProfile.ethnicity
                        )
                        hasRequestedGeneration.wrappedValue = vm.hasGeneratedStorybook
                    }
                    if let image = StorybookHeadshotOverride.resolvedHeadshot(profilePhotoData: profileVM.selectedProfile.photoData) {
                        headshotImage.wrappedValue = image
                        vm.subjectPhoto = image
                    } else {
                        headshotImage.wrappedValue = nil
                        vm.subjectPhoto = nil
                    }
                    vm.syncFaceDescriptionFromProfile(profileVM.selectedProfile)
                    updateIncompleteCount()
                }
            }
            .onChange(of: vm.isLoading) { _, _ in }
            .onChange(of: headshotImage.wrappedValue) { _, newShot in
                vm.subjectPhoto = newShot
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
