import SwiftUI
import UIKit
import PhotosUI
import Combine
import RevenueCat
import RevenueCatUI
import CoreData
import FirebaseAuth

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
    let softCream = LinenTheme.paper
    let terracotta = LinenTheme.accent
    let defaultBlack = LinenTheme.ink
    let defaultGray = LinenTheme.secondary
    let defaultRed = Color.red
    let defaultWhite = Color.white
    let arrowColor = Color.white.opacity(0.9)
    let subtleControlBackground = LinenTheme.surface
    let shadowColor = Color.black.opacity(0.15)
    let bookFrameFill = LinenTheme.card
    let bookFrameStroke = LinenTheme.line
    let fullScreenOverlayBackground = Color.black.opacity(0.85)
    
    // Book-specific colors - elegant and clean
    let bookPageBackground = BookInteriorStyle.paper // Warm paper white
    let bookTextColor = BookInteriorStyle.ink // Soft black for readability
    let chapterTitleColor = BookInteriorStyle.ink // Elegant brown
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
    
    func titleFont(for frameHeight: CGFloat) -> Font {
        .custom("GillSans", size: frameHeight * 0.040)
    }

    func bodyFont(for frameHeight: CGFloat) -> Font {
        .custom("Georgia", size: frameHeight * BookInteriorStyle.bodySize)
    }

    func pageNumberFont(for frameHeight: CGFloat) -> Font {
        .custom("GillSans", size: frameHeight * 0.015)
    }
}

// MARK: - QR Watermark Component
/// QR code overlay for illustration pages. Use `topInset` to keep it below the Kids book title bar.
struct QRWatermark: View {
    let memoryID: UUID
    /// When non-zero (e.g. Kids book bar height), QR sits below this so it doesn't overlap the top bar.
    var topInset: CGFloat = 0
    var qrSide: CGFloat = 60
    var imagePadding: CGFloat = 8
    var trailingPadding: CGFloat = 12
    var topPadding: CGFloat = 8
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: topInset)
            HStack {
                Spacer()
                // Frosted background for visibility on any image (black, white, etc.)
                Image(uiImage: StoryPageViewModel.qrCode(
                    from: MemoryLinks.universalLink(memoryID: memoryID).absoluteString,
                    size: qrSide
                ))
                .interpolation(.none)
                .resizable()
                .frame(width: qrSide, height: qrSide)
                .padding(imagePadding)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.trailing, trailingPadding)
            .padding(.top, topPadding)
            Spacer()
        }
    }
}

struct PreparedPageEditorRequest: Identifiable {
    let id = UUID()
    let target: StorybookEditablePageTarget
    let pageIndex: Int
    let pageID: String
    let memoryID: UUID
    let document: BookPageDocument
    let canReset: Bool
    let isLandscape: Bool
    let isIllustration: Bool
    let showsChrome: Bool
}

// Enhanced font system with distinct styles
extension Font {
    static func storyPageSerifFont(size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }
    
    // Kids book fonts - Times New Roman 12pt for publisher standard (11×8.5" print)
    static func kidsBookTitleFont(for frameHeight: CGFloat) -> Font {
        .custom("GillSans", size: frameHeight * 0.040)
    }
    
    static func kidsBookBodyFont(for frameHeight: CGFloat) -> Font {
        .custom("Georgia", size: frameHeight * BookInteriorStyle.bodySize)
    }
    
    static func kidsBookPageNumberFont(for frameHeight: CGFloat) -> Font {
        .custom("GillSans", size: frameHeight * 0.015)
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
    @State private var setupProfileID: UUID?
    @State private var setupUserID: String?
    @State private var showMemoirNamePrompt = false
    @State private var memoirNameDraft = ""
    @State private var memoirNameProfileID: UUID?
    @State private var memoirNameUserID: String?
    @State private var continueGenerationAfterName = false
    @State private var showProfileSetup: Bool = false
    @State private var didCompleteProfileSetup: Bool = false // Track if user completed setup or just exited
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = StoryPageViewModel()
    
    @State private var headshotPickerItem: PhotosPickerItem?
    @State private var gender: String = ""
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @Environment(\.storybookScreenEntry) private var storybookScreenEntry
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var userRace: String = ""
    @StateObject private var subscriptionManager = RCSubscriptionManager.shared
    
    let localColors = StoryPageLocalColors()
    
    @State private var currentPageIndex = 0
    @State private var showSettings = false
    @State private var showGallery = false
    @State private var selectedImageForFullScreen: UIImage? = nil
    @State private var hasRequestedGeneration = false
    @State private var isOpeningBook = true
    @State private var pageEditorRequest: PreparedPageEditorRequest? = nil
    @State private var isPreparingPageEditor = false
    @State private var showCoverEditor = false
    @State private var showCoverPDFMissingAlert = false
    
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
    @State private var showInteriorUpgradeConfirmation = false
    @State private var confirmedInteriorUpgradeBookID: String?
    @State private var isOrderPreparing = false
    @State private var orderNotReadyAlert = false
    @State private var orderNotReadyAlertTitle = "Book PDF Still Preparing"
    @State private var orderNotReadyAlertMessage = ""
    @State private var showSkippedMemoriesExplanation = false
    @State private var debugSessionID: String = String(UUID().uuidString.prefix(8))
    /// When free preview is exhausted, tutorial may allow one bonus image (tracked separately from `FreePreviewConfig`).
    @State private var pendingTutorialBonusGeneration: Bool = false
    @State private var isCheckingSubscription = false
    
    @Environment(\.managedObjectContext) private var context
    
    // NEW: Subscription check - exactly like MemoirView
    private var isSubscribed: Bool {
        subscriptionManager.hasActiveSubscription
    }
    
    // MARK: - Incomplete Memories Banner Component
    @ViewBuilder
    private func incompleteMemoriesBanner() -> some View {
        if incompleteCount > 0 {
            Button(action: { navigateToRecent = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundColor(LinenTheme.accent)
                    Text("\(incompleteCount) \(incompleteCount == 1 ? "memory" : "memories") can be enhanced")
                        .font(LinenTheme.body(14))
                        .foregroundColor(LinenTheme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(LinenTheme.secondary)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(LinenTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens saved stories to add more detail")
        }
    }

    private var isShowingOpeningBook: Bool {
        StorybookPagePresentationPolicy.shouldShowEntryLoading(
            isOpeningBook: isOpeningBook,
            resumesPendingGeneration: storybookScreenEntry.resumesPendingGeneration,
            hasLoadedBook: vm.hasGeneratedStorybook && !vm.pageItems.isEmpty
        ) || StorybookPagePresentationPolicy.shouldShowProfileLoadingOverlay(
            isLoadingProfileBook: vm.isLoadingProfileBook,
            hasLoadedBook: StorybookPagePresentationPolicy.shouldShowLoadedBook(
                hasGeneratedStorybook: vm.hasGeneratedStorybook,
                pageCount: vm.pageItems.count
            ),
            hasCanonicalBookMetadata: vm.currentBookVersionRecord != nil
        )
    }

    @ViewBuilder
    private func storybookContentView(
        bookFrameWidth: CGFloat,
        bookContentHeightInsideFrame: CGFloat
    ) -> some View {
        let hasLoadedBook = StorybookPagePresentationPolicy.shouldShowLoadedBook(
            hasGeneratedStorybook: vm.hasGeneratedStorybook,
            pageCount: vm.pageItems.count
        )
        if vm.isLoading {
            makeLoadingView()
        } else if isShowingOpeningBook {
            makeOpeningLibraryBookView(isLibrarySelection: true)
        } else if vm.isLoadingGalleryBook {
            makeOpeningLibraryBookView(isLibrarySelection: true)
        } else if hasLoadedBook && vm.requiresVisualReadyGate && !vm.isVisualBookReady {
            makeFinalizingAssetsView()
        } else if let error = vm.errorMessage {
            makeErrorView(error: error)
        } else if hasLoadedBook {
            makeBookContent(bookFrameWidth: bookFrameWidth, bookContentHeightInsideFrame: bookContentHeightInsideFrame)
        } else {
            makeEmptyStateView()
        }
    }
    
    @ViewBuilder
    private func makeLoadingView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(LinenTheme.forest)
            Text("Creating your book")
                .font(LinenTheme.heading(22))
                .foregroundColor(LinenTheme.ink)
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

            Text("Your memories are becoming a book.")
                .font(LinenTheme.body(13))
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
    private func makeOpeningLibraryBookView(isLibrarySelection: Bool) -> some View {
        let copy = StorybookPagePresentationPolicy.loadingCopy(isLibrarySelection: isLibrarySelection)
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: localColors.terracotta))
                .scaleEffect(1.15)
            Text(copy.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(localColors.terracotta)
            Text(copy.subtitle)
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
                    Text(subscriptionManager.isDeveloperUnlockedSession ? "Unlimited images" : "Images remaining: \(subscriptionManager.remainingAllowance)/100")
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
        let contentWidth = bookFrameWidth
        let contentHeight = bookContentHeightInsideFrame
        
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
        let slots = StorybookReaderSlotPolicy.slots(
            interiorPageCount: vm.pageItems.count,
            hasExteriorCover: vm.hasPrintCoverPDF
        )
        TabView(selection: $currentPageIndex) {
            ForEach(Array(slots.enumerated()), id: \.offset) { readerIndex, slot in
                let renderScale = min(
                    contentWidth / max(printSpec.widthPt, 1),
                    contentHeight / max(printSpec.heightPt, 1)
                )
                Group {
                    switch slot {
                    case .cover(let panel):
                        exteriorCoverPage(
                            panel: panel,
                            width: printSpec.widthPt,
                            height: printSpec.heightPt
                        )
                        .onTapGesture { openEditor(for: slot) }
                    case .interiorPage(let pageIndex):
                        pageView(
                            for: vm.pageItems[pageIndex],
                            at: pageIndex,
                            frameWidth: printSpec.widthPt,
                            frameHeight: printSpec.heightPt
                        )
                        .onTapGesture { openEditor(for: slot) }
                    }
                }
                .frame(width: printSpec.widthPt, height: printSpec.heightPt)
                .scaleEffect(renderScale, anchor: .center)
                .frame(width: contentWidth, height: contentHeight)
                .tag(readerIndex)
            }
        }
        .id(vm.tabViewCoverRefreshIdentity)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: contentWidth, height: contentHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func exteriorCoverPage(panel: BookCoverFlatPanel, width: CGFloat, height: CGFloat) -> some View {
        if let record = vm.currentBookVersionRecord,
           let url = record.printCoverPDFURL {
            RemotePDFThumbnailView(
                url: url,
                targetSize: CGSize(width: width * 2, height: height * 2),
                layout: record.coverFlatLayoutKind,
                panel: panel,
                cacheRevision: record.coverThumbnailCacheRevision,
                cacheIdentity: record.coverStoragePath ?? ""
            ) {
                fallbackExteriorCover(panel: panel, width: width, height: height)
            }
        } else {
            fallbackExteriorCover(panel: panel, width: width, height: height)
        }
    }

    @ViewBuilder
    private func fallbackExteriorCover(panel: BookCoverFlatPanel, width: CGFloat, height: CGFloat) -> some View {
        if panel == .front {
            MemoirCoverFrontPage(
                title: vm.bookDisplayTitle,
                subtitle: "",
                frameWidth: width,
                frameHeight: height,
                isKidsBook: vm.currentArtStyle == .kidsBook
            )
        } else {
            MemoirCoverBackPage(
                subtitle: vm.backCoverPitch,
                frameWidth: width,
                frameHeight: height
            )
        }
    }

    private var readerSlots: [StorybookReaderSlot] {
        StorybookReaderSlotPolicy.slots(
            interiorPageCount: vm.pageItems.count,
            hasExteriorCover: vm.hasPrintCoverPDF
        )
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
        if readerSlots.indices.contains(currentPageIndex),
           case .interiorPage(let pageIndex) = readerSlots[currentPageIndex],
           vm.isEditingImage(at: pageIndex) {
                makeLoadingOverlay()
                    .transition(.opacity)
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
        if readerSlots.count > 1 {
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
        .accessibilityIdentifier("storybookPreviousPage")
    }
    
    @ViewBuilder
    private func makeNextButton() -> some View {
        Button {
            if currentPageIndex < readerSlots.count - 1 {
                withAnimation(.easeInOut) { currentPageIndex += 1 }
            }
        } label: {
            Image(systemName: "arrow.right.circle.fill")
                .shadow(radius: 3)
        }
        .disabled(currentPageIndex == readerSlots.count - 1)
        .opacity(currentPageIndex == readerSlots.count - 1 ? 0.3 : 1.0)
        .accessibilityIdentifier("storybookNextPage")
    }
    
    @ViewBuilder
    private func makeEmptyStateView() -> some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinenTheme.surface)
                VStack(spacing: 10) {
                    Text("MEMOIR")
                        .font(LinenTheme.body(10, weight: .semibold))
                        .tracking(2)
                    Image("LinenJourney")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 156, height: 76)
                        .clipped()
                    Text("Your stories, together.")
                        .font(LinenTheme.heading(16))
                }
                .foregroundColor(LinenTheme.ink)
                .frame(width: 210, height: 210 * 8.5 / 11)
                .background(LinenTheme.paper)
                .overlay(alignment: .leading) {
                    Rectangle().fill(LinenTheme.line).frame(width: 6)
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 6, topTrailingRadius: 6))
                .shadow(color: LinenTheme.ink.opacity(0.14), radius: 5, x: 3, y: 5)
                .rotationEffect(.degrees(-4))
            }
            .frame(height: 180)
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("A book of your memories")
                    .font(LinenTheme.heading())
                    .foregroundColor(LinenTheme.ink)
                Text("Choose the stories you want to keep together, then make them into an illustrated book.")
                    .font(LinenTheme.body(14))
                    .foregroundColor(LinenTheme.secondary)
            }
            .multilineTextAlignment(.center)

            Button(action: { prepareStorybookSetup() }) {
                Text("Create a book")
                    .font(LinenTheme.body(16, weight: .semibold))
                    .foregroundColor(LinenTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 55)
                    .background(LinenTheme.accent, in: RoundedRectangle(cornerRadius: 14))
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

            if incompleteCount > 0 {
                incompleteMemoriesBanner()
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 8)
    }

    private func prepareStorybookSetup() {
        didCompleteProfileSetup = false
        setupProfileID = profileVM.selectedProfile.id
        setupUserID = Auth.auth().currentUser?.uid
        guard ensureMemoirName(continueGeneration: false) else { return }
        showProfileSetup = true
    }

    private func ensureMemoirName(continueGeneration: Bool) -> Bool {
        let profile = profileVM.selectedProfile
        var resolvedName = StorybookMemoirNamePolicy.usableName(profile.name)
        if resolvedName == nil {
            let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
            request.predicate = MemoryUserScope.profilePredicate(profileID: profile.id)
            do {
                resolvedName = vm.memoirName(profileName: profile.name, memories: try context.fetch(request))
            } catch {
                vm.errorMessage = "Your saved memories could not be read. Try again before creating the book."
                return false
            }
        }
        if let resolvedName {
            if profile.name != resolvedName { profileVM.updateName(for: profile, to: resolvedName) }
            grandparentName = resolvedName
            return true
        }
        memoirNameDraft = ""
        memoirNameProfileID = profile.id
        memoirNameUserID = Auth.auth().currentUser?.uid
        continueGenerationAfterName = continueGeneration
        showMemoirNamePrompt = true
        return false
    }

    private func saveMemoirName() {
        guard let profileID = memoirNameProfileID,
              profileVM.selectedProfile.id == profileID,
              Auth.auth().currentUser?.uid == memoirNameUserID,
              let profile = profileVM.profiles.first(where: { $0.id == profileID }),
              let name = StorybookMemoirNamePolicy.usableName(memoirNameDraft) else { return }
        profileVM.updateName(for: profile, to: name)
        grandparentName = name
        memoirNameProfileID = nil
        if continueGenerationAfterName {
            generateStorybookWithPaywallCheck()
        } else {
            showProfileSetup = true
        }
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
        guard !isCheckingSubscription else { return }
        guard ensureMemoirName(continueGeneration: true) else { return }
        let generationProfileID = profileVM.selectedProfile.id
        guard let firebaseUserID = Auth.auth().currentUser?.uid else {
            vm.errorMessage = "Sign in before creating a storybook. Your memories are still saved on this device."
            return
        }
        isCheckingSubscription = true
        vm.isLoading = true
        vm.currentStatus = "Verifying subscription…"
        Task { @MainActor in
            defer { isCheckingSubscription = false }
            await subscriptionManager.refreshCustomerInfo(forceRefresh: true)
            vm.isLoading = false
            guard profileVM.selectedProfile.id == generationProfileID else { return }
            guard Auth.auth().currentUser?.uid == firebaseUserID,
                  subscriptionManager.isIdentityReady(for: firebaseUserID) else {
                vm.errorMessage = subscriptionManager.identityErrorMessage
                    ?? "Subscription verification did not finish. Check your connection and try again."
                return
            }
            if !subscriptionManager.hasActiveSubscription,
               let error = subscriptionManager.activationErrorMessage {
                vm.errorMessage = error
                return
            }
            generateStorybookAfterSubscriptionCheck()
        }
    }

    private func generateStorybookAfterSubscriptionCheck() {
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

        let generationProfile = profileVM.selectedProfile
        let currentProfileID = generationProfile.id
        let finalPageCount = pagesExpected // Pass the adjusted page count
        let wasSubscribed = isSubscribed // Capture subscription state before async
        let useTutorialBonus = pendingTutorialBonusGeneration
        
        Task { @MainActor in
            vm.syncFaceDescriptionFromProfile(generationProfile)
            await vm.generateStorybook(
                forProfileID: currentProfileID,
                profileName: generationProfile.name,
                overridePageCount: finalPageCount,
                profileEthnicity: userRace
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
        
        return mainContent
            .analyticsScreen("book")
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
            showCoverEditor: $showCoverEditor,
            storybookScreenEntry: storybookScreenEntry,
            isOpeningBook: $isOpeningBook
        )
        .alert("Whose memoir is this?", isPresented: $showMemoirNamePrompt) {
            TextField("Person’s name", text: $memoirNameDraft)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("memoirNameInput")
            Button("Cancel", role: .cancel) { memoirNameProfileID = nil }
            Button("Save & Continue") { saveMemoirName() }
                .disabled(StorybookMemoirNamePolicy.usableName(memoirNameDraft) == nil)
        } message: {
            Text("Enter their name for the book title. We’ll save it to this profile.")
        }
        .onChange(of: vm.pageItems.count) { _, _ in
            currentPageIndex = StorybookPagePresentationPolicy.clampedPageIndex(
                currentPageIndex,
                pageCount: readerSlots.count
            )
        }
        .fullScreenCover(item: $pageEditorRequest) { request in
            PreparedBookPageEditorHost(
                request: request,
                vm: vm,
                onDismiss: { pageEditorRequest = nil }
            )
        }
        .alert("Print cover not ready", isPresented: $showCoverPDFMissingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Wait until your cover PDF has finished generating and synced, then try again. You can also open the book from My Library once the cover appears there.")
        }
        .fullScreenCover(item: $orderBookRecordForSheet) { record in
            OrderBookView(book: record)
        }
        .alert("Update book layout?", isPresented: $showInteriorUpgradeConfirmation) {
            Button("Cancel", role: .cancel) { confirmedInteriorUpgradeBookID = nil }
            Button("Update & Continue") {
                confirmedInteriorUpgradeBookID = vm.currentBookVersionRecord?.bookVersionId
                orderBookTapped()
            }
        } message: {
            Text("We’ll save a new copy with the updated interior so your printed book matches this preview. Your original book and previous orders stay saved.")
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
        GeometryReader { geometry in
            let usesCompactChrome = AdaptiveLayoutPolicy.usesCompactVerticalChrome(
                width: geometry.size.width,
                height: geometry.size.height,
                verticalSizeClass: verticalSizeClass
            )

            ZStack {
                localColors.softCream
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    makeHeader(usesCompactChrome: usesCompactChrome)
                    makeStorybookContentArea()
                    makeBottomActionArea(usesCompactChrome: usesCompactChrome)
                        .opacity(isShowingOpeningBook ? 0 : 1)
                        .allowsHitTesting(!isShowingOpeningBook)
                        .accessibilityHidden(isShowingOpeningBook)
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: usesCompactChrome ? 0 : 5)
                }
            }
        }
    }
    
    @ViewBuilder
    private func makeHeader(usesCompactChrome: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    makeBackButton()
                    Text(hasGeneratedStorybook ? "Read book" : "Your Book")
                        .font(LinenTheme.heading())
                        .foregroundColor(LinenTheme.ink)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    makeHeaderButtons(horizontal: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        makeBackButton()
                        Spacer(minLength: 0)
                        makeHeaderButtons(horizontal: true)
                    }
                    Text(hasGeneratedStorybook ? "Read book" : "Your Book")
                        .font(LinenTheme.heading())
                        .foregroundColor(LinenTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !usesCompactChrome, subscriptionManager.hasActiveSubscription {
                makeSubscriptionButton()
                    .padding(.leading, 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, usesCompactChrome ? 6 : 10)
        .padding(.bottom, usesCompactChrome ? 6 : 16)
    }

    @ViewBuilder
    private func makeBackButton() -> some View {
        Button(action: { dismiss() }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(localColors.defaultBlack.opacity(0.7))
                .frame(width: 44, height: 44)
                .background(localColors.subtleControlBackground)
                .clipShape(Circle())
        }
        .accessibilityLabel("Back")
    }
    
    @ViewBuilder
    private func makeSubscriptionButton() -> some View {
        Button(action: {
            showSubscriptionTooltip = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                showSubscriptionTooltip = false
            }
        }) {
            Text(subscriptionManager.isDeveloperUnlockedSession ? "Unlimited images" : "\(subscriptionManager.remainingAllowance)/100 images")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(subscriptionManager.remainingAllowance <= 5 ? .red : .gray)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private func makeHeaderButtons(horizontal: Bool) -> some View {
        Group {
            if horizontal {
                HStack(spacing: 6) {
                    makeHeaderButtonItems()
                }
            } else {
                VStack(spacing: 8) {
                    makeHeaderButtonItems()
                }
            }
        }
        .frame(minWidth: 44)
        .opacity(isShowingOpeningBook ? 0 : 1)
        .allowsHitTesting(!isShowingOpeningBook)
        .accessibilityHidden(isShowingOpeningBook)
    }

    @ViewBuilder
    private func makeHeaderButtonItems() -> some View {
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
            } else {
                makeSettingsButton()
            }

            makeGalleryButton()
    }

    private var hasGeneratedStorybook: Bool {
        StorybookPagePresentationPolicy.shouldShowLoadedBook(
            hasGeneratedStorybook: vm.hasGeneratedStorybook,
            pageCount: vm.pageItems.count
        )
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
                .frame(width: 44, height: 44)
                .background(localColors.subtleControlBackground)
                .clipShape(Circle())
        }
        .accessibilityLabel("Book library")
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
            .frame(width: 44, height: 44)
            .background(localColors.subtleControlBackground)
            .clipShape(Circle())
        }
        .accessibilityLabel("Export book")
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
                .frame(width: 44, height: 44)
                .background(localColors.subtleControlBackground)
                .clipShape(Circle())
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("storybookSettingsButton")
    }
    
    @ViewBuilder
    private func makeStorybookContentArea() -> some View {
        GeometryReader { geo in
            if vm.isLoading || isShowingOpeningBook || vm.isLoadingGalleryBook
                || (hasGeneratedStorybook && vm.requiresVisualReadyGate && !vm.isVisualBookReady)
                || vm.errorMessage != nil || !hasGeneratedStorybook {
                ScrollView {
                    storybookContentView(
                        bookFrameWidth: max(0, geo.size.width - 48),
                        bookContentHeightInsideFrame: max(0, geo.size.height - 32)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, geo.size.height - 32), alignment: hasGeneratedStorybook || vm.isLoading ? .center : .top)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            } else {
                makeBookFrame(geo: geo)
            }
        }
    }
    
    @ViewBuilder
    private func makeBookFrame(geo: GeometryProxy) -> some View {
        let printSpec = vm.currentPrintSpec
        let exportAspectRatio = printSpec.aspectRatio
        let cardInset: CGFloat = geo.size.height < 520 ? 12 : 16
        let availableContentSize = CGSize(
            width: max(0, geo.size.width * 0.94 - cardInset * 2),
            height: max(0, geo.size.height * 0.90 - cardInset * 2)
        )
        let pageSize = AdaptiveLayoutPolicy.aspectFitSize(
            aspectRatio: exportAspectRatio,
            inside: availableContentSize
        )
        let bookFrameWidth = pageSize.width + cardInset * 2
        let bookFrameHeight = pageSize.height + cardInset * 2
        let bookFrameX = geo.size.width / 2
        let bookFrameY = (geo.size.height / 2) + 4
        
        ZStack {
            makeBookPreviewBox(
                bookFrameWidth: bookFrameWidth,
                bookFrameHeight: bookFrameHeight,
                bookContentAreaWidth: pageSize.width,
                bookContentHeightInsideFrame: pageSize.height,
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
    private func makeBottomActionArea(usesCompactChrome: Bool) -> some View {
        if hasRequestedGeneration && !vm.pageItems.isEmpty && !vm.isLoading && (!vm.requiresVisualReadyGate || vm.isVisualBookReady) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                if canEditCurrentPage {
                    compactStorybookAction(
                        title: isPreparingPageEditor ? "Opening…" : "Edit",
                        systemImage: isPreparingPageEditor ? nil : "pencil",
                        filled: false,
                        action: handleCurrentPageEditTapped
                    )
                    .accessibilityIdentifier("storybookEditCurrentPage")
                    .disabled(isPreparingPageEditor)
                }
                compactStorybookAction(title: "New Book", systemImage: "plus", filled: false, action: { showRegenerateConfirmation = true })
                compactStorybookAction(
                    title: "Order",
                    systemImage: isOrderPreparing ? nil : "printer",
                    filled: true,
                    showsProgress: isOrderPreparing,
                    action: orderBookTapped
                )
                .disabled(isOrderPreparing || vm.isSavingBookRevision || vm.isUploadingToCloud)
                .opacity((isOrderPreparing || vm.isSavingBookRevision || vm.isUploadingToCloud) ? 0.7 : 1.0)
                }

                HStack(spacing: 8) {
                    if canEditCurrentPage {
                        compactStorybookAction(
                            title: isPreparingPageEditor ? "Opening…" : "Edit",
                            systemImage: nil,
                            filled: false,
                            action: handleCurrentPageEditTapped
                        )
                            .accessibilityIdentifier("storybookEditCurrentPage")
                            .disabled(isPreparingPageEditor)
                    }
                    compactStorybookAction(title: "New", systemImage: "plus", filled: false, action: { showRegenerateConfirmation = true })
                    compactStorybookAction(title: "Order", systemImage: isOrderPreparing ? nil : "printer", filled: true, showsProgress: isOrderPreparing, action: orderBookTapped)
                        .disabled(isOrderPreparing || vm.isSavingBookRevision || vm.isUploadingToCloud)
                }
            }
            .padding(.horizontal, usesCompactChrome ? 12 : 24)
            .padding(.vertical, 10)
            .adaptiveContentWidth(AdaptiveLayoutPolicy.workflowMaxWidth)
        }
    }

    private func compactStorybookAction(
        title: String,
        systemImage: String?,
        filled: Bool,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showsProgress {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(LinenTheme.body(15, weight: .semibold))
            .foregroundColor(filled ? LinenTheme.onAccent : LinenTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(filled ? LinenTheme.accent : LinenTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func orderBookTapped() {
        guard !isOrderPreparing, !vm.isSavingBookRevision, !vm.isUploadingToCloud else { return }
        let retryingInteriorUpgrade = confirmedInteriorUpgradeBookID != nil
            && confirmedInteriorUpgradeBookID == vm.currentBookVersionRecord?.bookVersionId
        guard !vm.hasUnpublishedBookChanges || retryingInteriorUpgrade else {
            orderNotReadyAlertTitle = "Unsaved Book Changes"
            orderNotReadyAlertMessage = "Your latest edit has not synced yet. Check your connection, save it again, and then order."
            orderNotReadyAlert = true
            return
        }
        isOrderPreparing = true
        Task {
            _ = await vm.fetchCurrentBookVersionRecord()
            if let record = vm.currentBookVersionRecord,
               BookInteriorUpgradePolicy.needsUpdate(layoutVersion: record.layoutVersion) {
                guard confirmedInteriorUpgradeBookID == record.bookVersionId else {
                    isOrderPreparing = false
                    showInteriorUpgradeConfirmation = true
                    return
                }
                let saved = await vm.saveCurrentBookInPlace(reason: "interiorDesignUpdate")
                guard saved, BookInteriorUpgradePolicy.canOrderPublishedUpdate(
                    previousBookID: record.bookVersionId,
                    record: vm.currentBookVersionRecord,
                    hasUnpublishedChanges: vm.hasUnpublishedBookChanges
                ) else {
                    isOrderPreparing = false
                    orderNotReadyAlertTitle = "Book Update Not Ready"
                    orderNotReadyAlertMessage = "Your original book is safe. Check your connection and retry to publish the updated copy before ordering."
                    orderNotReadyAlert = true
                    return
                }
                confirmedInteriorUpgradeBookID = nil
            }
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
        guard readerSlots.indices.contains(currentPageIndex) else { return }
        openEditor(for: readerSlots[currentPageIndex])
    }

    private func openEditor(for slot: StorybookReaderSlot) {
        switch StorybookPageEditDestinationPolicy.target(for: slot) {
        case .interiorPage(let pageIndex):
            handleInteriorPageEditTapped(at: pageIndex)
        case .exteriorCover(let panel):
            handleExteriorCoverEditTapped(panel: panel)
        }
    }

    private func handleInteriorPageEditTapped(at pageIndex: Int) {
        guard vm.pageItems.indices.contains(pageIndex), !isPreparingPageEditor else { return }
        let item = vm.pageItems[pageIndex]
        let pageID = item.id
        let hadExistingLayout = vm.freeformDocument(at: pageIndex) != nil
        isPreparingPageEditor = true
        Task {
            defer { isPreparingPageEditor = false }
            do {
                let document = try await vm.makeEditableFreeformDocument(at: pageIndex)
                guard vm.pageID(at: pageIndex) == pageID else {
                    throw BookPageEditorPersistenceError.pageChanged
                }
                pageEditorRequest = PreparedPageEditorRequest(
                    target: .interiorPage(pageIndex),
                    pageIndex: pageIndex,
                    pageID: pageID,
                    memoryID: item.memoryID,
                    document: document,
                    canReset: hadExistingLayout,
                    isLandscape: vm.currentPrintSpec.orientation == "landscape",
                    isIllustration: {
                        if case .illustration = item { return true }
                        return false
                    }(),
                    showsChrome: !BookInteriorAnchor.isNonMemoryPage(item.memoryID)
                        && !vm.isPrecomposedIllustration(memoryID: item.memoryID)
                )
            } catch {
                vm.errorMessage = error.localizedDescription
            }
        }
    }

    private func handleExteriorCoverEditTapped(panel: BookCoverFlatPanel) {
        guard !isPreparingPageEditor else { return }
        isPreparingPageEditor = true
        Task {
            defer { isPreparingPageEditor = false }
            do {
                let document = try await vm.makeEditableExteriorCoverDocument(panel: panel)
                pageEditorRequest = PreparedPageEditorRequest(
                    target: .exteriorCover(panel),
                    pageIndex: 0,
                    pageID: "cover:\(panel)",
                    memoryID: BookInteriorAnchor.blankPageMemoryId,
                    document: document,
                    canReset: false,
                    isLandscape: vm.currentPrintSpec.orientation == "landscape",
                    isIllustration: false,
                    showsChrome: false
                )
            } catch {
                vm.errorMessage = error.localizedDescription
            }
        }
    }

    private var canEditCurrentPage: Bool {
        readerSlots.indices.contains(currentPageIndex)
    }
    
    private func handleProfileSetupDismiss() {
        guard setupProfileID == profileVM.selectedProfile.id,
              setupUserID == Auth.auth().currentUser?.uid else {
            didCompleteProfileSetup = false
            return
        }
        if didCompleteProfileSetup {
            generateStorybookWithPaywallCheck()
            didCompleteProfileSetup = false
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
                    try? FileManager.default.removeItem(at: pdfURL)
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
                    try? FileManager.default.removeItem(at: pdfURL)
                    self.isDownloading = false
                }
            }
        }
    }
    
    // NEW: Regenerate functionality
    private func regenerateStorybook() {
        // Route through the same setup path as first-time creation:
        // ProfileSetupView -> Review Settings -> Save & Generate.
        prepareStorybookSetup()
    }
    
    // MARK: – Helper to count memories needing enhancement
    private func updateIncompleteCount() {
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
                print("  - Unenhanced memory detected")
            }
        } else {
            print("❌ StoryPage: Failed to fetch memories")
            incompleteCount = 0
        }
    }

    /// Instruction-based edit for print cover PDF panels (front / back), matching interior `ImageEditSheet` UX.
    struct CoverArtEditSheet: View {
        let panel: BookCoverFlatPanel
        let record: BookVersionRecord?
        @Binding var revisionText: String
        @Binding var isPresented: Bool
        let onSend: (String) -> Void
        let isEditing: Bool
        let onEditTitleBlurb: () -> Void

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

        private var previewAspectRatio: CGFloat {
            AdaptiveLayoutPolicy.validatedAspectRatio(
                width: record?.pageWidth ?? 11,
                height: record?.pageHeight ?? 8.5,
                fallback: 11 / 8.5
            )
        }

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(panelTitle)
                            .font(.headline)
                        Text("Preview the current cover, then describe one clear change.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close cover editor")
                    .accessibilityIdentifier("coverEditorClose")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                GeometryReader { geometry in
                    let previewSize = AdaptiveLayoutPolicy.aspectFitSize(
                        aspectRatio: previewAspectRatio,
                        inside: geometry.size
                    )

                    coverPreview
                        .frame(width: previewSize.width, height: previewSize.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                Button(action: onEditTitleBlurb) {
                    Text("Edit book title & back cover text")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(localColors.terracotta)
                    }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Describe the changes you want...", text: $revisionText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(.leading, 4)
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
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        }

        @ViewBuilder
        private var coverPreview: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.965, green: 0.94, blue: 0.89))

                if let record,
                   let url = record.printCoverPDFURL {
                    RemotePDFThumbnailView(
                        url: url,
                        targetSize: CGSize(width: 1_200, height: 900),
                        layout: record.coverFlatLayoutKind,
                        panel: panel,
                        cacheRevision: record.coverThumbnailCacheRevision,
                        cacheIdentity: record.coverStoragePath ?? ""
                    ) {
                        Color(red: 0.965, green: 0.94, blue: 0.89)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 30))
                        Text("Cover preview unavailable")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                if isEditing {
                    Color.black.opacity(0.28)
                    ProgressView("Updating cover…")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .aspectRatio(previewAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .accessibilityLabel(panel == .front ? "Current front cover preview" : "Current back cover preview")
        }
    }
}

// MARK: - Page View Selection Logic
extension StoryPage {
    @ViewBuilder
    private func pageView(for item: StoryPageViewModel.PageItem, at index: Int, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        let isKidsBook = vm.currentArtStyle == .kidsBook
        if let freeformPage = vm.freeformPageView(
            at: index,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        ) {
            freeformPage
        } else {
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
                // Keep the memory link below the illustration title.
                QRWatermark(
                    memoryID: memoryID,
                    topInset: frameHeight * (isKidsBook ? 0.10 : 0.065) + 6
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
            fallbackFrontCover
        } else if memoryID == BookInteriorAnchor.blankPageMemoryId {
            MemoirBlankPage(frameWidth: frameWidth, frameHeight: frameHeight)
        } else if memoryID == BookInteriorAnchor.closingPageMemoryId {
            fallbackBackCover
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

        }
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
    @State private var isSaving = false
    @State private var saveError: String?

    private let paper = Color(red: 0.98, green: 0.96, blue: 0.89)
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    private let ink = Color.black.opacity(0.84)

    private var canSave: Bool {
        !titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    private var titlePageSubtitle: String {
        for item in vm.pageItems {
            if case .textPage(_, _, let text, _, _, let memoryID) = item,
               memoryID == BookInteriorAnchor.titlePageMemoryId {
                return text
            }
        }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(ink.opacity(0.7))
                    .disabled(isSaving)

                Spacer()

                Text("Edit Book Details")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)

                Spacer()

                Button {
                    isSaving = true
                    Task {
                        let succeeded = await vm.updateCoverCopy(
                            title: titleDraft,
                            backCoverPitch: pitchDraft
                        )
                        isSaving = false
                        if succeeded {
                            dismiss()
                        } else {
                            saveError = "The book changes could not be published. Check your connection and try again."
                        }
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 42)
                    } else {
                        Text("Save")
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(canSave ? terracotta : Color.gray.opacity(0.45), in: Capsule())
                .disabled(!canSave)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GeometryReader { geometry in
                        let spec = vm.currentPrintSpec
                        let previewSize = AdaptiveLayoutPolicy.aspectFitSize(
                            aspectRatio: spec.aspectRatio,
                            inside: geometry.size
                        )
                        let scale = min(
                            previewSize.width / max(spec.widthPt, 1),
                            previewSize.height / max(spec.heightPt, 1)
                        )
                        MemoirCoverFrontPage(
                            title: titleDraft,
                            subtitle: titlePageSubtitle,
                            frameWidth: spec.widthPt,
                            frameHeight: spec.heightPt,
                            isKidsBook: vm.currentArtStyle == .kidsBook
                        )
                        .scaleEffect(scale)
                        .frame(width: previewSize.width, height: previewSize.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 240)
                    .accessibilityIdentifier("storybookCoverCopyPreview")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Book title")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ink.opacity(0.68))
                    TextField("Memoir title", text: $titleDraft)
                        .textInputAutocapitalization(.words)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .padding(14)
                        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Printed back-cover blurb")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ink.opacity(0.68))
                        TextEditor(text: $pitchDraft)
                            .font(.system(size: 15, design: .serif))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 128)
                            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
                        Text("This appears only on the printed book cover, not the closing Memoir credit page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(paper.ignoresSafeArea())
        .accessibilityIdentifier("storybookCoverCopyEditor")
        .interactiveDismissDisabled(isSaving)
        .alert(
            "Couldn’t Save Cover",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "The cover changes could not be saved.")
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
    private var barHeight: CGFloat { frameHeight * 0.10 }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar: memory title left, page number right (vertically centered in the bar)
            HStack(alignment: .center) {
                Text(title ?? "Memory")
                    .font(.kidsBookTitleFont(for: frameHeight))
                    .foregroundColor(colors.chapterTitleColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text("\(pageNumber)")
                    .font(.kidsBookPageNumberFont(for: frameHeight))
                    .foregroundColor(colors.pageNumberColor)
            }
            .padding(.horizontal, frameWidth * 0.07)
            .padding(.vertical, barHeight * 0.1)
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
            .background(colors.bookPageBackground)

            // Full page illustration fills remaining space
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
    
    var body: some View {
        FieldnotesMemoryPage(title: title, text: text, pageNumber: pageNumber,
                             frameWidth: frameWidth, frameHeight: frameHeight)
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
    private var barHeight: CGFloat { frameHeight * 0.10 }
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
    
    var body: some View {
        FieldnotesMemoryPage(title: title, text: text, pageNumber: pageNumber,
                             frameWidth: frameWidth, frameHeight: frameHeight)
    }
}

struct FieldnotesMemoryPage: View {
    let title: String?
    let text: String
    let pageNumber: Int
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    var body: some View {
        let bodySize = frameHeight * BookInteriorStyle.bodySize
        ZStack(alignment: .topLeading) {
            BookInteriorStyle.paper
            FieldnotesMemoryChrome(pageNumber: pageNumber, frameWidth: frameWidth, frameHeight: frameHeight)
            Text(title ?? "Memory")
                .font(.custom("GillSans", size: frameHeight * 0.054))
                .foregroundStyle(BookInteriorStyle.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(
                    width: frameWidth * BookInteriorStyle.memoryContentWidth,
                    height: frameHeight * BookInteriorStyle.memoryTitleHeight,
                    alignment: .leading
                )
                .offset(
                    x: frameWidth * BookInteriorStyle.memoryHorizontalInset,
                    y: frameHeight * BookInteriorStyle.memoryTitleY
                )
            Text(text)
                .font(.custom("Georgia", size: bodySize))
                .lineSpacing(bodySize * BookInteriorStyle.lineSpacing / BookInteriorStyle.bodySize)
                .foregroundStyle(BookInteriorStyle.ink)
                .frame(
                    width: frameWidth * BookInteriorStyle.memoryContentWidth,
                    height: frameHeight * BookInteriorStyle.memoryBodyHeight,
                    alignment: .topLeading
                )
                .offset(
                    x: frameWidth * BookInteriorStyle.memoryHorizontalInset,
                    y: frameHeight * BookInteriorStyle.memoryBodyY
                )
        }
        .frame(width: frameWidth, height: frameHeight)
        .clipped()
    }
}

struct FieldnotesMemoryChrome: View {
    let pageNumber: Int
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("MEMORY")
                .font(.custom("GillSans", size: frameHeight * 0.015))
                .tracking(frameWidth * 0.002)
                .foregroundStyle(BookInteriorStyle.accent)
                .offset(
                    x: frameWidth * BookInteriorStyle.memoryHorizontalInset,
                    y: frameHeight * BookInteriorStyle.memoryKickerY
                )
            Rectangle().fill(BookInteriorStyle.rule)
                .frame(
                    width: frameWidth * BookInteriorStyle.memoryContentWidth,
                    height: max(0.4, frameHeight * 0.001)
                )
                .offset(
                    x: frameWidth * BookInteriorStyle.memoryHorizontalInset,
                    y: frameHeight * BookInteriorStyle.memoryRuleY
                )
            Text(String(format: "%02d", pageNumber))
            .font(.custom("GillSans", size: frameHeight * 0.015))
            .foregroundStyle(BookInteriorStyle.ink)
            .frame(width: frameWidth * BookInteriorStyle.memoryContentWidth, alignment: .trailing)
            .offset(
                x: frameWidth * BookInteriorStyle.memoryHorizontalInset,
                y: frameHeight * BookInteriorStyle.memoryPageNumberY
            )
        }
        .frame(width: frameWidth, height: frameHeight, alignment: .topLeading)
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
        showCoverEditor: Binding<Bool>,
        storybookScreenEntry: StorybookScreenEntry,
        isOpeningBook: Binding<Bool>
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
            storybookScreenEntry: storybookScreenEntry,
            isOpeningBook: isOpeningBook
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
        showCoverEditor: Binding<Bool>
    ) -> some View {
        self
            .background(
                NavigationLink(
                    destination: RecentMemoriesView(
                        enhancementMode: true,
                        initialMemoirMode: currentMemoirMode()
                    ).environmentObject(profileVM),
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
                    .adaptiveSheetDetents(preferredHeight: 152)
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
                SubscriptionPaywallView()
            }
            .fullScreenCover(isPresented: showCoverEditor) {
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
            .alert("Create a New Book?", isPresented: showRegenerateConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Create New Book") {
                    regenerateStorybook()
                }
            } message: {
                Text("Your current book will stay in your Library while you create a new one.")
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
        storybookScreenEntry: StorybookScreenEntry,
        isOpeningBook: Binding<Bool>
    ) -> some View {
        self
            .onAppear {
                print("🧭 StoryPage lifecycle onAppear; profile=\(profileVM.selectedProfile.id.uuidString.prefix(8))…, hasGenerated=\(vm.hasGeneratedStorybook), hasRequested=\(hasRequestedGeneration.wrappedValue), pageItems=\(vm.pageItems.count), entry=\(storybookScreenEntry)")
                StorybookSeenTracker.shared.setStoryPageVisible(true)
                if let bookId = vm.currentBookVersionRecord?.bookVersionId {
                    StorybookSeenTracker.shared.markCompletedSeen(jobId: bookId)
                }
            }
            .background(StorybookAppearanceObserver {
                print("[StorybookEntry] Navigation finished; starting book restoration")
                vm.restoreSettingsFromCloud()
                let routedJobID = storybookScreenEntry.resumesPendingGeneration
                    ? StorybookSeenTracker.shared.consumePendingRouteForAttachment()
                    : nil
                Task { @MainActor in
                    defer { isOpeningBook.wrappedValue = false }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-UITestSeedStorybook") {
                        vm.seedStorybookForUITesting(
                            profileID: profileVM.selectedProfile.id,
                            profileName: profileVM.selectedProfile.name
                        )
                        hasRequestedGeneration.wrappedValue = true
                        return
                    }
                    #endif
                    if storybookScreenEntry.resumesPendingGeneration {
                        let resuming = await vm.resumeInProgressGenerationIfMarkerExists(
                            profileID: profileVM.selectedProfile.id,
                            profileName: profileVM.selectedProfile.name,
                            profileEthnicity: profileVM.selectedProfile.ethnicity,
                            routedJobID: routedJobID
                        )
                        if resuming {
                            hasRequestedGeneration.wrappedValue = true
                            return
                        }
                    }
                    vm.loadStorybookForProfile(
                        profileVM.selectedProfile.id,
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

                Task { @MainActor in
                    if vm.styleTilePublic == nil,
                       let style = UIImage(named: "kidsref") {
                        vm.styleTile = style
                    }
                }

                Task { await subscriptionManager.refreshCustomerInfo() }
                updateIncompleteCount()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true))
            .onDisappear {
                print("🧭 StoryPage lifecycle onDisappear; hasRequested=\(hasRequestedGeneration.wrappedValue), pageItems=\(vm.pageItems.count)")
                StorybookSeenTracker.shared.setStoryPageVisible(false)
            }
            .onChange(of: subscriptionManager.hasActiveSubscription) { _, isActive in
                if isActive, vm.errorMessage?.contains("free preview") == true {
                    vm.errorMessage = nil
                }
            }
            .onChange(of: vm.currentBookVersionRecord?.bookVersionId) { _, newBookId in
                // Displaying a finished book (job id == book version id) counts as seeing it,
                // so the launch auto-route stops force-opening it.
                if let newBookId {
                    StorybookSeenTracker.shared.markCompletedSeen(jobId: newBookId)
                }
            }
            .onChange(of: vm.hasGeneratedStorybook) { _, hasGenerated in
                if hasGenerated {
                    hasRequestedGeneration.wrappedValue = true
                }
            }
            .onChange(of: profileVM.selectedProfile.id) { _, newProfileID in
                print("🧭 StoryPage profile changed to \(newProfileID.uuidString.prefix(8))…; reloading storybook")
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
    private func makeSubscriptionTooltip() -> some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Image Generation Limit")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Each subscription includes 100 images per calendar month. This counter shows how many you have remaining.")
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
