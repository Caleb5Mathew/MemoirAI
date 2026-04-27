import Foundation
import SwiftUI
import CoreData
import CoreImage.CIFilterBuiltins
import PDFKit
import UIKit
import Photos
import FirebaseAuth
import FirebaseFirestore

/// Filter Xcode console for `[StorybookGen]` to see storybook pipeline details.
/// In **Release** builds, set `UserDefaults` key `MemoirAI_StorybookVerboseLogging` to `true` to enable the same verbose lines.
private enum StorybookGenLog {
    #if DEBUG
    static let verbose: Bool = true
    #else
    static var verbose: Bool { UserDefaults.standard.bool(forKey: "MemoirAI_StorybookVerboseLogging") }
    #endif

    static func line(_ message: String) {
        print("[StorybookGen] \(message)")
    }

    static func verboseLine(_ message: String) {
        if verbose { line(message) }
    }

    static func fence(_ title: String) {
        line("════════ \(title) ════════")
    }
}

/// A memory that was dropped from the storybook because illustration generation did not produce an image.
struct SkippedStoryImageMemory: Identifiable, Equatable {
    let id: UUID
    let memoryLabel: String
    let detail: String
}

struct PersistablePageItem: Codable {
    let type: String // "illustration", "textPage", "qrCode"
    let imageData: Data?
    let caption: String?
    let title: String?
    let subtitle: String?
    let textContent: String?
    let url: String?
    let pageIndex: Int?
    let totalPages: Int?
}

struct PersistableStorybook: Codable {
    let profileID: UUID
    let pageItems: [PersistablePageItem]
    let artStyle: String
    let createdAt: Date
    /// Editable display / print title (cover + Lulu metadata).
    var bookDisplayTitle: String?
    /// Back-cover marketing copy (also used for interior colophon).
    var backCoverPitch: String?
    /// `CoverFontPreset.rawValue`
    var coverFontPreset: String?

    init(
        profileID: UUID,
        pageItems: [PersistablePageItem],
        artStyle: String,
        createdAt: Date,
        bookDisplayTitle: String? = nil,
        backCoverPitch: String? = nil,
        coverFontPreset: String? = nil
    ) {
        self.profileID = profileID
        self.pageItems = pageItems
        self.artStyle = artStyle
        self.createdAt = createdAt
        self.bookDisplayTitle = bookDisplayTitle
        self.backCoverPitch = backCoverPitch
        self.coverFontPreset = coverFontPreset
    }
}

@MainActor
class StoryPageViewModel: ObservableObject {
    struct PrintParityReport {
        let printWidth: CGFloat
        let printHeight: CGFloat
        let previewWidth: CGFloat
        let previewHeight: CGFloat
        let expectedAspectRatio: CGFloat
        let previewAspectRatio: CGFloat
        let pageCount: Int
        let hasPotentialOverflowRisk: Bool
        let notes: [String]
    }

    enum PageItem {
        case illustration(image: UIImage, memoryID: UUID, title: String?)
        case textPage(index: Int, total: Int, body: String, title: String?, subtitle: String?, memoryID: UUID)
    }

    @Published var isLoading      : Bool = false
    /// True while finishing a previously interrupted `bookVersions` upload for this profile (do not start competing saves).
    @Published var isResumingPendingBookSync: Bool = false
    /// Set while `FirestoreSyncService.queueBookSync` is still running (covers upload + `syncBook`).
    @Published var isUploadingToCloud: Bool = false
    private var bookSyncInFlightCount: Int = 0
    /// Firestore listener for `users/{uid}/storybookJobs/{jobId}` (cloud AI generation).
    private var storybookCloudJobListener: ListenerRegistration?
    private var cloudStorybookFinalizeStarted = false
    /// True while saving, rendering page images, and waiting for canonical PDF after generation reached 100%.
    @Published var isFinalizingAssets: Bool = false
    @Published var errorMessage   : String?
    @Published var progress       : Double    = 0
    @Published var pageItems      : [PageItem] = []

    /// Editable book title for cover, interior title page, and Lulu metadata.
    @Published var bookDisplayTitle: String = ""
    /// AI or fallback back-cover / colophon copy.
    @Published var backCoverPitch: String = ""
    /// `CoverFontPreset.rawValue`; updated when print packaging runs.
    var coverFontPreset: String = ""

    /// Last cloud sync id for `resyncPrintPackagingAfterTitleEdit()` (same id as Firestore `bookVersions` doc).
    private(set) var lastSyncedBookVersionId: String?
    /// Original `createdAt` used when building `PersistableStorybook` for the synced version.
    private(set) var lastPersistedBookCreatedAt: Date?

    // Progress tracking for UI
    @Published var currentMemoryIndex: Int = 0
    @Published var totalMemories: Int = 0
    @Published var currentStatus: String = ""
    
    // Image editing state
    @Published var editingImageIndex: Int? = nil
    @Published var imageEditingStates: [Int: Bool] = [:] // Track loading state per image index
    /// When non-nil, user is regenerating print cover art for the front or back panel (instruction-based edit).
    @Published private(set) var coverPanelEditing: BookCoverFlatPanel?

    /// True when the synced book has a print cover PDF to load panels from.
    var hasPrintCoverPDF: Bool {
        currentBookVersionRecord?.printCoverPDFURL != nil
    }

    func isEditingCoverArt(for panel: BookCoverFlatPanel) -> Bool {
        coverPanelEditing == panel
    }

    @Published var subjectPhoto   : UIImage?
    @Published var subjectPhotoID : String?
    @Published var styleTile      : UIImage?
    @Published var styleTileID    : String?
    private  var subjectPhotoJPEG : Data?

    @AppStorage("memoirPageCount")          private var pageCountSetting      = 2
    @AppStorage("memoirArtStyle")           private var artStyleRaw           = ArtStyle.kidsBook.rawValue
    @AppStorage("memoirCustomArtStyleText") private var customArtStyleText    = ""
    @AppStorage("memoirEthnicity")          private var ethnicity             = ""
    @AppStorage("memoirGender")             private var gender                = ""
    @AppStorage("memoirOtherPersonalDetails") private var otherDetails        = ""
    @AppStorage("memoirMemorySource")       private var memorySourceSetting   = "all"
    @AppStorage("memoirGeminiModelOverride") private var geminiModelOverrideRawValue = GeminiImageService.Model.gemini3ProPreview
    @AppStorage("memoirStyleReferencePreset") private var styleReferencePresetRawValue = "normal"
    
    // iCloud backup for critical settings
    private func backupSettingsToCloud() {
        NSUbiquitousKeyValueStore.default.set(pageCountSetting, forKey: "memoir_pageCount")
        NSUbiquitousKeyValueStore.default.set(artStyleRaw, forKey: "memoir_artStyle")
        NSUbiquitousKeyValueStore.default.set(customArtStyleText, forKey: "memoir_customArtStyleText")
        NSUbiquitousKeyValueStore.default.set(ethnicity, forKey: "memoir_ethnicity")
        NSUbiquitousKeyValueStore.default.set(gender, forKey: "memoir_gender")
        NSUbiquitousKeyValueStore.default.set(otherDetails, forKey: "memoir_otherPersonalDetails")
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    private func restoreSettingsFromCloud() {
        NSUbiquitousKeyValueStore.default.synchronize()
        
        let cloudPageCount = NSUbiquitousKeyValueStore.default.longLong(forKey: "memoir_pageCount")
        if cloudPageCount > 0 {
            pageCountSetting = Int(cloudPageCount)
        }
        
        let cloudArtStyle = NSUbiquitousKeyValueStore.default.string(forKey: "memoir_artStyle")
        if let artStyle = cloudArtStyle, !artStyle.isEmpty {
            artStyleRaw = artStyle
        }
        
        let cloudCustomStyle = NSUbiquitousKeyValueStore.default.string(forKey: "memoir_customArtStyleText")
        if let customStyle = cloudCustomStyle {
            customArtStyleText = customStyle
        }
        
        let cloudEthnicity = NSUbiquitousKeyValueStore.default.string(forKey: "memoir_ethnicity")
        if let ethnicity = cloudEthnicity {
            self.ethnicity = ethnicity
        }
        
        let cloudGender = NSUbiquitousKeyValueStore.default.string(forKey: "memoir_gender")
        if let gender = cloudGender {
            self.gender = gender
        }
        
        let cloudOtherDetails = NSUbiquitousKeyValueStore.default.string(forKey: "memoir_otherPersonalDetails")
        if let otherDetails = cloudOtherDetails {
            self.otherDetails = otherDetails
        }
    }
    
    // NEW: Persistent storage for generated storybooks per profile
    @Published var hasGeneratedStorybook: Bool = false
    /// True after canonical cloud render confirms the interior PDF is ready (`pdfURL` + rendered status). Cover may still be generating.
    @Published var isVisualBookReady: Bool = false
    /// During fresh generation, keep StoryPage hidden until visual artifacts are ready.
    @Published var requiresVisualReadyGate: Bool = false
    @Published var currentBookVersionRecord: BookVersionRecord?
    /// Illustration pages loaded from pre-rendered full-page assets should not receive an extra title/QR overlay.
    private var precomposedIllustrationMemoryIDs: Set<UUID> = []
    /// When a cloud illustration failed to download, we keep the Firestore page row so the user can retry with a fresh Storage URL.
    @Published private(set) var illustrationReloadSources: [UUID: BookVersionPageRecord] = [:]
    @Published private(set) var illustrationRetryInProgress: Set<UUID> = []

    /// Populated after `generateStorybook` when one or more memories were skipped because Gemini returned no image or errored.
    @Published private(set) var skippedMemoriesDuringGeneration: [SkippedStoryImageMemory] = []

    private static let illustrationDownloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private var currentProfileID: UUID?
    /// Used so `loadStorybookForProfile` does not clear `skippedMemoriesDuringGeneration` on every `onAppear` for the same profile.
    private var lastStorybookLoadProfileID: UUID?
    private var profileName: String?
    private var loadedBookOrientation: String?
    private var loadedBookPageWidth: CGFloat?
    private var loadedBookPageHeight: CGFloat?

    // Make currentArtStyle public so StoryPage can access it
    var currentArtStyle : ArtStyle {
        if let resolved = ArtStyle(rawValue: artStyleRaw) { return resolved }
        print("⚠️ currentArtStyle: unrecognized rawValue '\(artStyleRaw)' — falling back to kidsBook")
        return .kidsBook
    }

    /// True when the current book has required artifacts ready for entering print checkout.
    /// Page-count eligibility is handled in `OrderBookView` via selectable format options.
    var isBookOrderable: Bool {
        guard let r = currentBookVersionRecord else { return false }
        return r.renderStatus == BookRenderStatus.rendered.rawValue
            && r.pdfURL != nil
            && r.coverURL != nil
    }
    private func canonicalVisualReadiness(for record: BookVersionRecord?) -> Bool {
        guard let record else { return false }
        // Require cover so the gallery cell stays unavailable until the full artifact set is ready.
        return record.renderStatus == BookRenderStatus.rendered.rawValue
            && record.pdfURL != nil
            && record.coverURL != nil
    }
    var currentPrintSpec: BookPrintSpec { resolvedPrintSpec() }

    /// Identity for the story `TabView`; cover panels already reload via `RemotePDFThumbnailView` `.task(id: cacheKey)`.
    var tabViewCoverRefreshIdentity: String {
        lastSyncedBookVersionId ?? ""
    }

    /// User-facing summary for the “skipped memories” notice after partial storybook generation.
    var skippedMemoriesNoticeSummary: String {
        let n = skippedMemoriesDuringGeneration.count
        guard n > 0 else { return "" }
        if n == 1 {
            return "One memory was not included because its illustration could not be created. Everything else is in your storybook."
        }
        return "\(n) memories were not included because their illustrations could not be created. Everything else is in your storybook."
    }

    private var faceDescription : String?

    private let promptGen : PromptGenerator
    private let imageCtx  : ImageContext
    private let imageSvc  : OpenAIImageService
    private let openAIKey : String
    private let assembler : PromptAssembler
    private let geminiImageSvc : GeminiImageService?
    private var cachedNormalStyleImage: UIImage?
    private var cachedRef1StyleImage: UIImage?
    private var cachedRef2StyleImage: UIImage?

    // Toggle to bypass expensive LLM sanitization if it's over-sanitising prompts.
    private let useLLMSanitizer = false

    private var effectiveGeminiModel: String {
        // Production/default path: always use Nano Banana 3 Pro Preview.
        let productionModel = GeminiImageService.Model.gemini3ProPreview
        let allowedModels = Set([
            GeminiImageService.Model.gemini3ProPreview,
            GeminiImageService.Model.gemini25FlashImage
        ])

        #if DEBUG
        let canUseDeveloperOverride = RCSubscriptionManager.shared.isDeveloperUnlocked
        #else
        let canUseDeveloperOverride = false
        #endif

        guard canUseDeveloperOverride else {
            return productionModel
        }

        let configured = geminiModelOverrideRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowedModels.contains(configured) else {
            return productionModel
        }
        return configured
    }

    private enum StyleReferenceProfile: String {
        case normal
        case ref1
        case ref2
        case none // legacy value fallback
    }

    private struct LoadedStyleReference {
        let image: UIImage
        let filename: String
    }

    private var styleReferenceProfile: StyleReferenceProfile {
        if styleReferencePresetRawValue == StyleReferenceProfile.none.rawValue {
            return .normal
        }
        return StyleReferenceProfile(rawValue: styleReferencePresetRawValue) ?? .normal
    }

    private func loadBundledStyleReferenceImage(named baseName: String) -> UIImage? {
        if let subdirURL = Bundle.main.url(forResource: baseName, withExtension: "png", subdirectory: "FlipbookBundle"),
           let data = try? Data(contentsOf: subdirURL),
           let image = UIImage(data: data) {
            return image
        }

        if let rootURL = Bundle.main.url(forResource: baseName, withExtension: "png"),
           let data = try? Data(contentsOf: rootURL),
           let image = UIImage(data: data) {
            return image
        }

        if let image = UIImage(named: baseName) ?? UIImage(named: "FlipbookBundle/\(baseName)") {
            return image
        }

        return nil
    }

    private func loadSelectedStyleReferenceIfNeeded(lockedArtStyle: ArtStyle? = nil) -> LoadedStyleReference? {
        let style = lockedArtStyle ?? currentArtStyle
        guard style == .kidsBook else {
            return nil
        }

        switch styleReferenceProfile {
        case .normal:
            if let cachedNormalStyleImage {
                return LoadedStyleReference(image: cachedNormalStyleImage, filename: "Refnormal.png")
            }
            if let image = loadBundledStyleReferenceImage(named: "Refnormal") {
                cachedNormalStyleImage = image
                print("🧷 Loaded style reference image: Refnormal.png")
                return LoadedStyleReference(image: image, filename: "Refnormal.png")
            }
        case .ref1:
            if let cachedRef1StyleImage {
                return LoadedStyleReference(image: cachedRef1StyleImage, filename: "Ref1.png")
            }
            if let image = loadBundledStyleReferenceImage(named: "Ref1") {
                cachedRef1StyleImage = image
                print("🧷 Loaded style reference image: Ref1.png")
                return LoadedStyleReference(image: image, filename: "Ref1.png")
            }
        case .ref2:
            if let cachedRef2StyleImage {
                return LoadedStyleReference(image: cachedRef2StyleImage, filename: "Ref2.png")
            }
            if let image = loadBundledStyleReferenceImage(named: "Ref2") {
                cachedRef2StyleImage = image
                print("🧷 Loaded style reference image: Ref2.png")
                return LoadedStyleReference(image: image, filename: "Ref2.png")
            }
        case .none:
            return nil
        }

        print("⚠️ Style reference preset '\(styleReferenceProfile.rawValue)' is ON, but the selected file could not be loaded from app bundle.")
        return nil
    }

    private func styleReferencePromptHint(for style: ArtStyle) -> String? {
        guard style == .kidsBook else { return nil }

        switch styleReferenceProfile {
        case .normal:
            return """
            STYLE REFERENCE HINT (Normal): A style reference image is attached. Keep the same soft watercolor children's-book vibe and hand-drawn warmth as the reference. Preserve scene details and composition freedom from the memory, but keep rendering style consistent across pages.
            """
        case .none:
            return nil
        case .ref1:
            return """
            STYLE REFERENCE HINT (Ref1): A style reference image is attached. Match its hand-drawn watercolor children's-book vibe: soft pencil/ink lines, gentle paint texture, light paper feel, and warm natural palette. Keep scene details and composition creative, but keep rendering consistent with the reference across pages.
            Little laughs in daylight glow, soft brushstrokes in a gentle flow.
            Keep it warm and storybook sweet, with hand-drawn charm in every beat.
            Avoid anime, vector-clean, cel-shaded, or glossy digital-cartoon rendering.
            """
        case .ref2:
            return """
            STYLE REFERENCE HINT (Ref2): A style reference image is attached. Keep the same playful hand-drawn children's-book feel, simple readable forms, and consistent page-to-page rendering vibe. Preserve scene/action details from the memory and allow natural composition variation page to page.
            """
        }
    }

    init() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
              !key.isEmpty, !key.contains("YOUR_API") else {
            fatalError("OPENAI_API_KEY missing or invalid")
        }
        openAIKey = key
        promptGen = PromptGenerator(apiKey: key)
        imageCtx  = ImageContext(apiKey: key)
        imageSvc  = OpenAIImageService(apiKey: key)
        assembler = PromptAssembler(apiKey: key)
        
        // Initialize Gemini service if API key is available (optional)
        if let geminiKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
           !geminiKey.isEmpty, !geminiKey.contains("YOUR_API") {
            geminiImageSvc = GeminiImageService(apiKey: geminiKey)
            print("✅ Gemini image service initialized")
        } else {
            geminiImageSvc = nil
            print("⚠️ GEMINI_API_KEY not found, Gemini image generation will be skipped")
        }
        
        // Restore settings from iCloud backup
        restoreSettingsFromCloud()

        NotificationCenter.default.addObserver(forName: .storybookCloudUploadActivity, object: nil, queue: .main) { [weak self] n in
            Task { @MainActor in
                guard let self else { return }
                if let d = n.userInfo?["bookSyncCountDelta"] as? Int {
                    self.bookSyncInFlightCount = max(0, self.bookSyncInFlightCount + d)
                    self.isUploadingToCloud = self.bookSyncInFlightCount > 0
                } else if let uploading = n.userInfo?["isUploading"] as? Bool {
                    // Legacy: boolean replaced by refcount delta on `queueBookSync`.
                    self.isUploadingToCloud = uploading
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .storybookGenerationBackgroundExpiring, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.emergencyFlushInProgressGenerationToDisk()
            }
        }
    }

    func expectedPageCount() -> Int { pageCountSetting }
    var  styleTilePublic: UIImage? { styleTile }
    
    // Backup settings when they change
    private func backupSettingsIfNeeded() {
        backupSettingsToCloud()
    }
    
    // NEW: Load persisted storybook for a profile
    func loadStorybookForProfile(_ profileID: UUID, name: String? = nil, profileEthnicity: String? = nil) {
        if lastStorybookLoadProfileID != profileID {
            skippedMemoriesDuringGeneration = []
        }
        lastStorybookLoadProfileID = profileID
        currentProfileID = profileID
        profileName = name
        if ethnicity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let pe = profileEthnicity?.trimmingCharacters(in: .whitespacesAndNewlines), !pe.isEmpty {
            ethnicity = pe
        }
        requiresVisualReadyGate = false
        Task {
            print("[StorybookLoad] loadStorybookForProfile START profile=\(profileID.uuidString.prefix(8)) isLoading=\(isLoading) pageItems=\(pageItems.count) isLoadingGalleryBook=\(isLoadingGalleryBook)")
            // Avoid racing `generateStorybook`: a load that started before generation can still finish after.
            guard !isLoading else {
                print("[StorybookLoad] loadStorybookForProfile ABORT (isLoading before migrate)")
                return
            }
            guard !isLoadingGalleryBook else {
                print("[StorybookLoad] loadStorybookForProfile ABORT (My Library book is opening — skip profile cloud load)")
                return
            }
            await migrateLegacyLocalBooksIfNeeded(for: profileID)
            guard !isLoading else {
                print("[StorybookLoad] loadStorybookForProfile ABORT (isLoading after migrate)")
                return
            }
            guard !isLoadingGalleryBook else {
                print("[StorybookLoad] loadStorybookForProfile ABORT (gallery load started during migrate)")
                return
            }
            isResumingPendingBookSync = true
            await FirestoreSyncService.shared.retryPendingSyncs(for: profileID)
            isResumingPendingBookSync = false
            guard !isLoading else {
                print("[StorybookLoad] loadStorybookForProfile ABORT (isLoading after pending sync retry)")
                return
            }
            guard !isLoadingGalleryBook else {
                print("[StorybookLoad] loadStorybookForProfile ABORT (gallery load after pending sync retry)")
                return
            }
            // Do not auto-regenerate covers during normal book loading.
            // Auto backfill can make an existing book's cover art change unexpectedly.
            let loadedFromCloud = await loadLatestBookVersionFromCloud(for: profileID)
            guard !isLoading else {
                print("[StorybookLoad] loadStorybookForProfile ABORT (isLoading after cloud) loadedFromCloud=\(loadedFromCloud)")
                return
            }
            guard !isLoadingGalleryBook else {
                print("[StorybookLoad] loadStorybookForProfile ABORT (gallery load — skip disk fallback / duplicate apply)")
                return
            }
            if !loadedFromCloud {
                print("[StorybookLoad] loadStorybookForProfile → loadPersistedStorybook (cloud skipped or none)")
                loadPersistedStorybook(for: profileID)
            } else {
                print("[StorybookLoad] loadStorybookForProfile END applied cloud latest pageItems=\(pageItems.count)")
            }
        }
    }
    
    // NEW: Clear current storybook (for regeneration)
    func clearCurrentStorybook() {
        pageItems.removeAll()
        hasGeneratedStorybook = false
        isVisualBookReady = false
        isFinalizingAssets = false
        requiresVisualReadyGate = false
        currentBookVersionRecord = nil
        errorMessage = nil
        loadedBookOrientation = nil
        loadedBookPageWidth = nil
        loadedBookPageHeight = nil
        bookDisplayTitle = ""
        backCoverPitch = ""
        coverFontPreset = ""
        lastSyncedBookVersionId = nil
        lastPersistedBookCreatedAt = nil
        precomposedIllustrationMemoryIDs = []
        illustrationReloadSources = [:]
        illustrationRetryInProgress = []
        skippedMemoriesDuringGeneration = []
        
        // Clear persisted data for current profile
        if let profileID = currentProfileID {
            clearPersistedStorybook(for: profileID)
        }
    }
    
    // NEW: Download storybook as PDF – pixel-perfect snapshot of SwiftUI pages
    func downloadStorybook(previewWidth: CGFloat? = nil, previewHeight: CGFloat? = nil) -> URL? {
        guard !pageItems.isEmpty else { return nil }
        let printSpec = resolvedPrintSpec()
        let pdfWidth = printSpec.widthPt
        let pdfHeight = printSpec.heightPt
        let isKids = printSpec.orientation == "landscape"
        
        // PDF bounds in points - always use standard page sizes
        let pdfBounds = CGRect(x: 0, y: 0, width: pdfWidth, height: pdfHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pdfBounds)
        
        // For rendering, use PDF dimensions
        let bookWidth = pdfWidth
        let bookHeight = pdfHeight

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("MemoirAI_Storybook_\(Date().timeIntervalSince1970).pdf")

        do {
            try renderer.writePDF(to: url) { ctx in
                for (idx, item) in pageItems.enumerated() {
                    ctx.beginPage(withBounds: pdfBounds, pageInfo: [:])

                    // Build the same SwiftUI view used on-screen
                    let view: AnyView
                    let fontStyle = BookFontStyle(artStyle: currentArtStyle)
                    switch item {
                    case .illustration(let image, let memoryID, let title):
                        if isPrecomposedIllustration(memoryID: memoryID) {
                            view = AnyView(
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: bookWidth, height: bookHeight)
                                    .clipped()
                            )
                        } else {
                            let illustrationView: AnyView
                            if isKids {
                                illustrationView = AnyView(KidsBookIllustrationPage(
                                    image: image,
                                    memoryID: memoryID,
                                    title: title,
                                    frameWidth: bookWidth,
                                    frameHeight: bookHeight,
                                    pageNumber: idx + 1))
                            } else {
                                illustrationView = AnyView(VerticalBookIllustrationPage(
                                    image: image,
                                    memoryID: memoryID,
                                    title: title,
                                    fontStyle: fontStyle,
                                    frameWidth: bookWidth,
                                    frameHeight: bookHeight,
                                    pageNumber: idx + 1,
                                    totalPages: pageItems.count))
                            }
                            let qrTopInset: CGFloat = bookHeight * 0.065 + 6
                            view = AnyView(illustrationView.overlay(QRWatermark(memoryID: memoryID, topInset: qrTopInset)))
                        }
                    case .textPage(let pIdx, let total, let body, let title, let subtitle, let memoryID):
                        let textView: AnyView
                        if isKids {
                            textView = AnyView(KidsBookTextPage(
                                index: pIdx,
                                total: total,
                                text: body,
                                title: title,
                                subtitle: subtitle,
                                memoryID: memoryID,
                                fontStyle: fontStyle,
                                frameWidth: bookWidth,
                                frameHeight: bookHeight,
                                pageNumber: idx + 1))
                        } else {
                            textView = AnyView(VerticalBookTextPage(
                                index: pIdx,
                                total: total,
                                text: body,
                                title: title,
                                subtitle: subtitle,
                                memoryID: memoryID,
                                fontStyle: fontStyle,
                                frameWidth: bookWidth,
                                frameHeight: bookHeight,
                                pageNumber: idx + 1))
                        }
                        view = AnyView(textView.overlay(QRWatermark(memoryID: memoryID)))
                    }

                    // Snapshot & draw full-bleed
                    let img = view.snapshot(width: bookWidth, height: bookHeight)
                    img.draw(in: pdfBounds)
                }
            }
            return url
        } catch {
            print("❌ Failed to create PDF: \(error)")
            return nil
        }
    }
    
    func renderCurrentBookPagesAsImages() -> [UIImage] {
        guard !pageItems.isEmpty else { return [] }
        
        let spec = resolvedPrintSpec()
        let bookWidth = spec.widthPt
        let bookHeight = spec.heightPt
        let isKids = spec.orientation == "landscape"
        let fontStyle = BookFontStyle(artStyle: currentArtStyle)
        
        return pageItems.enumerated().map { idx, item in
            autoreleasepool {
            let view: AnyView
            
            switch item {
            case .illustration(let image, let memoryID, let title):
                if isPrecomposedIllustration(memoryID: memoryID) {
                    view = AnyView(
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: bookWidth, height: bookHeight)
                            .clipped()
                    )
                } else {
                    let illustrationView: AnyView = isKids
                        ? AnyView(KidsBookIllustrationPage(
                            image: image,
                            memoryID: memoryID,
                            title: title,
                            frameWidth: bookWidth,
                            frameHeight: bookHeight,
                            pageNumber: idx + 1
                        ))
                        : AnyView(VerticalBookIllustrationPage(
                            image: image,
                            memoryID: memoryID,
                            title: title,
                            fontStyle: fontStyle,
                            frameWidth: bookWidth,
                            frameHeight: bookHeight,
                            pageNumber: idx + 1,
                            totalPages: pageItems.count
                        ))
                    
                    let qrTopInset: CGFloat = bookHeight * 0.065 + 6
                    view = AnyView(illustrationView.overlay(QRWatermark(memoryID: memoryID, topInset: qrTopInset)))
                }
            case .textPage(let pageIndex, let total, let body, let title, let subtitle, let memoryID):
                if memoryID == BookInteriorAnchor.titlePageMemoryId {
                    let coverTitle = (title ?? bookDisplayTitle).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Memoir"
                        : (title ?? bookDisplayTitle)
                    view = AnyView(
                        MemoirCoverFrontPage(
                            title: coverTitle,
                            subtitle: body,
                            frameWidth: bookWidth,
                            frameHeight: bookHeight,
                            isKidsBook: isKids
                        )
                    )
                } else if memoryID == BookInteriorAnchor.closingPageMemoryId {
                    let heading = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? (title ?? "About this Memoir")
                        : "About this Memoir"
                    view = AnyView(
                        MemoirCoverBackPage(
                            heading: heading,
                            bodyText: body,
                            frameWidth: bookWidth,
                            frameHeight: bookHeight
                        )
                    )
                } else {
                    let textView: AnyView = isKids
                        ? AnyView(KidsBookTextPage(
                            index: pageIndex,
                            total: total,
                            text: body,
                            title: title,
                            subtitle: subtitle,
                            memoryID: memoryID,
                            fontStyle: fontStyle,
                            frameWidth: bookWidth,
                            frameHeight: bookHeight,
                            pageNumber: idx + 1
                        ))
                        : AnyView(VerticalBookTextPage(
                            index: pageIndex,
                            total: total,
                            text: body,
                            title: title,
                            subtitle: subtitle,
                            memoryID: memoryID,
                            fontStyle: fontStyle,
                            frameWidth: bookWidth,
                            frameHeight: bookHeight,
                            pageNumber: idx + 1
                        ))
                    view = AnyView(textView.overlay(QRWatermark(memoryID: memoryID)))
                }
            }
            
            var shot = view.snapshot(width: bookWidth, height: bookHeight)
            if min(shot.size.width, shot.size.height) <= 64 {
                print("⚠️ [StorybookLoad] WARNING degenerate page snapshot at index=\(idx); substituting light placeholder")
                let s = CGSize(width: max(bookWidth, 100), height: max(bookHeight, 100))
                shot = UIGraphicsImageRenderer(size: s).image { ctx in
                    UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1.0).setFill()
                    ctx.fill(CGRect(origin: .zero, size: s))
                }
            }
            return shot
            }
        }
    }
    
    func exportCurrentBookToPhotos() async throws {
        let pageImages = renderCurrentBookPagesAsImages()
        guard !pageImages.isEmpty else { return }
        
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "MemoirAI", code: 301, userInfo: [NSLocalizedDescriptionKey: "Photo library permission denied"])
        }
        
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                for image in pageImages {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }) { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "MemoirAI", code: 302, userInfo: [NSLocalizedDescriptionKey: "Failed saving pages to Photos"]))
                }
            }
        }
    }
    
    func exportBookVersionPDF(bookVersionId: String) async -> URL? {
        if let serverPdfURL = await FirestoreSyncService.shared.fetchOrGenerateBookPDF(bookVersionId: bookVersionId),
           let url = URL(string: serverPdfURL) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let localURL = docs.appendingPathComponent("MemoirAI_Storybook_Server_\(bookVersionId).pdf")
                    try data.write(to: localURL, options: .atomic)
                    return localURL
                }
            } catch {
                print("⚠️ Could not download server-rendered PDF, falling back to local render: \(error.localizedDescription)")
            }
        }

        guard let record = await FirestoreSyncService.shared.fetchBookVersion(bookVersionId: bookVersionId) else {
            return nil
        }
        
        await applyBookVersionRecord(record)
        return downloadStorybook()
    }

    private func resolvedPrintSpec() -> BookPrintSpec {
        if let width = loadedBookPageWidth,
           let height = loadedBookPageHeight,
           width > 0,
           height > 0 {
            let orientation = loadedBookOrientation ?? (width > height ? "landscape" : "portrait")
            return BookPrintSpec(
                widthPt: width,
                heightPt: height,
                orientation: orientation,
                trimSizeInches: orientation == "landscape" ? "11x8.5" : "8.5x11",
                layoutVersion: BookPrintSpec.layoutVersion
            )
        }
        
        return BookPrintSpec.forArtStyle(artStyleRaw)
    }

    func makePrintParityReport(previewWidth: CGFloat, previewHeight: CGFloat) -> PrintParityReport {
        let spec = resolvedPrintSpec()
        let expectedAspect = spec.aspectRatio
        let safePreviewHeight = max(previewHeight, 1)
        let previewAspect = previewWidth / safePreviewHeight
        
        var notes: [String] = []
        let aspectDelta = abs(expectedAspect - previewAspect)
        if aspectDelta > 0.01 {
            notes.append("Preview/export aspect mismatch detected (\(String(format: "%.4f", aspectDelta))).")
        } else {
            notes.append("Preview and print aspect ratio are aligned.")
        }
        
        let hasLongText = pageItems.contains { item in
            if case .textPage(_, _, let body, _, _, _) = item {
                return body.count > 1400
            }
            return false
        }
        if hasLongText {
            notes.append("One or more text pages are long; verify no clipping on-device and PDF.")
        }
        
        return PrintParityReport(
            printWidth: spec.widthPt,
            printHeight: spec.heightPt,
            previewWidth: previewWidth,
            previewHeight: previewHeight,
            expectedAspectRatio: expectedAspect,
            previewAspectRatio: previewAspect,
            pageCount: pageItems.count,
            hasPotentialOverflowRisk: hasLongText,
            notes: notes
        )
    }

    // MARK: - Print packaging (title, pitch, interior bookends)

    private func persistablePageItemsFromCurrentState() -> [PersistablePageItem] {
        pageItems.enumerated().map { index, item in
            switch item {
            case .illustration(let image, let memoryID, let title):
                return PersistablePageItem(
                    type: "illustration",
                    imageData: image.jpegData(compressionQuality: 0.75),
                    caption: nil,
                    title: title,
                    subtitle: nil,
                    textContent: nil,
                    url: "memoirai://memory/\(memoryID.uuidString)",
                    pageIndex: index,
                    totalPages: nil
                )
            case .textPage(let pIdx, let total, let body, let title, let subtitle, let memoryID):
                return PersistablePageItem(
                    type: "textPage",
                    imageData: nil,
                    caption: nil,
                    title: title,
                    subtitle: subtitle,
                    textContent: body,
                    url: "memoirai://memory/\(memoryID.uuidString)",
                    pageIndex: pIdx,
                    totalPages: total
                )
            }
        }
    }

    private func memorySnippetForPitch() -> String {
        var parts: [String] = []
        for item in pageItems {
            if case .textPage(_, _, let body, _, _, _) = item {
                let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count > 15 { parts.append(t) }
            }
        }
        let joined = parts.joined(separator: "\n\n")
        if joined.count <= 2500 { return joined }
        return String(joined.prefix(2500))
    }

    private struct CoverSignalStats {
        var score: Int
        var recency: Int
        var display: String
    }

    private static let coverSignalStopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "into", "about", "have", "has", "had",
        "were", "was", "are", "our", "your", "their", "them", "they", "then", "than", "when", "where",
        "what", "which", "while", "after", "before", "over", "under", "through", "around", "very",
        "just", "really", "also", "story", "memory", "memoir", "page"
    ]

    /// Frequency-first cover signals with deterministic tie-breaks.
    /// Prioritizes repeated memory titles and recurring keywords from text pages.
    private func rankedCoverSignals(maxCount: Int = 5) -> [String] {
        let memoryItems = persistablePageItemsFromCurrentState().filter { item in
            guard let memoryId = BookVersionRecordFactory.memoryId(from: item.url) else { return false }
            return memoryId != BookInteriorAnchor.titlePageMemoryId.uuidString &&
                memoryId != BookInteriorAnchor.closingPageMemoryId.uuidString
        }
        guard !memoryItems.isEmpty else { return [] }

        var titleStats: [String: CoverSignalStats] = [:]
        var keywordStats: [String: CoverSignalStats] = [:]

        for (index, item) in memoryItems.enumerated() {
            if let rawTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTitle.isEmpty {
                let key = rawTitle.lowercased()
                if var existing = titleStats[key] {
                    existing.score += 3
                    existing.recency = max(existing.recency, index)
                    titleStats[key] = existing
                } else {
                    titleStats[key] = CoverSignalStats(score: 3, recency: index, display: rawTitle)
                }
            }

            if let body = item.textContent {
                for token in coverKeywordTokens(from: body) {
                    if var existing = keywordStats[token] {
                        existing.score += 1
                        existing.recency = max(existing.recency, index)
                        keywordStats[token] = existing
                    } else {
                        keywordStats[token] = CoverSignalStats(
                            score: 1,
                            recency: index,
                            display: token.capitalized
                        )
                    }
                }
            }
        }

        let sortedTitles = titleStats.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.recency != $1.recency { return $0.recency > $1.recency }
            return $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
        }
        let sortedKeywords = keywordStats.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.recency != $1.recency { return $0.recency > $1.recency }
            return $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
        }

        var selected: [String] = []
        var seen = Set<String>()

        for stat in sortedTitles {
            let normalized = stat.display.lowercased()
            if seen.insert(normalized).inserted {
                selected.append(stat.display)
            }
            if selected.count >= maxCount { return selected }
        }

        for stat in sortedKeywords where stat.score >= 2 {
            let normalized = stat.display.lowercased()
            if seen.insert(normalized).inserted {
                selected.append(stat.display)
            }
            if selected.count >= maxCount { break }
        }

        return selected
    }

    private func coverKeywordTokens(from text: String) -> [String] {
        let lower = text.lowercased()
        let words = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }

        var output: [String] = []
        output.reserveCapacity(words.count)
        for w in words {
            if Self.coverSignalStopWords.contains(w) { continue }
            output.append(w)
        }
        return output
    }

    private func distinctMemoryTitlesForCover() -> [String] {
        rankedCoverSignals(maxCount: 5)
    }

    private func stripInteriorBookendPages() {
        pageItems.removeAll {
            if case .textPage(_, _, _, _, _, let id) = $0 {
                return id == BookInteriorAnchor.titlePageMemoryId || id == BookInteriorAnchor.closingPageMemoryId
            }
            return false
        }
    }

    private func refreshInteriorBookends(openingBlurb: String, closingPitch: String) {
        stripInteriorBookendPages()
        let policy = CoverCopyPolicy(artStyle: currentArtStyle, profileDisplayName: profileName ?? "")
        let title = bookDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? policy.defaultBookTitle()
            : bookDisplayTitle
        if bookDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bookDisplayTitle = title
        }
        let opening = PageItem.textPage(
            index: 1,
            total: 1,
            body: openingBlurb,
            title: bookDisplayTitle,
            subtitle: nil,
            memoryID: BookInteriorAnchor.titlePageMemoryId
        )
        let closing = PageItem.textPage(
            index: 1,
            total: 1,
            body: closingPitch,
            title: "About this book",
            subtitle: nil,
            memoryID: BookInteriorAnchor.closingPageMemoryId
        )
        pageItems.insert(opening, at: 0)
        pageItems.append(closing)
    }

    private func hasInteriorTitlePage() -> Bool {
        pageItems.contains {
            if case .textPage(_, _, _, _, _, let id) = $0 {
                return id == BookInteriorAnchor.titlePageMemoryId
            }
            return false
        }
    }

    private func hasInteriorClosingPage() -> Bool {
        pageItems.contains {
            if case .textPage(_, _, _, _, _, let id) = $0 {
                return id == BookInteriorAnchor.closingPageMemoryId
            }
            return false
        }
    }

    private func ensureInteriorBookendsPresent() {
        guard !pageItems.isEmpty else { return }
        guard !hasInteriorTitlePage() || !hasInteriorClosingPage() else { return }
        let policy = CoverCopyPolicy(artStyle: currentArtStyle, profileDisplayName: profileName ?? "")
        let trimmedTitle = bookDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            bookDisplayTitle = policy.defaultBookTitle()
        }
        let pitch = backCoverPitch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? policy.fallbackBackCoverPitch(bookTitle: bookDisplayTitle)
            : backCoverPitch
        refreshInteriorBookends(openingBlurb: policy.interiorTitlePageBlurb(), closingPitch: pitch)
    }

    /// Older books stored `title`/`subtitle` only on the first text page of a memory; continuation pages used `nil`, which hid headers.
    private func backfillContinuationTextPageHeaders() {
        var firstHeaderByMemory: [UUID: (title: String?, subtitle: String?)] = [:]
        for i in pageItems.indices {
            guard case .textPage(let idx, let total, let body, let t, let s, let mid) = pageItems[i] else { continue }
            if mid == BookInteriorAnchor.titlePageMemoryId || mid == BookInteriorAnchor.closingPageMemoryId {
                continue
            }
            if let existing = firstHeaderByMemory[mid] {
                let newTitle = t ?? existing.title
                let newSubtitle = s ?? existing.subtitle
                if newTitle != t || newSubtitle != s {
                    pageItems[i] = .textPage(
                        index: idx,
                        total: total,
                        body: body,
                        title: newTitle,
                        subtitle: newSubtitle,
                        memoryID: mid
                    )
                }
            } else {
                firstHeaderByMemory[mid] = (t, s)
            }
        }
    }

    private func canonicalizedNarratorName(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let markers = ["(me)", "(narrator)", "(self)", "(main)", "(i)"]
        for marker in markers {
            value = value.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }
        value = value.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func resolvedNarratorDisplayName(
        profileName explicitProfileName: String?,
        from memories: [MemoryEntry]
    ) -> String {
        let profileCandidate = canonicalizedNarratorName(explicitProfileName)
        var scores: [String: Int] = [:]

        if let profileCandidate {
            // Profile should dominate tie-breaks and near-matches.
            scores[profileCandidate, default: 0] += 100
        }

        for entry in memories {
            if let narrator = canonicalizedNarratorName(deriveSubjectName(from: entry)) {
                scores[narrator, default: 0] += 10
                if let profileCandidate,
                   narrator.caseInsensitiveCompare(profileCandidate) == .orderedSame {
                    scores[narrator, default: 0] += 40
                }
            }
        }

        if let best = scores.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key.count < rhs.key.count
        })?.key {
            return best
        }

        return profileCandidate ?? "Narrator"
    }

    /// Keeps the interior title page header in sync when the user edits `bookDisplayTitle`.
    func syncBookendTitleFromDisplayTitle() {
        guard let idx = pageItems.firstIndex(where: {
            if case .textPage(_, _, _, _, _, let id) = $0 { return id == BookInteriorAnchor.titlePageMemoryId }
            return false
        }),
        case .textPage(let i, let t, let body, _, let sub, let id) = pageItems[idx] else { return }
        pageItems[idx] = .textPage(
            index: i,
            total: t,
            body: body,
            title: bookDisplayTitle,
            subtitle: sub,
            memoryID: id
        )
    }

    private func preparePrintPackagingBeforePersist(existingBackCoverPitchFromCloud: String? = nil) async {
        let policy = CoverCopyPolicy(artStyle: currentArtStyle, profileDisplayName: profileName ?? "")
        if bookDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bookDisplayTitle = policy.defaultBookTitle()
        }
        coverFontPreset = policy.coverFontPreset().rawValue

        let pitch: String
        if let preset = existingBackCoverPitchFromCloud?.trimmingCharacters(in: .whitespacesAndNewlines), !preset.isEmpty {
            pitch = CoverCopyPolicy.sanitizePitch(preset)
        } else {
            let excerpt = memorySnippetForPitch()
            let themes = distinctMemoryTitlesForCover()
            let prompt = policy.aiPitchSystemPrompt(
                bookTitle: bookDisplayTitle,
                storyExcerpt: excerpt,
                memoryThemes: themes
            )
            if let geminiSvc = geminiImageSvc,
               let raw = await geminiSvc.generateBackCoverPitch(prompt: prompt) {
                pitch = CoverCopyPolicy.sanitizePitch(raw)
            } else {
                pitch = policy.fallbackBackCoverPitch(bookTitle: bookDisplayTitle)
            }
        }
        backCoverPitch = pitch
        refreshInteriorBookends(openingBlurb: policy.interiorTitlePageBlurb(), closingPitch: pitch)
    }

    /// Always returns print-packaging inputs; `headshot` may be nil (AI cover then uses the non-human path).
    private func makeCoverInputsIfAvailable() -> FirestoreSyncService.CoverInputs {
        let name = profileName ?? ""
        let rankedThemes = rankedCoverSignals(maxCount: 5)
        let preset = CoverFontPreset(rawValue: coverFontPreset) ?? CoverCopyPolicy(artStyle: currentArtStyle, profileDisplayName: name).coverFontPreset()
        let trimmedTitle = bookDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleForPrint = trimmedTitle.isEmpty ? CoverCopyPolicy(artStyle: currentArtStyle, profileDisplayName: name).defaultBookTitle() : trimmedTitle
        let pitch = backCoverPitch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CoverCopyPolicy(artStyle: currentArtStyle, profileDisplayName: name).fallbackBackCoverPitch(bookTitle: titleForPrint)
            : backCoverPitch
        let customTrimmed = customArtStyleText.trimmingCharacters(in: .whitespacesAndNewlines)
        return FirestoreSyncService.CoverInputs(
            headshot: subjectPhoto,
            profileName: name.isEmpty ? "Narrator" : name,
            ethnicity: ethnicity.isEmpty ? nil : ethnicity,
            gender: gender.isEmpty ? nil : gender,
            memoryThemes: rankedThemes,
            artStyle: currentArtStyle,
            customArtStyleText: customTrimmed.isEmpty ? nil : customTrimmed,
            printTitle: titleForPrint,
            backCoverPitch: pitch,
            coverFontPreset: preset
        )
    }

    /// Re-uploads pages + cover when the user edits the print title after the initial sync.
    func resyncPrintPackagingAfterTitleEdit() async {
        syncBookendTitleFromDisplayTitle()
        await saveCurrentBookInPlace(reason: "printTitle")
    }

    /// Assembles a `PersistableStorybook` and normalizes empty display title / back-cover copy in memory.
    private func buildPersistableStorybookForSave(profileID: UUID, createdAt: Date) -> PersistableStorybook? {
        guard !pageItems.isEmpty else { return nil }
        let persistableItems = persistablePageItemsFromCurrentState()
        let trimmedTitle = bookDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let policy = CoverCopyPolicy(artStyle: currentArtStyle, profileDisplayName: profileName ?? "")
        let titleStored = trimmedTitle.isEmpty ? policy.defaultBookTitle() : trimmedTitle
        let pitchStored = backCoverPitch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? policy.fallbackBackCoverPitch(bookTitle: titleStored)
            : backCoverPitch
        let presetStored = coverFontPreset.isEmpty ? policy.coverFontPreset().rawValue : coverFontPreset
        if bookDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bookDisplayTitle = titleStored
        }
        if backCoverPitch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            backCoverPitch = pitchStored
        }
        return PersistableStorybook(
            profileID: profileID,
            pageItems: persistableItems,
            artStyle: artStyleRaw,
            createdAt: createdAt,
            bookDisplayTitle: titleStored,
            backCoverPitch: pitchStored,
            coverFontPreset: presetStored
        )
    }

    /// Encodes a storybook, writes to disk, optional iCloud, and when `appendToHistory` is true, appends history files + iCloud history metadata. Does not sync to Firestore.
    private func writeStorybookToLocalAndICloudCaches(
        _ storybookData: PersistableStorybook,
        profileID: UUID,
        appendToHistory: Bool
    ) throws {
        let encoder = JSONEncoder()
        var data = try encoder.encode(storybookData)
        var dataSizeMB = Double(data.count) / (1024 * 1024)

        // Save to Application Support (avoids multi‑MB UserDefaults / CFPreferences failures)
        do {
            try StorybookLocalStore.writeCurrentBook(data: data, profileID: profileID)
            if appendToHistory {
                try StorybookLocalStore.appendHistory(data: data, profileID: profileID)
            }
        } catch {
            print("❌ Local storybook file cache failed (continuing with cloud/Firebase): \(error.localizedDescription)")
        }

        let cloudStore = NSUbiquitousKeyValueStore.default
        let cloudKey = "memoir_storybook_\(profileID.uuidString)"
        let cloudHistoryKey = "memoir_storybook_history_\(profileID.uuidString)"
        let createdAt = storybookData.createdAt
        if dataSizeMB < 0.95 {
            cloudStore.set(data, forKey: cloudKey)
            print("✅ Storybook synced to iCloud (\(String(format: "%.2f", dataSizeMB))MB)")
        } else {
            print("⚠️ Storybook large (\(String(format: "%.2f", dataSizeMB))MB), trying aggressive compression")
            let compressedItems = storybookData.pageItems.map { item -> PersistablePageItem in
                if item.type == "illustration", let imageData = item.imageData,
                   let image = UIImage(data: imageData),
                   let compressedData = image.jpegData(compressionQuality: 0.6) {
                    return PersistablePageItem(
                        type: item.type,
                        imageData: compressedData,
                        caption: item.caption,
                        title: item.title,
                        subtitle: item.subtitle,
                        textContent: item.textContent,
                        url: item.url,
                        pageIndex: item.pageIndex,
                        totalPages: item.totalPages
                    )
                }
                return item
            }
            let compressedStorybook = PersistableStorybook(
                profileID: storybookData.profileID,
                pageItems: compressedItems,
                artStyle: storybookData.artStyle,
                createdAt: storybookData.createdAt,
                bookDisplayTitle: storybookData.bookDisplayTitle,
                backCoverPitch: storybookData.backCoverPitch,
                coverFontPreset: storybookData.coverFontPreset
            )
            if let compressedData = try? encoder.encode(compressedStorybook),
               Double(compressedData.count) / (1024 * 1024) < 0.95 {
                data = compressedData
                dataSizeMB = Double(data.count) / (1024 * 1024)
                cloudStore.set(data, forKey: cloudKey)
                do {
                    try StorybookLocalStore.writeCurrentBook(data: data, profileID: profileID)
                } catch {
                    print("⚠️ Could not write compressed current book to disk: \(error.localizedDescription)")
                }
                print("✅ Storybook synced to iCloud with compression (\(String(format: "%.2f", dataSizeMB))MB)")
            } else {
                print("⚠️ Storybook still too large even after compression, storing metadata only")
            }
        }
        if appendToHistory {
            let historyMetadataKey = "\(cloudHistoryKey)_metadata"
            var historyMetadata: [[String: Any]] = cloudStore.array(forKey: historyMetadataKey) as? [[String: Any]] ?? []
            historyMetadata.append([
                "createdAt": createdAt.timeIntervalSince1970,
                "artStyle": artStyleRaw,
                "profileID": profileID.uuidString
            ])
            cloudStore.set(historyMetadata, forKey: historyMetadataKey)
        }
        cloudStore.synchronize()
    }

    /// Re-syncs the current book in place: same `bookVersionId` / `createdAt` as the last cloud sync (no new Firestore doc, no new history file).
    func saveCurrentBookInPlace(reason: String) async {
        if isResumingPendingBookSync {
            for _ in 0..<100 {
                if !isResumingPendingBookSync { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        guard let bookId = lastSyncedBookVersionId,
              let bookCreatedAt = lastPersistedBookCreatedAt,
              let profileID = currentProfileID,
              !pageItems.isEmpty
        else {
            if let profileID = currentProfileID, !pageItems.isEmpty {
                print("[Storybook] saveCurrentBookInPlace(\(reason)) — no lastSynced id; new book version via persistStorybook")
                persistStorybook(for: profileID)
            }
            return
        }
        guard let storybookData = buildPersistableStorybookForSave(profileID: profileID, createdAt: bookCreatedAt) else { return }
        do {
            try writeStorybookToLocalAndICloudCaches(storybookData, profileID: profileID, appendToHistory: false)
        } catch {
            print("❌ saveCurrentBookInPlace: encode/cache failed: \(error)")
        }
        hasGeneratedStorybook = true
        let layout = BookVersionLayoutFactory.layout(forArtStyle: artStyleRaw)
        loadedBookOrientation = layout.orientation
        loadedBookPageWidth = CGFloat(layout.pageWidth)
        loadedBookPageHeight = CGFloat(layout.pageHeight)
        print("[StorybookLoad] saveCurrentBookInPlace reason=\(reason) id=\(bookId.prefix(28))… pageItems=\(pageItems.count)")
        let renderedPages = renderCurrentBookPagesAsImages()
        if renderedPages.count != pageItems.count {
            print("⚠️ Rendered page count (\(renderedPages.count)) != pageItems count (\(pageItems.count)); sync may use fallbacks for missing pages")
        }
        let coverInputs = makeCoverInputsIfAvailable()
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MemoirAI.BookInPlace") {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        defer {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        await FirestoreSyncService.shared.syncBook(
            storybookData,
            bookId: bookId,
            renderedPageImages: renderedPages,
            coverInputs: coverInputs
        )
        if let updated = await FirestoreSyncService.shared.fetchBookVersion(bookVersionId: bookId) {
            currentBookVersionRecord = updated
        }
    }

    /// New book version (first full generation only): appends local + iCloud history, registers pending sync, queues a cloud sync.
    private func persistStorybook(for profileID: UUID, reservedCreatedAt: Date? = nil, reservedBookVersionId: String? = nil) {
        let createdAt = reservedCreatedAt ?? Date()
        let bookVersionId: String
        if let b = reservedBookVersionId, let t = reservedCreatedAt {
            bookVersionId = b
            if lastSyncedBookVersionId != b {
                lastSyncedBookVersionId = b
            }
            if lastPersistedBookCreatedAt != t {
                lastPersistedBookCreatedAt = t
            }
        } else {
            bookVersionId = "\(profileID.uuidString)_\(Int(createdAt.timeIntervalSince1970))"
            lastSyncedBookVersionId = bookVersionId
            lastPersistedBookCreatedAt = createdAt
        }
        guard let storybookData = buildPersistableStorybookForSave(profileID: profileID, createdAt: createdAt) else { return }
        do {
            try writeStorybookToLocalAndICloudCaches(storybookData, profileID: profileID, appendToHistory: true)
        } catch {
            print("❌ persistStorybook: cache write failed: \(error)")
        }
        hasGeneratedStorybook = true
        let layout = BookVersionLayoutFactory.layout(forArtStyle: artStyleRaw)
        loadedBookOrientation = layout.orientation
        loadedBookPageWidth = CGFloat(layout.pageWidth)
        loadedBookPageHeight = CGFloat(layout.pageHeight)
        print("[StorybookLoad] persistStorybook (new) sync queued id=\(bookVersionId.prefix(28))… createdAt=\(createdAt.timeIntervalSince1970) pageItems=\(pageItems.count)")
        let renderedPages = renderCurrentBookPagesAsImages()
        if renderedPages.count != pageItems.count {
            print("⚠️ Rendered page count (\(renderedPages.count)) != pageItems count (\(pageItems.count)); sync may use fallbacks for missing pages")
        }
        let coverInputs = makeCoverInputsIfAvailable()
        FirestoreSyncService.shared.registerPendingBookSyncForProfile(bookId: bookVersionId, profileId: profileID)
        FirestoreSyncService.shared.queueBookSync(
            storybookData,
            bookId: bookVersionId,
            renderedPageImages: renderedPages,
            coverInputs: coverInputs
        )
        print("✅ Storybook persisted for profile: \(profileID) (\(renderedPages.count) pages → Firebase)")
    }
    
    private func loadPersistedStorybook(for profileID: UUID) {
        var data: Data?
        
        // 1️⃣ Local file cache (+ one-shot migration from legacy UserDefaults)
        if let localData = StorybookLocalStore.readCurrentBookData(profileID: profileID) {
            data = localData
        }
        // 2️⃣ iCloud Key-Value Store (restored after reinstall; small books only)
        else {
            let cloudStore = NSUbiquitousKeyValueStore.default
            cloudStore.synchronize()
            
            let cloudKey = "memoir_storybook_\(profileID.uuidString)"
            
            // Check if stored as data in iCloud KVS
            if let cloudData = cloudStore.data(forKey: cloudKey) {
                data = cloudData
                try? StorybookLocalStore.writeCurrentBook(data: cloudData, profileID: profileID)
                print("🔄 Restored storybook from iCloud backup")
            }
        }
        
        guard let storybookData = data else {
            hasGeneratedStorybook = false
            isVisualBookReady = false
            return
        }
        
        let decoder = JSONDecoder()
        do {
            let storybook = try decoder.decode(PersistableStorybook.self, from: storybookData)
            let layout = BookVersionLayoutFactory.layout(forArtStyle: storybook.artStyle)
            loadedBookOrientation = layout.orientation
            loadedBookPageWidth = CGFloat(layout.pageWidth)
            loadedBookPageHeight = CGFloat(layout.pageHeight)
            
            // Convert back to PageItems
            pageItems = storybook.pageItems.compactMap { persistableItem in
                // Extract memoryID from URL if present
                var memoryID: UUID?
                if let urlString = persistableItem.url,
                   let url = URL(string: urlString),
                   url.scheme == "memoirai",
                   url.host == "memory" {
                    let pathComponents = url.pathComponents
                    if pathComponents.count > 1 {
                        memoryID = UUID(uuidString: pathComponents[1])
                    }
                }
                // Fallback to generating a new UUID if not found
                let finalMemoryID = memoryID ?? UUID()
                
                switch persistableItem.type {
                case "illustration":
                    guard let imageData = persistableItem.imageData,
                          let image = UIImage(data: imageData) else { return nil }
                    return PageItem.illustration(
                        image: image,
                        memoryID: finalMemoryID,
                        title: persistableItem.title
                    )
                    
                case "textPage":
                    guard let textContent = persistableItem.textContent else { return nil }
                    return PageItem.textPage(
                        index: persistableItem.pageIndex ?? 1,
                        total: persistableItem.totalPages ?? 1,
                        body: textContent,
                        title: persistableItem.title,
                        subtitle: persistableItem.subtitle,
                        memoryID: finalMemoryID
                    )
                    
                case "qrCode":
                    // Legacy QR code pages - skip them (QR is now on every page)
                    return nil
                    
                default:
                    return nil
                }
            }
            
            precomposedIllustrationMemoryIDs = []
            
            bookDisplayTitle = storybook.bookDisplayTitle ?? ""
            backCoverPitch = storybook.backCoverPitch ?? ""
            coverFontPreset = storybook.coverFontPreset
                ?? CoverCopyPolicy(artStyle: ArtStyle(rawValue: storybook.artStyle) ?? .kidsBook, profileDisplayName: "").coverFontPreset().rawValue
            ensureInteriorBookendsPresent()
            backfillContinuationTextPageHeaders()
            lastSyncedBookVersionId = "\(storybook.profileID.uuidString)_\(Int(storybook.createdAt.timeIntervalSince1970))"
            lastPersistedBookCreatedAt = storybook.createdAt

            hasGeneratedStorybook = true
            isVisualBookReady = true
            print("✅ Storybook loaded for profile: \(profileID)")
            print("[StorybookLoad] loadPersistedStorybook disk createdAt=\(storybook.createdAt.timeIntervalSince1970) pageItems=\(pageItems.count) versionHint=\(lastSyncedBookVersionId?.prefix(28) ?? "nil")…")
        } catch {
            print("❌ Failed to load persisted storybook: \(error)")
            hasGeneratedStorybook = false
            isVisualBookReady = false
        }
    }
    
    /// `createdAt` of on-disk `current.book` for this profile, if decodable.
    private func localPersistedStorybookCreatedAt(for profileID: UUID) -> Date? {
        guard let data = StorybookLocalStore.readCurrentBookData(profileID: profileID),
              let book = try? JSONDecoder().decode(PersistableStorybook.self, from: data) else {
            return nil
        }
        return book.createdAt
    }

    private func loadLatestBookVersionFromCloud(for profileID: UUID) async -> Bool {
        guard let record = await FirestoreSyncService.shared.fetchLatestBookVersion(profileID: profileID) else {
            print("[StorybookLoad] fetchLatestBookVersion → nil")
            return false
        }
        let cloudCreated = record.createdAt
        let cloudId = record.bookVersionId
        print("[StorybookLoad] fetchLatest id=\(cloudId.prefix(28))… createdAt=\(cloudCreated.timeIntervalSince1970) pages=\(record.pageCount) isLoading=\(isLoading)")

        let applyOutcome = StorybookCloudApplyPolicy.outcome(
            isLoading: isLoading,
            localPersistedBookCreatedAt: localPersistedStorybookCreatedAt(for: profileID),
            record: record
        )
        switch applyOutcome {
        case .shouldApply:
            break
        case .skipBecauseGenerating:
            print("[StorybookLoad] SKIP applyBookVersionRecord (isLoading) — avoid racing generateStorybook")
            return false
        case .skipBecauseLocalPersistedBookIsNewer(let localCreated, let cloudCreated, let delta):
            print("[StorybookLoad] SKIP applyBookVersionRecord — local current.book newer by \(String(format: "%.1f", delta))s (local=\(localCreated.timeIntervalSince1970) cloud=\(cloudCreated.timeIntervalSince1970))")
            return false
        case .skipBecauseCloudIsPartial(let inArray, let count):
            print("[StorybookLoad] SKIP applyBookVersionRecord — cloud book partial (pages.count=\(inArray) < pageCount=\(count)) id=\(cloudId.prefix(28))")
            return false
        }

        await applyBookVersionRecord(record)
        return true
    }
    
    func loadBookVersionRecord(_ record: BookVersionRecord) {
        Task {
            await applyBookVersionRecord(record)
        }
    }

    /// Fetch the current on-screen book version when possible, then fall back to latest for the profile.
    /// This avoids checking print readiness against a different newer/older book than the one being viewed.
    func fetchCurrentBookVersionRecord() async -> BookVersionRecord? {
        guard let current = currentBookVersionRecord else {
            guard let profileID = currentProfileID else { return nil }
            let latest = await FirestoreSyncService.shared.fetchLatestBookVersion(profileID: profileID)
            if let latest {
                await MainActor.run { currentBookVersionRecord = latest }
            }
            return latest
        }

        if let exact = await FirestoreSyncService.shared.fetchBookVersion(bookVersionId: current.bookVersionId) {
            await MainActor.run { currentBookVersionRecord = exact }
            return exact
        }

        // Exact fetch failed (e.g. transient network) — keep the in-memory book so order/checkout
        // cannot swap to an unrelated "latest" profile book with different cover art.
        return current
    }

    /// Publishes canonical print/readiness metadata from a `BookVersionRecord` (used after pages are ready for gallery loads, or up-front for normal cloud sync).
    private func applyCanonicalBookMetadataFromCloudRecord(_ record: BookVersionRecord) {
        currentBookVersionRecord = record
        isVisualBookReady = canonicalVisualReadiness(for: record)
        loadedBookOrientation = record.orientation
        loadedBookPageWidth = CGFloat(record.pageWidth)
        loadedBookPageHeight = CGFloat(record.pageHeight)
        if !isLoading {
            artStyleRaw = record.artStyle
        }
        bookDisplayTitle = record.printTitle ?? ""
        backCoverPitch = record.backCoverPitch ?? ""
        coverFontPreset = record.coverFontPreset
            ?? CoverCopyPolicy(artStyle: ArtStyle(rawValue: record.artStyle) ?? .kidsBook, profileDisplayName: "").coverFontPreset().rawValue
        lastSyncedBookVersionId = record.bookVersionId
        lastPersistedBookCreatedAt = record.createdAt
    }

    /// Same book already hydrated with real illustrations (not incremental placeholders) and matching cover revision — skip full download pass.
    private func canShortCircuitApplyBookVersionRecord(_ record: BookVersionRecord) -> Bool {
        guard lastSyncedBookVersionId == record.bookVersionId,
              !pageItems.isEmpty,
              !StorybookCloudApplyPolicy.isIncompleteCloudRecord(record) else { return false }
        guard let cur = currentBookVersionRecord,
              cur.bookVersionId == record.bookVersionId,
              cur.coverURL == record.coverURL,
              cur.coverThumbnailCacheRevision == record.coverThumbnailCacheRevision else { return false }
        guard record.pages.count == pageItems.count else { return false }
        guard illustrationReloadSources.isEmpty else { return false }
        for item in pageItems {
            guard case .illustration(let img, _, _) = item else { continue }
            if img.size.width <= 2, img.size.height <= 2 { return false }
        }
        return true
    }

    /// - Parameter galleryApplyToken: When non-`nil`, ties apply to `galleryBookLoadGeneration` / task cancellation so superseded selections never commit mixed state.
    ///   Canonical metadata is applied up front; `pageItems` is published with placeholder illustrations immediately for My Library loads (`isLoadingGalleryBook` clears before downloads finish).
    /// - Returns: `true` if `pageItems` were committed for this record.
    @discardableResult
    private func applyBookVersionRecord(_ record: BookVersionRecord, galleryApplyToken: UInt64? = nil) async -> Bool {
        print("[StorybookLoad] applyBookVersionRecord id=\(record.bookVersionId.prefix(28))… createdAt=\(record.createdAt.timeIntervalSince1970) pages=\(record.pages.count) isLoading=\(isLoading) hasPrintCoverPDF=\(record.printCoverPDFURL != nil) galleryToken=\(galleryApplyToken.map(String.init) ?? "nil")")
        if StorybookCloudApplyPolicy.isIncompleteCloudRecord(record) {
            print("⚠️ applyBookVersionRecord — incomplete cloud (pages in doc=\(record.pages.count), pageCount=\(record.pageCount)) — not applying; consider repair sync")
            if lastSyncedBookVersionId == record.bookVersionId, !pageItems.isEmpty, pageItems.count > record.pages.count {
                Task { await saveCurrentBookInPlace(reason: "repairPartialCloud") }
            }
            return false
        }

        if canShortCircuitApplyBookVersionRecord(record) {
            print("[StorybookLoad] applyBookVersionRecord SHORT-CIRCUIT same book=\(record.bookVersionId.prefix(20))…")
            applyCanonicalBookMetadataFromCloudRecord(record)
            enqueuePrefetchPrintCoverPanels(for: record)
            return true
        }

        let galleryToken = galleryApplyToken
        let isDeferredGalleryApply = galleryToken != nil

        func stillValidForGallery() -> Bool {
            guard let t = galleryToken else { return true }
            return t == galleryBookLoadGeneration && !Task.isCancelled
        }

        if isDeferredGalleryApply {
            guard stillValidForGallery() else { return false }
        }

        applyCanonicalBookMetadataFromCloudRecord(record)
        illustrationReloadSources = [:]

        let placeholderW = CGFloat(record.pageWidth)
        let placeholderH = CGFloat(record.pageHeight)
        let incrementalPh = Self.incrementalIllustrationPlaceholderUIImage()
        var deferredIllustrationReload: [UUID: BookVersionPageRecord] = [:]

        let sortedPages = record.pages.sorted(by: { $0.pageIndex < $1.pageIndex })
        var slots: [PageItem?] = Array(repeating: nil, count: sortedPages.count)
        var precomposedMemoryIDs: Set<UUID> = []

        for (idx, page) in sortedPages.enumerated() {
            let memoryUUID = UUID(uuidString: page.memoryId ?? "") ?? UUID()
            if page.type == "textPage" {
                let text = page.textContent ?? ""
                slots[idx] = .textPage(
                    index: page.pageIndex + 1,
                    total: max(1, record.pageCount),
                    body: text,
                    title: page.title,
                    subtitle: page.subtitle,
                    memoryID: memoryUUID
                )
            } else if page.type == "illustration" {
                slots[idx] = .illustration(image: incrementalPh, memoryID: memoryUUID, title: page.title)
            }
        }

        struct IllustrationPageWork {
            let slotIndex: Int
            let page: BookVersionPageRecord
            let memoryUUID: UUID
        }
        let illustrationWork: [IllustrationPageWork] = sortedPages.enumerated().compactMap { idx, page in
            guard page.type == "illustration" else { return nil }
            let memoryUUID = UUID(uuidString: page.memoryId ?? "") ?? UUID()
            return IllustrationPageWork(slotIndex: idx, page: page, memoryUUID: memoryUUID)
        }

        let rebuilt = slots.compactMap { $0 }

        guard !rebuilt.isEmpty else {
            print("⚠️ Cloud book version \(record.bookVersionId) had no reconstructable pages")
            if isDeferredGalleryApply, stillValidForGallery(), !record.pages.isEmpty {
                errorMessage = "This book couldn’t be opened — its saved pages don’t match what we expect. Try another book or contact support if this keeps happening."
            }
            return false
        }

        guard stillValidForGallery() else {
            print("[StorybookLoad] applyBookVersionRecord discarding slot publish (stale gallery token)")
            return false
        }

        if !pageItems.isEmpty, rebuilt.count < pageItems.count, lastSyncedBookVersionId == record.bookVersionId {
            print("⚠️ applyBookVersionRecord — would shrink in-memory book from \(pageItems.count) to \(rebuilt.count) for id=\(record.bookVersionId.prefix(24))…; refusing & repairing cloud from local state")
            Task { await saveCurrentBookInPlace(reason: "repairShorterCloudRebuild") }
            return false
        }

        pageItems = rebuilt
        precomposedIllustrationMemoryIDs = []
        ensureInteriorBookendsPresent()
        backfillContinuationTextPageHeaders()

        hasGeneratedStorybook = true

        if isDeferredGalleryApply, stillValidForGallery() {
            isLoadingGalleryBook = false
        }

        print("✅ Published storybook slots id=\(record.bookVersionId) count=\(rebuilt.count) (illustrations streaming…)")
        enqueuePrefetchPrintCoverPanels(for: record)

        let bookVersionId = record.bookVersionId
        /// Parallelize cloud illustration fetches (sequential was very slow for large books). Chunked to avoid hundreds of simultaneous connections.
        let parallelIllustrationChunk = 6
        for chunkStart in stride(from: 0, to: illustrationWork.count, by: parallelIllustrationChunk) {
            guard stillValidForGallery() else {
                print("[StorybookLoad] applyBookVersionRecord aborted mid-load (superseded My Library selection or cancellation)")
                return false
            }
            let end = min(chunkStart + parallelIllustrationChunk, illustrationWork.count)
            let chunk = Array(illustrationWork[chunkStart..<end])
            await withTaskGroup(of: (Int, PageItem, UUID, Bool, BookVersionPageRecord?).self) { group in
                for item in chunk {
                    group.addTask { [weak self] in
                        guard let self else {
                            let ph = Self.makeCloudIllustrationPlaceholderUIImage(pageWidth: placeholderW, pageHeight: placeholderH)
                            return (item.slotIndex, PageItem.illustration(image: ph, memoryID: item.memoryUUID, title: item.page.title), item.memoryUUID, false, item.page)
                        }
                        if let result = await self.fetchIllustrationImage(
                            for: item.page,
                            memoryUUID: item.memoryUUID,
                            bookVersionId: bookVersionId
                        ) {
                            return (
                                item.slotIndex,
                                PageItem.illustration(image: result.image, memoryID: item.memoryUUID, title: item.page.title),
                                item.memoryUUID,
                                result.precomposed,
                                nil
                            )
                        }
                        let placeholder = Self.makeCloudIllustrationPlaceholderUIImage(pageWidth: placeholderW, pageHeight: placeholderH)
                        print(
                            "📥 [IllustrationDownload] placeholder pageIndex=\(item.page.pageIndex) mem=\(item.memoryUUID.uuidString.prefix(8)) book=\(bookVersionId.prefix(12))"
                        )
                        return (
                            item.slotIndex,
                            PageItem.illustration(image: placeholder, memoryID: item.memoryUUID, title: item.page.title),
                            item.memoryUUID,
                            false,
                            item.page
                        )
                    }
                }
                for await (slotIndex, pageItem, mem, precomposed, failedPage) in group {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        guard stillValidForGallery() else { return }
                        guard pageItems.indices.contains(slotIndex) else { return }
                        pageItems[slotIndex] = pageItem
                        if precomposed {
                            precomposedMemoryIDs.insert(mem)
                        }
                        if let fp = failedPage {
                            if isDeferredGalleryApply {
                                deferredIllustrationReload[mem] = fp
                            } else {
                                illustrationReloadSources[mem] = fp
                            }
                        }
                    }
                }
            }
        }

        guard stillValidForGallery() else {
            print("[StorybookLoad] applyBookVersionRecord discarding illustration stream results (stale gallery token)")
            return false
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            guard stillValidForGallery() else { return }
            if isDeferredGalleryApply {
                illustrationReloadSources = deferredIllustrationReload
            }
            precomposedIllustrationMemoryIDs = precomposedMemoryIDs
            ensureInteriorBookendsPresent()
            backfillContinuationTextPageHeaders()
        }

        print("✅ Loaded cloud book version \(record.bookVersionId) with \(pageItems.count) pages (illustrations resolved)")

        return true
    }

    /// Monotonic token + structured task so superseded My Library selections never commit mixed state or clear the spinner for the wrong load.
    private var galleryBookLoadGeneration: UInt64 = 0
    private var galleryBookLoadTask: Task<Void, Never>?

    /// Load a book from My Library: always apply canonical Firestore record (print metadata), then overlay local illustration bytes when matched legacy is present.
    @Published var isLoadingGalleryBook: Bool = false

    func loadGalleryBook(record: BookVersionRecord, legacyBook: PersistableStorybook?) {
        galleryBookLoadTask?.cancel()
        galleryBookLoadGeneration &+= 1
        let token = galleryBookLoadGeneration
        print("🧭 VM loadGalleryBook start: id=\(record.bookVersionId), source=\(record.source), pages=\(record.pageCount), hasLegacy=\(legacyBook != nil) token=\(token)")
        print("[StorybookLoad] loadGalleryBook record.createdAt=\(record.createdAt.timeIntervalSince1970) bookVersionId=\(record.bookVersionId.prefix(28))…")
        errorMessage = nil
        isLoadingGalleryBook = true
        galleryBookLoadTask = Task { @MainActor in
            defer {
                if token == galleryBookLoadGeneration {
                    isLoadingGalleryBook = false
                }
            }
            guard token == galleryBookLoadGeneration, !Task.isCancelled else { return }
            skippedMemoriesDuringGeneration = []
            let committed = await applyBookVersionRecord(record, galleryApplyToken: token)
            guard token == galleryBookLoadGeneration, !Task.isCancelled else { return }
            if !committed {
                if record.pages.isEmpty, let legacy = legacyBook, !legacy.pageItems.isEmpty {
                    applyLegacyBookFallback(from: legacy, cloudRecord: record)
                    print("🧭 VM loadGalleryBook recovered from local disk (cloud pages empty); re-queued sync id=\(record.bookVersionId)")
                    FirestoreSyncService.shared.queueBookSync(legacy, bookId: record.bookVersionId)
                } else if record.pages.isEmpty, legacyBook == nil {
                    errorMessage = "This book’s upload was interrupted before it finished saving to the cloud. Regenerate the storybook on this device, or open it from a device that still has the original copy."
                    print("🧭 VM loadGalleryBook no cloud pages and no local match for id=\(record.bookVersionId)")
                } else {
                    print("🧭 VM loadGalleryBook skip legacy merge (apply did not commit this record)")
                }
                return
            }
            guard currentBookVersionRecord?.bookVersionId == record.bookVersionId else {
                print("🧭 VM loadGalleryBook record mismatch after apply")
                return
            }
            if let legacy = legacyBook {
                mergeLegacyIllustrationData(from: legacy)
                print("🧭 VM loadGalleryBook merged legacy image bytes for id=\(record.bookVersionId)")
            }
            print("🧭 VM loadGalleryBook end: pageItems=\(pageItems.count), illustrations=\(storybookGeneratedIllustrationCount), hasGeneratedStorybook=\(hasGeneratedStorybook)")
        }
    }

    /// When Firestore has no `pages` rows yet (interrupted sync) but this device still has the full `PersistableStorybook`, load locally and let `queueBookSync` repair the cloud doc.
    private func applyLegacyBookFallback(from legacy: PersistableStorybook, cloudRecord: BookVersionRecord) {
        applyCanonicalBookMetadataFromCloudRecord(cloudRecord)
        let layout = BookVersionLayoutFactory.layout(forArtStyle: legacy.artStyle)
        loadedBookOrientation = layout.orientation
        loadedBookPageWidth = CGFloat(layout.pageWidth)
        loadedBookPageHeight = CGFloat(layout.pageHeight)

        pageItems = legacy.pageItems.compactMap { persistableItem in
            var memoryID: UUID?
            if let urlString = persistableItem.url,
               let url = URL(string: urlString),
               url.scheme == "memoirai",
               url.host == "memory" {
                let pathComponents = url.pathComponents
                if pathComponents.count > 1 {
                    memoryID = UUID(uuidString: pathComponents[1])
                }
            }
            let finalMemoryID = memoryID ?? UUID()
            switch persistableItem.type {
            case "illustration":
                guard let imageData = persistableItem.imageData,
                      let image = UIImage(data: imageData) else { return nil }
                return PageItem.illustration(image: image, memoryID: finalMemoryID, title: persistableItem.title)
            case "textPage":
                let body = persistableItem.textContent ?? ""
                return PageItem.textPage(
                    index: persistableItem.pageIndex ?? 1,
                    total: persistableItem.totalPages ?? max(1, legacy.pageItems.count),
                    body: body,
                    title: persistableItem.title,
                    subtitle: persistableItem.subtitle,
                    memoryID: finalMemoryID
                )
            case "qrCode":
                return nil
            default:
                return nil
            }
        }
        precomposedIllustrationMemoryIDs = []
        illustrationReloadSources = [:]
        illustrationRetryInProgress = []

        if (cloudRecord.printTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let localTitle = legacy.bookDisplayTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !localTitle.isEmpty {
            bookDisplayTitle = localTitle
        }
        if (cloudRecord.backCoverPitch ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let pitch = legacy.backCoverPitch?.trimmingCharacters(in: .whitespacesAndNewlines), !pitch.isEmpty {
            backCoverPitch = pitch
        }
        if cloudRecord.coverFontPreset == nil || (cloudRecord.coverFontPreset ?? "").isEmpty {
            coverFontPreset = legacy.coverFontPreset
                ?? CoverCopyPolicy(artStyle: ArtStyle(rawValue: legacy.artStyle) ?? .kidsBook, profileDisplayName: bookDisplayTitle).coverFontPreset().rawValue
        }

        ensureInteriorBookendsPresent()
        backfillContinuationTextPageHeaders()
        lastSyncedBookVersionId = cloudRecord.bookVersionId
        lastPersistedBookCreatedAt = legacy.createdAt
        hasGeneratedStorybook = true
        isVisualBookReady = true
        errorMessage = nil
        print("[StorybookLoad] applyLegacyBookFallback pageItems=\(pageItems.count) bookVersionId=\(cloudRecord.bookVersionId.prefix(28))…")
    }

    private func mergeLegacyIllustrationData(from legacy: PersistableStorybook) {
        let legacyItems = legacy.pageItems
        guard !legacyItems.isEmpty, !pageItems.isEmpty else { return }

        var newItems: [PageItem] = []
        for (idx, item) in pageItems.enumerated() {
            guard idx < legacyItems.count else {
                newItems.append(item)
                continue
            }
            let legacyItem = legacyItems[idx]
            if legacyItem.type == "illustration",
               let data = legacyItem.imageData,
               let img = UIImage(data: data) {
                if case .illustration(_, let memoryID, let title) = item {
                    newItems.append(.illustration(image: img, memoryID: memoryID, title: title))
                    precomposedIllustrationMemoryIDs.remove(memoryID)
                    illustrationReloadSources.removeValue(forKey: memoryID)
                    continue
                }
            }
            newItems.append(item)
        }
        pageItems = newItems
        backfillContinuationTextPageHeaders()
    }
    
    func isPrecomposedIllustration(memoryID: UUID) -> Bool {
        precomposedIllustrationMemoryIDs.contains(memoryID)
    }
    
    private struct IllustrationURLCandidate {
        let url: String
        let precomposed: Bool
    }
    
    private func illustrationURLCandidates(for page: BookVersionPageRecord) -> [IllustrationURLCandidate] {
        var candidates: [IllustrationURLCandidate] = []
        var seen = Set<String>()
        
        func add(_ url: String?, precomposed: Bool) {
            guard let raw = url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
            guard !raw.lowercased().contains(".pdf") else { return }
            guard seen.insert(raw).inserted else { return }
            candidates.append(IllustrationURLCandidate(url: raw, precomposed: precomposed))
        }
        
        // Prefer full-page PNG first. JPEG `imageURL` is often the same composed snapshot as `renderedPageURL`
        // but its Storage path does not contain "rendered", which used to mark it non-precomposed and caused double title/QR in the live reader.
        add(page.renderedPageURL, precomposed: true)
        let hasRenderedURL = !(page.renderedPageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        let imagePrecomposed = hasRenderedURL || (page.imageURL ?? "").lowercased().contains("rendered")
        add(page.imageURL, precomposed: imagePrecomposed)
        return candidates
    }

    /// Loads an illustration from cached Firestore URLs (with retries), then fresh Storage-signed URLs by path.
    private func fetchIllustrationImage(
        for page: BookVersionPageRecord,
        memoryUUID: UUID,
        bookVersionId: String
    ) async -> (image: UIImage, precomposed: Bool)? {
        if Task.isCancelled { return nil }
        let ctx = "book=\(bookVersionId.prefix(10)) pageIdx=\(page.pageIndex) mem=\(memoryUUID.uuidString.prefix(8))"

        let diskKey = "\(bookVersionId)|\(page.pageIndex)|\(memoryUUID.uuidString)"
        if let hit = IllustrationImageDiskCache.shared.image(forKey: diskKey) {
            let precomposed = !(page.renderedPageStoragePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
                || !(page.renderedPageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
            return (hit, precomposed)
        }

        for candidate in illustrationURLCandidates(for: page) {
            if Task.isCancelled { return nil }
            let label = "\(ctx) source=firestoreURL precomposed=\(candidate.precomposed)"
            if let data = await downloadImageData(from: candidate.url, context: label, maxAttempts: 3),
               let image = UIImage(data: data) {
                IllustrationImageDiskCache.shared.store(image: image, forKey: diskKey)
                return (image, candidate.precomposed)
            }
        }

        if let path = page.renderedPageStoragePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            do {
                let fresh = try await StorageService.shared.freshDownloadURL(forStoragePath: path)
                let label = "\(ctx) source=freshStoragePath kind=png precomposed=true"
                if let data = await downloadImageData(from: fresh.absoluteString, context: label, maxAttempts: 3),
                   let image = UIImage(data: data) {
                    IllustrationImageDiskCache.shared.store(image: image, forKey: diskKey)
                    return (image, true)
                }
            } catch {
                print("[IllustrationDownload] \(ctx) fresh png path failed: \(error.localizedDescription)")
            }
        }

        let jpegIsPrecomposed = !(page.renderedPageStoragePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        if let path = page.imageStoragePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            do {
                let fresh = try await StorageService.shared.freshDownloadURL(forStoragePath: path)
                let label = "\(ctx) source=freshStoragePath kind=jpeg precomposed=\(jpegIsPrecomposed)"
                if let data = await downloadImageData(from: fresh.absoluteString, context: label, maxAttempts: 3),
                   let image = UIImage(data: data) {
                    IllustrationImageDiskCache.shared.store(image: image, forKey: diskKey)
                    return (image, jpegIsPrecomposed)
                }
            } catch {
                print("[IllustrationDownload] \(ctx) fresh jpeg path failed: \(error.localizedDescription)")
            }
        }


        print("📥 [IllustrationDownload] FAILED all sources \(ctx)")
        return nil
    }

    /// 1×1 paper-colored bitmap used as a lightweight slot until a real illustration is decoded (gallery incremental load).
    private nonisolated static func incrementalIllustrationPlaceholderUIImage() -> UIImage {
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Safe to call from concurrent download tasks (not MainActor-isolated).
    private nonisolated static func makeCloudIllustrationPlaceholderUIImage(pageWidth: CGFloat, pageHeight: CGFloat) -> UIImage {
        let w = max(pageWidth, 100)
        let h = max(pageHeight, 100)
        let size = CGSize(width: w, height: h)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.94, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let fontSize = min(w, h) * 0.038
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: paragraph
            ]
            let text = "Illustration couldn’t load from iCloud.\nTap Retry to download again."
            let rect = CGRect(x: 32, y: h / 2 - 70, width: w - 64, height: 140)
            text.draw(in: rect, withAttributes: attrs)
        }
    }

    private func cloudIllustrationPlaceholderImage(pageWidth: CGFloat? = nil, pageHeight: CGFloat? = nil) -> UIImage {
        let w = pageWidth ?? loadedBookPageWidth ?? 612
        let h = pageHeight ?? loadedBookPageHeight ?? 792
        return Self.makeCloudIllustrationPlaceholderUIImage(pageWidth: w, pageHeight: h)
    }

    private func replaceIllustration(memoryID: UUID, image: UIImage, precomposed: Bool) {
        var newItems = pageItems
        for i in newItems.indices {
            guard case .illustration(_, let mid, let title) = newItems[i], mid == memoryID else { continue }
            newItems[i] = .illustration(image: image, memoryID: memoryID, title: title)
            break
        }
        pageItems = newItems
        if precomposed {
            precomposedIllustrationMemoryIDs.insert(memoryID)
        } else {
            precomposedIllustrationMemoryIDs.remove(memoryID)
        }
    }

    func needsCloudIllustrationReload(memoryID: UUID) -> Bool {
        illustrationReloadSources[memoryID] != nil
    }

    func isCloudIllustrationRetrying(memoryID: UUID) -> Bool {
        illustrationRetryInProgress.contains(memoryID)
    }

    /// Retries download using the same pipeline as `fetchIllustrationImage` (Firestore URLs, then fresh Storage URLs).
    func retryCloudIllustrationLoad(memoryID: UUID) {
        guard let page = illustrationReloadSources[memoryID],
              let bookId = currentBookVersionRecord?.bookVersionId else { return }
        illustrationRetryInProgress.insert(memoryID)
        Task { @MainActor in
            defer { illustrationRetryInProgress.remove(memoryID) }
            if let result = await fetchIllustrationImage(for: page, memoryUUID: memoryID, bookVersionId: bookId) {
                replaceIllustration(memoryID: memoryID, image: result.image, precomposed: result.precomposed)
                illustrationReloadSources.removeValue(forKey: memoryID)
                print("📥 [IllustrationDownload] retry success mem=\(memoryID.uuidString.prefix(8))")
            } else {
                print("📥 [IllustrationDownload] retry still failed mem=\(memoryID.uuidString.prefix(8))")
            }
        }
    }

    private func downloadImageData(from urlString: String, context: String, maxAttempts: Int = 3) async -> Data? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased()) else {
            print("📥 [IllustrationDownload] invalid URL context=\(context)")
            return nil
        }

        for attempt in 1...maxAttempts {
            if Task.isCancelled {
                print("📥 [IllustrationDownload] cancelled context=\(context)")
                return nil
            }
            do {
                let (data, response) = try await Self.illustrationDownloadSession.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    print("📥 [IllustrationDownload] non-HTTP context=\(context) attempt=\(attempt)")
                    if attempt < maxAttempts { try await Task.sleep(nanoseconds: UInt64(300_000_000 * UInt64(attempt))) }
                    continue
                }
                if (200...299).contains(http.statusCode) {
                    guard !data.isEmpty else {
                        print("📥 [IllustrationDownload] empty body HTTP \(http.statusCode) context=\(context) attempt=\(attempt)")
                        if attempt < maxAttempts { try await Task.sleep(nanoseconds: UInt64(300_000_000 * UInt64(attempt))) }
                        continue
                    }
                    if attempt > 1 {
                        print("📥 [IllustrationDownload] success after retry context=\(context) attempt=\(attempt)")
                    }
                    return data
                }
                print("📥 [IllustrationDownload] HTTP \(http.statusCode) context=\(context) attempt=\(attempt)")
            } catch is CancellationError {
                print("📥 [IllustrationDownload] cancelled (URLSession) context=\(context)")
                return nil
            } catch {
                print("📥 [IllustrationDownload] error context=\(context) attempt=\(attempt) \(error.localizedDescription)")
            }
            if attempt < maxAttempts {
                let delayNs = UInt64(350_000_000 * UInt64(attempt))
                do {
                    try await Task.sleep(nanoseconds: delayNs)
                } catch is CancellationError {
                    return nil
                } catch {}
            }
        }
        return nil
    }
    
    private func migrateLegacyLocalBooksIfNeeded(for profileID: UUID) async {
        guard let userId = FirebaseConfig.shared.currentUserId else { return }
        
        let migrationKey = "book_versions_migrated_\(userId)_\(profileID.uuidString)"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }
        
        let historyDataArray = StorybookLocalStore.readHistoryDataArray(profileID: profileID)
        guard !historyDataArray.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        
        let decoder = JSONDecoder()
        let books = historyDataArray.compactMap { try? decoder.decode(PersistableStorybook.self, from: $0) }
        
        if books.isEmpty {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        
        for book in books {
            let bookVersionId = "\(profileID.uuidString)_\(Int(book.createdAt.timeIntervalSince1970))_legacy"
            await FirestoreSyncService.shared.syncBook(book, bookId: bookVersionId)
        }

        let backfilled = await FirestoreSyncService.shared.backfillBookVersionArtifacts(profileID: profileID, limit: 50)
        print("🧰 Artifact backfill triggered for \(backfilled) book versions")
        
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("✅ Migrated \(books.count) legacy local books to canonical book versions for \(profileID)")
    }

    /// Load a historic book from the gallery into the editor view
    func loadHistoricBook(_ book: PersistableStorybook) {
        // Convert PersistablePageItem[] to PageItem[] using the same logic as loadPersistedStorybook
        pageItems = book.pageItems.compactMap { persistableItem in
            // Extract memoryID from URL if present
            var memoryID: UUID?
            if let urlString = persistableItem.url,
               let url = URL(string: urlString),
               url.scheme == "memoirai",
               url.host == "memory" {
                let pathComponents = url.pathComponents
                if pathComponents.count > 1 {
                    memoryID = UUID(uuidString: pathComponents[1])
                }
            }
            // Fallback to generating a new UUID if not found
            let finalMemoryID = memoryID ?? UUID()
            
            switch persistableItem.type {
            case "illustration":
                guard let imageData = persistableItem.imageData,
                      let image = UIImage(data: imageData) else { return nil }
                return PageItem.illustration(
                    image: image,
                    memoryID: finalMemoryID,
                    title: persistableItem.title
                )
                
            case "textPage":
                guard let textContent = persistableItem.textContent else { return nil }
                return PageItem.textPage(
                    index: persistableItem.pageIndex ?? 1,
                    total: persistableItem.totalPages ?? 1,
                    body: textContent,
                    title: persistableItem.title,
                    subtitle: persistableItem.subtitle,
                    memoryID: finalMemoryID
                )
                
            case "qrCode":
                // Legacy QR code pages - skip them (QR is now on every page)
                return nil
                
            default:
                return nil
            }
        }
        precomposedIllustrationMemoryIDs = []
        
        // Update art style to match the loaded book (ensures correct layout/fonts)
        artStyleRaw = book.artStyle
        let layout = BookVersionLayoutFactory.layout(forArtStyle: book.artStyle)
        loadedBookOrientation = layout.orientation
        loadedBookPageWidth = CGFloat(layout.pageWidth)
        loadedBookPageHeight = CGFloat(layout.pageHeight)

        bookDisplayTitle = book.bookDisplayTitle ?? ""
        backCoverPitch = book.backCoverPitch ?? ""
        coverFontPreset = book.coverFontPreset
            ?? CoverCopyPolicy(artStyle: ArtStyle(rawValue: book.artStyle) ?? .kidsBook, profileDisplayName: "").coverFontPreset().rawValue
        lastSyncedBookVersionId = "\(book.profileID.uuidString)_\(Int(book.createdAt.timeIntervalSince1970))"
        lastPersistedBookCreatedAt = book.createdAt
        
        hasGeneratedStorybook = true
        backfillContinuationTextPageHeaders()
        print("✅ Historic book loaded into editor: \(book.createdAt)")
    }
    
    // MARK: - Text Measurement and Pagination
    
    /// Measure the height of text when rendered with given constraints
    private func measureTextHeight(_ text: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat = 0) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        
        let boundingBox = text.boundingRect(
            with: constraintRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return ceil(boundingBox.height)
    }
    
    /// Split text into pages that fit within the given height constraint
    private func splitTextToFitHeight(_ text: String, maxHeight: CGFloat, width: CGFloat, font: UIFont, lineSpacing: CGFloat = 0, paragraphSeparator: String = "\n\n") -> [String] {
        guard !text.isEmpty else { return [] }
        
        // Split text into paragraphs (preserve natural breaks)
        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        
        var pages: [String] = []
        var currentPageText: [String] = []
        var currentPageHeight: CGFloat = 0
        
        for paragraph in paragraphs {
            let paragraphHeight = measureTextHeight(paragraph, width: width, font: font, lineSpacing: lineSpacing)
            
            // If single paragraph exceeds page, split by sentences
            if paragraphHeight > maxHeight {
                // Flush current page if it has content
                if !currentPageText.isEmpty {
                    pages.append(currentPageText.joined(separator: paragraphSeparator))
                    currentPageText = []
                    currentPageHeight = 0
                }
                
                // Split paragraph by sentences (preserve punctuation)
                let sentenceEndings = CharacterSet(charactersIn: ".!?")
                var sentences: [String] = []
                var currentSentence = ""
                
                for char in paragraph {
                    currentSentence.append(char)
                    if String(char).rangeOfCharacter(from: sentenceEndings) != nil {
                        let trimmed = currentSentence.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            sentences.append(trimmed)
                        }
                        currentSentence = ""
                    }
                }
                // Add any remaining text
                if !currentSentence.trimmingCharacters(in: .whitespaces).isEmpty {
                    sentences.append(currentSentence.trimmingCharacters(in: .whitespaces))
                }
                
                var currentSentenceGroup: [String] = []
                var currentGroupHeight: CGFloat = 0
                
                for sentence in sentences {
                    let sentenceHeight = measureTextHeight(sentence, width: width, font: font, lineSpacing: lineSpacing)
                    
                    if currentGroupHeight + sentenceHeight > maxHeight && !currentSentenceGroup.isEmpty {
                        // Current group exceeds page, save it and start new page
                        pages.append(currentSentenceGroup.joined(separator: " "))
                        currentSentenceGroup = [sentence]
                        currentGroupHeight = sentenceHeight
                    } else {
                        currentSentenceGroup.append(sentence)
                        currentGroupHeight += sentenceHeight
                    }
                }
                
                // Add remaining sentence group
                if !currentSentenceGroup.isEmpty {
                    pages.append(currentSentenceGroup.joined(separator: " "))
                }
            } else {
                // Paragraph fits — include separator height if there's already content on this page
                let separatorHeight: CGFloat = currentPageText.isEmpty
                    ? 0
                    : measureTextHeight(paragraphSeparator, width: width, font: font, lineSpacing: lineSpacing)
                if currentPageHeight + separatorHeight + paragraphHeight > maxHeight && !currentPageText.isEmpty {
                    // Start new page
                    pages.append(currentPageText.joined(separator: paragraphSeparator))
                    currentPageText = [paragraph]
                    currentPageHeight = paragraphHeight
                } else {
                    // Add to current page
                    currentPageText.append(paragraph)
                    currentPageHeight += separatorHeight + paragraphHeight
                }
            }
        }
        
        // Add remaining content as final page
        if !currentPageText.isEmpty {
            pages.append(currentPageText.joined(separator: paragraphSeparator))
        }
        
        return pages.isEmpty ? [text] : pages
    }
    
    /// Convert SwiftUI Font to UIFont for text measurement - uses same relative sizing as BookFontStyle
    private func uiFont(from fontStyle: BookFontStyle, frameHeight: CGFloat) -> UIFont {
        // Body font at 2.0% of frame height (matches BookFontStyle.bodyFont)
        let size = frameHeight * 0.020
        
        switch fontStyle {
        case .kidsBook:
            return UIFont(name: "TimesNewRomanPSMT", size: 12) ?? UIFont.systemFont(ofSize: 12, weight: .regular)
        case .comic:
            return UIFont.systemFont(ofSize: size, weight: .semibold)
        case .realistic:
            return UIFont(name: "Georgia", size: size) ?? UIFont.systemFont(ofSize: size, weight: .regular)
        case .custom:
            return UIFont.systemFont(ofSize: size, weight: .regular)
        }
    }
    
    /// Split long text into multiple pages that fit within bounds
    func paginateText(_ text: String, title: String?, subtitle: String?, pageHeight: CGFloat, pageWidth: CGFloat, memoryID: UUID) -> [PageItem] {
        guard !text.isEmpty else { return [] }
        
        let isKidsBook = currentArtStyle == .kidsBook
        // Kids: header bar unchanged per page; vertical: title+subtitle on every page → less body height than old 0.70 model
        let availableHeight = pageHeight * (isKidsBook ? 0.65 : 0.62)
        let textWidth = pageWidth * (isKidsBook ? 0.81 : 0.84) // kids: side 8.5% + right 10.5%; vertical: 6% + 10%
        
        // Get font for current art style - use same relative sizing as display
        let fontStyle = BookFontStyle(artStyle: currentArtStyle)
        let font = uiFont(from: fontStyle, frameHeight: pageHeight)
        
        // Kids book: double spacing (2× line height) + no blank line between paragraphs
        let lineSpacing: CGFloat = isKidsBook ? 12 : pageHeight * 0.006  // matches VerticalBookTextPage.lineSpacing
        let paragraphSeparator = isKidsBook ? "\n" : "\n\n"
        
        // Split text into pages
        let pageTexts = splitTextToFitHeight(text, maxHeight: availableHeight, width: textWidth, font: font, lineSpacing: lineSpacing, paragraphSeparator: paragraphSeparator)
        
        // Create PageItem array — repeat title/subtitle on every text page (match-first continuation UX)
        return pageTexts.enumerated().map { index, pageText in
            PageItem.textPage(
                index: index + 1,
                total: pageTexts.count,
                body: pageText,
                title: title,
                subtitle: subtitle,
                memoryID: memoryID
            )
        }
    }

    private func memoryDisplayLabel(for entry: MemoryEntry, fallbackOrdinal: Int) -> String {
        if let p = entry.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p.count > 100 ? String(p.prefix(100)) + "…" : p
        }
        if let t = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t.count > 100 ? String(t.prefix(100)) + "…" : t
        }
        return "Memory \(fallbackOrdinal)"
    }

    private func isQuestionDrivenMemory(_ entry: MemoryEntry) -> Bool {
        guard let rawPrompt = entry.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPrompt.isEmpty else {
            return false
        }

        let normalizedPrompt = rawPrompt.lowercased()
        if normalizedPrompt == "untitled prompt" || normalizedPrompt == "untitled" {
            return false
        }

        if let chapter = entry.chapter?.trimmingCharacters(in: .whitespacesAndNewlines),
           !chapter.isEmpty {
            if isKnownMemoirPrompt(chapterTitle: chapter, promptText: rawPrompt) {
                return true
            }
        }

        if rawPrompt.hasSuffix("?") {
            return true
        }

        let questionPrefixes = [
            "what", "when", "where", "who", "why", "how",
            "tell me about", "describe", "share", "think of"
        ]
        return questionPrefixes.contains { normalizedPrompt.hasPrefix($0 + " ") || normalizedPrompt == $0 }
    }
    
    private func clearPersistedStorybook(for profileID: UUID) {
        StorybookLocalStore.removeCurrentBook(profileID: profileID)
        let localKey = "storybook_\(profileID.uuidString)"
        UserDefaults.standard.removeObject(forKey: localKey)
        
        // Also clear from iCloud
        let cloudStore = NSUbiquitousKeyValueStore.default
        let cloudKey = "memoir_storybook_\(profileID.uuidString)"
        cloudStore.removeObject(forKey: cloudKey)
        cloudStore.synchronize()
        
        print("🗑️ Cleared persisted storybook for profile: \(profileID)")
    }
    
    private func ensureSubjectPhotoIsRegistered() async {
        guard subjectPhotoID == nil, let shot = subjectPhoto else { return }
        do {
            let (fid, jpeg) = try await imageCtx.createReference(from: shot)
            subjectPhotoID   = fid
            subjectPhotoJPEG = jpeg
            print("✅ head-shot uploaded →", fid)
        } catch {
            print("🚫 head-shot upload failed:", error.localizedDescription)
        }
    }

    private func ensureFaceDescription() async {
        guard faceDescription == nil,
              let fid = subjectPhotoID else { return }
        do {
            faceDescription = try await imageCtx.faceDescriptor(
                fileID: fid,
                jpegData: subjectPhotoJPEG,
                race: self.ethnicity,
                gender: self.gender
            )
            
            if let desc = faceDescription {
                print("✅ face descriptor →", desc)
            } else {
                print("⚠️ Face descriptor was nil after successful API call.")
            }
        } catch {
            print("🚫 face descriptor failed:", error.localizedDescription)
            faceDescription = nil
        }
    }

    private let traitOpposites: [String : [String]] = [
        "light skin": ["dark brown skin", "very dark skin"], "pale skin": ["medium-brown skin", "dark skin"],
        "fair skin": ["brown skin", "dark skin"], "dark skin": ["pale caucasian skin", "light skin"],
        "brown skin": ["very light skin", "pale skin"], "blond hair": ["jet-black hair", "dark-brown hair"],
        "light-blond hair": ["black hair", "dark-brown hair"], "brown hair": ["blond hair", "jet-black hair"],
        "black hair": ["light-blond hair", "gray hair"], "gray hair": ["blond hair", "black hair", "vibrant red hair"],
        "straight texture": ["tight coils", "kinky curly texture"], "wavy texture": ["pin-straight hair"],
        "curly texture": ["pin-straight hair"], "tight coils": ["straight texture"], "male": ["female presentation"],
        "female": ["male presentation"]
    ]

    // Enhanced race descriptor mapping with more accurate translations
    private let raceDescriptorMap: [String: String] = [
        // South Asian descriptors - more specific for Indian
        "indian": "warm brown skin, expressive dark eyes, straight dark hair",
        "south asian": "warm brown skin, expressive dark eyes, straight dark hair",
        "pakistani": "warm brown skin, expressive dark eyes, straight dark hair",
        "bengali": "warm brown skin, expressive dark eyes, straight dark hair",
        "tamil": "warm brown skin, expressive dark eyes, straight dark hair",
        
        // East Asian descriptors
        "asian": "light brown skin, dark almond-shaped eyes, straight black hair",
        "east asian": "light brown skin, dark almond-shaped eyes, straight black hair",
        "chinese": "light brown skin, dark almond-shaped eyes, straight black hair",
        "japanese": "light brown skin, dark almond-shaped eyes, straight black hair",
        "korean": "light brown skin, dark almond-shaped eyes, straight black hair",
        
        // Other descriptors
        "hispanic": "warm olive skin, expressive brown eyes, dark wavy hair",
        "latino": "warm olive skin, expressive brown eyes, dark wavy hair",
        "mexican": "warm olive skin, expressive brown eyes, dark wavy hair",
        "black": "rich dark skin, expressive brown eyes, textured dark hair",
        "african american": "rich dark skin, expressive brown eyes, textured dark hair",
        "african": "rich dark skin, expressive brown eyes, textured dark hair",
        "caucasian": "fair skin, varied eye color, straight to wavy hair",
        "white": "fair skin, varied eye color, straight to wavy hair",
        "european": "fair skin, varied eye color, straight to wavy hair",
        "middle eastern": "olive skin, expressive dark eyes, dark hair",
        "arabic": "olive skin, expressive dark eyes, dark hair",
        "persian": "olive skin, expressive dark eyes, dark hair",
        "native american": "bronze skin, dark eyes, long dark hair",
        "indigenous": "bronze skin, dark eyes, long dark hair",
        "mixed": "unique features, expressive eyes, distinctive hair texture",
        "biracial": "unique features, expressive eyes, distinctive hair texture"
    ]

    private func translateRaceToDescriptor(_ text: String) -> String {
        var translated = text
        let lowercaseText = text.lowercased()
        
        for (race, descriptor) in raceDescriptorMap {
            // Create patterns for more comprehensive matching
            let patterns = [
                race,
                "\(race) heritage",
                "\(race) background",
                "\(race) ancestry",
                "\(race) ethnicity",
                "of \(race) descent",
                "\(race) features",
                "\(race) appearance"
            ]
            
            for pattern in patterns {
                if lowercaseText.contains(pattern) {
                    translated = translated.replacingOccurrences(
                        of: pattern,
                        with: descriptor,
                        options: .caseInsensitive
                    )
                }
            }
        }
        
        // Also handle some common problematic phrases
        translated = translated.replacingOccurrences(of: "race", with: "features", options: .caseInsensitive)
        translated = translated.replacingOccurrences(of: "ethnicity", with: "appearance", options: .caseInsensitive)
        translated = translated.replacingOccurrences(of: "racial", with: "physical", options: .caseInsensitive)
        
        return translated
    }

    /// Intelligent LLM-based prompt sanitizer that preserves character details while ensuring DALL-E 3 compliance
    private func sanitizePromptWithLLM(_ prompt: String) async -> String {
        let systemPrompt = """
        You are a DALL-E 3 prompt sanitizer. Your job is to rewrite prompts to be DALL-E 3 compliant while preserving ALL character details and visual information.

        DALL-E 3 TRIGGERS TO AVOID:
        - Explicit racial terms: "Caucasian", "Black", "Indian", "Asian", "Hispanic"
        - Age + race combinations: "17 year old Indian", "21 Black person"
        - Personal names with detailed descriptions
        - Negative emotional states: "anxious", "angry", "sad"
        - Harsh instructional language: "must", "never", "forbidden"
        - Ancestry references: "of Indian descent", "suggesting ancestry"

        SAFE ALTERNATIVES:
        - Visual descriptors: "warm brown skin", "dark hair", "light eyes"
        - General age ranges: "teenager", "young adult", "middle-aged"
        - Positive emotions: "focused", "determined", "thoughtful"
        - Gentle instructions: "showing", "featuring", "with"

        PRESERVE THESE:
        - All physical appearance details (hair, eyes, skin tone, build)
        - Clothing and accessories
        - Scene setting and activities
        - Character relationships and roles
        - Art style preferences

        REWRITE RULES:
        1. Replace racial terms with visual descriptors
        2. Convert specific ages to age ranges when combined with appearance
        3. Remove personal names or make them generic
        4. Soften harsh language
        5. Keep the prompt under 200 characters when possible
        6. Maintain all essential visual information

        Return ONLY the rewritten prompt, nothing else.
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": 300
        ]

        do {
            let startedAt = Date()
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, httpResponse) = try await URLSession.shared.data(for: req)
            let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode
            
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg
            }
            struct Root: Decodable { let choices: [Choice] }
            
            let sanitized = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content ?? prompt
            
            print("🧹 LLM SANITIZED PROMPT:")
            print("ORIGINAL: \(prompt)")
            print("SANITIZED: \(sanitized)")
            await logOpenAIChatTelemetry(
                model: "gpt-4o-mini",
                promptChars: prompt.count,
                responseData: data,
                statusCode: statusCode,
                success: true,
                startedAt: startedAt
            )
            
            return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            print("⚠️ LLM sanitization failed, using original prompt: \(error)")
            return prompt
        }
    }

    /// Enhanced sanitization that combines LLM intelligence with fallback rules
    private func sanitizeForDALLE3(_ prompt: String) async -> String {
        let llmSanitized: String
        if useLLMSanitizer {
            llmSanitized = await sanitizePromptWithLLM(prompt)
        } else {
            llmSanitized = prompt // skip LLM step
        }
        
        // Apply additional safety checks as fallback
        var finalSanitized = llmSanitized
        
        // Emergency fallback replacements for any missed terms
        let emergencyReplacements = [
            ("Caucasian", "light-skinned"),
            ("Black person", "person with dark skin"),
            ("Indian", "South Asian"),
            ("Hispanic", "Latino"),
            ("age 17", "teenage"),
            ("age 21", "young adult"),
            ("years old", "year old"),
            ("NEGATIVE:", "Style note:"),
            ("Avoid:", "Preferring:"),
            ("must not", "should avoid"),
            ("never", "rarely")
        ]
        
        for (problematic, safe) in emergencyReplacements {
            finalSanitized = finalSanitized.replacingOccurrences(of: problematic, with: safe, options: .caseInsensitive)
        }
        
        // Final cleanup
        finalSanitized = finalSanitized.replacingOccurrences(of: "  ", with: " ")
        finalSanitized = finalSanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return finalSanitized
    }

    private func negativesOpposite(to identity: [String]) -> String {
        let idLower = identity.joined(separator: ", ").lowercased()
        var bans: Set<String> = []
        for (trait, oppo) in traitOpposites where idLower.contains(trait) { bans.formUnion(oppo) }
        
        // Use softer, less triggering negative terms
        bans.formUnion(["different gender", "inconsistent features", "different skin tone"])
        
        if bans.isEmpty { bans.insert("different facial features") }
        return "Avoid: " + bans.joined(separator: ", ") + "."
    }

    // Enhanced identity prompt builder that enforces main character consistency
    private func buildIdentityPrompt() -> String {
        var identityBits: [String] = []
        
        // Get the main character's description from face analysis
        if let vision = faceDescription, !vision.isEmpty {
            identityBits.append(vision)
        }
        
        // Add user-specified details from settings
        if !ethnicity.isEmpty {
            identityBits.append(ethnicity)
        }
        
        if !gender.isEmpty {
            identityBits.append("presenting as \(gender.lowercased())")
        }
        
        if !otherDetails.isEmpty {
            identityBits.append(otherDetails)
        }
        
        guard !identityBits.isEmpty else { return "" }
        
        let mainCharacterDescription = identityBits.joined(separator: ", ")
        
        let positive = "MAIN CHARACTER: The narrator is a person with \(mainCharacterDescription). By default, family members and close friends should share similar skin tone and features, UNLESS specific descriptions are provided for them in SCENE CHARACTERS below."
        
        return positive + " "
    }
    
    /// Infers gender from common names when gender field is empty
    /// Gives the system creative freedom to infer gender from names like "Melody" (female) or "Caleb" (male)
    private func inferGenderFromName(_ name: String) -> String? {
        let firstName = name.components(separatedBy: " ").first?.lowercased() ?? name.lowercased()
        
        // Common feminine names
        let feminineNames: Set<String> = [
            "melody", "sarah", "emma", "olivia", "sophia", "isabella", "mia", "charlotte",
            "amelia", "harper", "evelyn", "abigail", "emily", "elizabeth", "sofia", "avery",
            "ella", "scarlett", "grace", "victoria", "riley", "aria", "lily", "aurora",
            "zoey", "hannah", "layla", "penelope", "chloe", "nora", "hazel", "luna",
            "savannah", "brooklyn", "leah", "zoe", "stella", "maya", "audrey", "claire",
            "lucy", "anna", "caroline", "genesis", "aaliyah", "kennedy", "kinsley",
            "allison", "natalie", "madelyn", "naomi", "eva", "alice",
            "jessica", "jennifer", "ashley", "amanda", "stephanie", "nicole", "rachel",
            "samantha", "katherine", "christine", "helen", "deborah", "laura", "karen",
            "nancy", "betty", "dorothy", "lisa", "sandra", "donna", "carol", "ruth",
            "sharon", "michelle", "kimberly", "amy", "angela", "melissa", "brenda",
            "maria", "rosa", "priya", "ananya", "anika", "pooja", "neha", "kavya"
        ]
        
        // Common masculine names  
        let masculineNames: Set<String> = [
            "caleb", "james", "john", "robert", "michael", "william", "david", "joseph",
            "charles", "thomas", "daniel", "matthew", "anthony", "mark", "donald", "steven",
            "paul", "andrew", "joshua", "kenneth", "kevin", "brian", "george", "timothy",
            "ronald", "edward", "jason", "jeffrey", "ryan", "jacob", "gary", "nicholas",
            "eric", "jonathan", "stephen", "larry", "justin", "scott", "brandon", "benjamin",
            "samuel", "raymond", "gregory", "frank", "alexander", "patrick", "jack", "dennis",
            "jerry", "tyler", "aaron", "jose", "adam", "nathan", "henry", "douglas", "zachary",
            "peter", "kyle", "noah", "ethan", "jeremy", "walter", "christian", "keith",
            "roger", "terry", "austin", "sean", "gerald", "carl", "dylan", "harold", "jordan",
            "jesse", "bryan", "lawrence", "arthur", "gabriel", "bruce", "albert", "willie",
            "alan", "wayne", "elijah", "eugene", "russell", "bobby", "mason", "philip",
            "louis", "harry", "arjun", "raj", "vikram", "rahul", "amit", "sanjay", "ravi"
        ]
        
        if feminineNames.contains(firstName) {
            return "female"
        } else if masculineNames.contains(firstName) {
            return "male"
        }
        return nil  // Unknown - let AI decide
    }

    private func normalizeFaceDescriptor(_ descriptor: String, explicitGender: String) -> String {
        var cleaned = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        if !explicitGender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let genderPattern = #"\b(a\s+man|a\s+woman|man|woman|male|female)\b"#
            cleaned = cleaned.replacingOccurrences(
                of: genderPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        cleaned = cleaned.replacingOccurrences(of: #"\s*,\s*"#, with: ", ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #",\s*,"#, with: ", ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ",.- ").union(.whitespacesAndNewlines))
        return cleaned
    }

    private func dedupeCharacterTraits(_ traits: [String], against descriptor: String) -> [String] {
        var seen = Set<String>()
        let descriptorLower = descriptor.lowercased()

        return traits.compactMap { rawTrait in
            let trimmed = rawTrait.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return nil }
            guard !descriptorLower.contains(normalized) else { return nil }
            seen.insert(normalized)
            return trimmed
        }
    }
    
    private struct StableTraitValue {
        let value: String
        let source: String
    }
    
    private struct StableTraitSnapshot {
        let ethnicity: StableTraitValue?
        let gender: StableTraitValue?
        let hairAndFeatures: StableTraitValue?
    }
    
    private func cleanedStableTraitValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWeakTraitValue(trimmed) else { return nil }
        return trimmed
    }
    
    private func containsAnyWord(in text: String, words: [String]) -> Bool {
        let normalized = " \(normalizeLooseText(text)) "
        for word in words where normalized.contains(" \(normalizeLooseText(word)) ") {
            return true
        }
        return false
    }
    
    private func deriveEthnicityFromLegacy(_ character: CharacterDetails.Character) -> StableTraitValue? {
        if let race = cleanedStableTraitValue(character.race) {
            return StableTraitValue(value: race, source: "legacyDerived(race)")
        }
        
        let searchableTexts = [character.physicalDescription, character.appearance, character.combinedAppearance]
        let ethnicityKeywords: [(label: String, words: [String])] = [
            ("South Asian", ["south asian", "indian", "pakistani", "bangladeshi"]),
            ("East Asian", ["east asian", "chinese", "japanese", "korean"]),
            ("Southeast Asian", ["southeast asian", "filipino", "vietnamese", "thai", "indonesian"]),
            ("Middle Eastern", ["middle eastern", "arab", "persian", "iranian"]),
            ("Black", ["african", "african american"]),
            ("White", ["caucasian", "european"]),
            ("Latino", ["latino", "latina", "latinx", "hispanic", "mexican"]),
            ("Native American", ["native american", "indigenous"]),
            ("Mixed", ["mixed", "biracial", "multiracial"])
        ]
        
        for text in searchableTexts {
            guard let cleanedText = cleanedStableTraitValue(text) else { continue }
            for keyword in ethnicityKeywords where containsAnyWord(in: cleanedText, words: keyword.words) {
                return StableTraitValue(value: keyword.label, source: "legacyDerived(appearanceParse)")
            }
        }
        return nil
    }
    
    private func deriveGenderFromLegacy(_ character: CharacterDetails.Character) -> StableTraitValue? {
        let searchableTexts = [character.physicalDescription, character.appearance, character.combinedAppearance]
        for text in searchableTexts {
            guard let cleanedText = cleanedStableTraitValue(text) else { continue }
            if containsAnyWord(in: cleanedText, words: ["female", "woman", "girl"]) {
                return StableTraitValue(value: "female", source: "legacyDerived(appearanceParse)")
            }
            if containsAnyWord(in: cleanedText, words: ["male", "man", "boy"]) {
                return StableTraitValue(value: "male", source: "legacyDerived(appearanceParse)")
            }
        }
        return nil
    }
    
    private func deriveHairFromLegacy(_ character: CharacterDetails.Character) -> StableTraitValue? {
        if let physical = cleanedStableTraitValue(character.physicalDescription) {
            return StableTraitValue(value: physical, source: "legacyDerived(physicalDescription)")
        }
        
        let hairWords = [
            "hair", "haired", "curly", "wavy", "straight", "braid", "braided",
            "ponytail", "afro", "buzz", "beard", "mustache", "freckles",
            "glasses", "dimples", "fringe", "bangs"
        ]
        let clothingWords = [
            "wearing", "shirt", "pants", "jeans", "jacket", "hoodie", "dress",
            "skirt", "blouse", "sweater", "coat", "shoes", "sneakers", "converse", "top"
        ]
        
        let fallbackSegments = [character.appearance, character.combinedAppearance]
        for text in fallbackSegments {
            guard let cleanedText = cleanedStableTraitValue(text) else { continue }
            let segments = cleanedText
                .split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            let hairSegments = segments.filter { segment in
                containsAnyWord(in: segment, words: hairWords) &&
                !containsAnyWord(in: segment, words: clothingWords)
            }
            
            if !hairSegments.isEmpty {
                return StableTraitValue(
                    value: hairSegments.joined(separator: ", "),
                    source: "legacyDerived(appearanceParse)"
                )
            }
        }
        
        return nil
    }
    
    private func stableTraitSnapshot(for character: CharacterDetails.Character) -> StableTraitSnapshot {
        let ethnicity: StableTraitValue? = {
            if let direct = cleanedStableTraitValue(character.ethnicity) {
                return StableTraitValue(value: direct, source: "splitField")
            }
            return deriveEthnicityFromLegacy(character)
        }()
        
        let gender: StableTraitValue? = {
            if let direct = cleanedStableTraitValue(character.gender) {
                return StableTraitValue(value: direct, source: "splitField")
            }
            return deriveGenderFromLegacy(character)
        }()
        
        let hairAndFeatures: StableTraitValue? = {
            if let direct = cleanedStableTraitValue(character.hairAndFeatures) {
                return StableTraitValue(value: direct, source: "splitField")
            }
            return deriveHairFromLegacy(character)
        }()
        
        return StableTraitSnapshot(
            ethnicity: ethnicity,
            gender: gender,
            hairAndFeatures: hairAndFeatures
        )
    }
    
    private func applyingStableTraitSnapshot(
        to character: CharacterDetails.Character,
        logContext: String
    ) -> CharacterDetails.Character {
        let snapshot = stableTraitSnapshot(for: character)
        var normalized = character
        
        if normalized.ethnicity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let ethnicity = snapshot.ethnicity {
            normalized.ethnicity = ethnicity.value
            print("🧩 Stable trait fill (\(logContext)) '\(character.name)' field ethnicity from \(ethnicity.source)")
        }
        
        if normalized.gender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let gender = snapshot.gender {
            normalized.gender = gender.value
            print("🧩 Stable trait fill (\(logContext)) '\(character.name)' field gender from \(gender.source)")
        }
        
        if normalized.hairAndFeatures.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let hair = snapshot.hairAndFeatures {
            normalized.hairAndFeatures = hair.value
            print("🧩 Stable trait fill (\(logContext)) '\(character.name)' field hairAndFeatures from \(hair.source)")
        }
        
        return normalized
    }
    
    /// Fills in empty stable traits from another memory where the same global
    /// character has those fields populated. Clothes are NOT inherited since
    /// they change per scene.
    private func enrichFromGlobalCharacter(
        _ character: CharacterDetails.Character,
        entry: MemoryEntry,
        profileID: UUID
    ) -> CharacterDetails.Character {
        guard let globalId = character.globalCharacterId else { return character }
        let normalizedCharacter = applyingStableTraitSnapshot(to: character, logContext: "localNormalization")
        let needsEthnicity = normalizedCharacter.ethnicity.isEmpty
        let needsGender = normalizedCharacter.gender.isEmpty
        let needsHair = normalizedCharacter.hairAndFeatures.isEmpty
        guard needsEthnicity || needsGender || needsHair else { return normalizedCharacter }
        
        // Pull full appearance history so we can skip the current memory itself.
        let allAppearances = GlobalCharacterManager.shared.getAllAppearances(
            globalCharacterId: globalId,
            profileID: profileID
        )
        let otherAppearances = allAppearances
            .filter { $0.memory.objectID != entry.objectID }
            .sorted { ($0.memory.createdAt ?? .distantPast) > ($1.memory.createdAt ?? .distantPast) }
        
        if otherAppearances.count < allAppearances.count {
            print("⏭️ Skipped current-memory global source for '\(character.name)' while enriching stable traits.")
        }
        
        guard !otherAppearances.isEmpty else {
            print("⏭️ No other memories found for global character '\(character.name)' to backfill missing stable traits.")
            return normalizedCharacter
        }
        
        func chooseFieldValue(_ extractor: (CharacterDetails.Character) -> StableTraitValue?, field: String) -> StableTraitValue? {
            let values = otherAppearances.compactMap { appearance -> StableTraitValue? in
                extractor(appearance.character)
            }
            print("🔎 Global field scan '\(character.name)' '\(field)': scanned \(otherAppearances.count) memories, found \(values.count) candidate values.")
            guard let first = values.first, !isWeakTraitValue(first.value) else {
                print("⏭️ No usable global '\(field)' value found for '\(character.name)'.")
                return nil
            }
            let uniqueByNormalized = Dictionary(grouping: values, by: { normalizeLooseText($0.value) })
            if uniqueByNormalized.count > 1 {
                print("⚠️ Multiple global '\(field)' values found for '\(character.name)'; using most recent non-empty value.")
            }
            return first
        }
        
        var enriched = normalizedCharacter
        if needsEthnicity {
            print("🧭 Missing field detected for '\(character.name)': ethnicity")
        }
        if needsEthnicity, let ethnicity = chooseFieldValue({ stableTraitSnapshot(for: $0).ethnicity }, field: "ethnicity") {
            enriched.ethnicity = ethnicity.value
            print("🔗 Inherited ethnicity '\(ethnicity.value)' for \(character.name) from another memory (global ID path, source: \(ethnicity.source))")
        }
        if needsGender {
            print("🧭 Missing field detected for '\(character.name)': gender")
        }
        if needsGender, let gender = chooseFieldValue({ stableTraitSnapshot(for: $0).gender }, field: "gender") {
            enriched.gender = gender.value
            print("🔗 Inherited gender '\(gender.value)' for \(character.name) from another memory (global ID path, source: \(gender.source))")
        }
        if needsHair {
            print("🧭 Missing field detected for '\(character.name)': hairAndFeatures")
        }
        if needsHair, let hair = chooseFieldValue({ stableTraitSnapshot(for: $0).hairAndFeatures }, field: "hairAndFeatures") {
            enriched.hairAndFeatures = hair.value
            print("🔗 Inherited hair/features '\(hair.value)' for \(character.name) from another memory (global ID path, source: \(hair.source))")
        }
        return enriched
    }
    
    private struct InferredMatchCandidate {
        let character: CharacterDetails.Character
        let memoryDate: Date?
        let score: Int
    }
    
    private func normalizeLooseText(_ value: String) -> String {
        let lower = value.lowercased()
        let allowed = lower.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(allowed)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func isWeakTraitValue(_ value: String) -> Bool {
        let normalized = normalizeLooseText(value)
        if normalized.isEmpty { return true }
        let weakValues: Set<String> = [
            "unknown", "unsure", "not sure", "n a", "na", "none", "other", "prefer not to say"
        ]
        return weakValues.contains(normalized)
    }
    
    private func relationshipsCompatible(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizeLooseText(lhs)
        let right = normalizeLooseText(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.contains(right) || right.contains(left)
    }
    
    private func hasTokenOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let leftTokens = Set(normalizeLooseText(lhs).split(separator: " ").map(String.init))
        let rightTokens = Set(normalizeLooseText(rhs).split(separator: " ").map(String.init))
        let meaningfulLeft = leftTokens.filter { $0.count > 2 }
        let meaningfulRight = rightTokens.filter { $0.count > 2 }
        guard !meaningfulLeft.isEmpty, !meaningfulRight.isEmpty else { return false }
        return !Set(meaningfulLeft).intersection(Set(meaningfulRight)).isEmpty
    }
    
    private func inferredMatchScore(
        target: CharacterDetails.Character,
        candidate: CharacterDetails.Character,
        memoryDate: Date?
    ) -> Int? {
        let targetSnapshot = stableTraitSnapshot(for: target)
        let candidateSnapshot = stableTraitSnapshot(for: candidate)
        let targetName = normalizeLooseText(target.name)
        let candidateName = normalizeLooseText(candidate.name)
        guard !targetName.isEmpty, targetName == candidateName else { return nil }
        
        // If both are linked and IDs disagree, they are explicitly different people.
        if let targetGlobal = target.globalCharacterId,
           let candidateGlobal = candidate.globalCharacterId,
           targetGlobal != candidateGlobal {
            return nil
        }
        
        var score = 50 // exact normalized name
        var anchorCount = 0
        
        let targetRel = target.relationshipToNarrator.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateRel = candidate.relationshipToNarrator.trimmingCharacters(in: .whitespacesAndNewlines)
        if !targetRel.isEmpty && !candidateRel.isEmpty {
            guard relationshipsCompatible(targetRel, candidateRel) else { return nil }
            score += 40
            anchorCount += 1
        }
        
        if let targetGenderValue = targetSnapshot.gender?.value,
           let candidateGenderValue = candidateSnapshot.gender?.value {
            let targetGender = normalizeLooseText(targetGenderValue)
            let candidateGender = normalizeLooseText(candidateGenderValue)
            guard targetGender == candidateGender else { return nil }
            score += 30
            anchorCount += 1
        }
        
        if let targetEthnicityValue = targetSnapshot.ethnicity?.value,
           let candidateEthnicityValue = candidateSnapshot.ethnicity?.value {
            let targetEthnicity = normalizeLooseText(targetEthnicityValue)
            let candidateEthnicity = normalizeLooseText(candidateEthnicityValue)
            guard targetEthnicity == candidateEthnicity else { return nil }
            score += 30
            anchorCount += 1
        }
        
        if let targetHairValue = targetSnapshot.hairAndFeatures?.value,
           let candidateHairValue = candidateSnapshot.hairAndFeatures?.value {
            guard hasTokenOverlap(targetHairValue, candidateHairValue) else { return nil }
            score += 20
            anchorCount += 1
        }
        
        // If we have no relationship/trait anchor, skip to avoid same-name collisions.
        guard anchorCount > 0 else { return nil }
        
        // Prefer candidates that can fill more missing stable fields.
        if targetSnapshot.ethnicity == nil,
           let candidateEthnicity = candidateSnapshot.ethnicity,
           !isWeakTraitValue(candidateEthnicity.value) {
            score += 5
        }
        if targetSnapshot.gender == nil,
           let candidateGender = candidateSnapshot.gender,
           !isWeakTraitValue(candidateGender.value) {
            score += 5
        }
        if targetSnapshot.hairAndFeatures == nil,
           let candidateHair = candidateSnapshot.hairAndFeatures,
           !isWeakTraitValue(candidateHair.value) {
            score += 5
        }
        
        if let memoryDate {
            let days = Int(Date().timeIntervalSince(memoryDate) / 86_400)
            if days <= 90 {
                score += 15
            } else if days <= 365 {
                score += 10
            } else {
                score += 5
            }
        }
        
        return score
    }
    
    private func bestInferredTraitSource(
        for target: CharacterDetails.Character,
        entry: MemoryEntry,
        profileID: UUID
    ) -> CharacterDetails.Character? {
        let targetSnapshot = stableTraitSnapshot(for: target)
        let needsStableTraits = targetSnapshot.ethnicity == nil || targetSnapshot.gender == nil || targetSnapshot.hairAndFeatures == nil
        guard needsStableTraits else { return nil }
        
        // We only infer when at least one reliable anchor exists on the target.
        let hasRelationshipAnchor = !target.relationshipToNarrator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTraitAnchor = targetSnapshot.gender != nil || targetSnapshot.ethnicity != nil || targetSnapshot.hairAndFeatures != nil
        guard hasRelationshipAnchor || hasTraitAnchor else {
            print("⏭️ Skipped inferred match for '\(target.name)' due to missing anchors.")
            return nil
        }
        
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = MemoryUserScope.profilePredicate(profileID: profileID)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]
        
        let sourceMemories: [MemoryEntry]
        do {
            sourceMemories = try PersistenceController.shared.container.viewContext.fetch(request)
        } catch {
            print("⚠️ Failed to fetch memories for inferred matching: \(error.localizedDescription)")
            return nil
        }
        
        let currentID = entry.objectID
        var candidates: [InferredMatchCandidate] = []
        
        for memory in sourceMemories where memory.objectID != currentID {
            guard let detailsString = memory.characterDetails,
                  !detailsString.isEmpty,
                  let data = detailsString.data(using: .utf8),
                  let details = try? JSONDecoder().decode(CharacterDetails.self, from: data) else { continue }
            
            for candidate in details.characters {
                guard let score = inferredMatchScore(
                    target: target,
                    candidate: candidate,
                    memoryDate: memory.createdAt
                ) else { continue }
                
                // High-confidence gate for safety.
                guard score >= 90 else { continue }
                
                candidates.append(
                    InferredMatchCandidate(character: candidate, memoryDate: memory.createdAt, score: score)
                )
            }
        }
        
        guard !candidates.isEmpty else {
            print("⏭️ No high-confidence inferred match found for '\(target.name)'.")
            return nil
        }
        
        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return (lhs.memoryDate ?? .distantPast) > (rhs.memoryDate ?? .distantPast)
            }
            return lhs.score > rhs.score
        }
        
        // Conflict guard: if multiple high-confidence candidates disagree on a field, skip that field.
        var resolved = target
        
        func resolvedValue(_ extractor: (CharacterDetails.Character) -> StableTraitValue?, field: String) -> StableTraitValue? {
            let rankedValues = sortedCandidates.compactMap { candidate -> (value: String, normalized: String, score: Int, source: String)? in
                guard let resolvedTrait = extractor(candidate.character) else { return nil }
                let value = resolvedTrait.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty || isWeakTraitValue(value) { return nil }
                return (value, normalizeLooseText(value), candidate.score, resolvedTrait.source)
            }
            guard !rankedValues.isEmpty else { return nil }
            
            let top = rankedValues[0]
            if rankedValues.count > 1 {
                let second = rankedValues[1]
                if top.normalized != second.normalized {
                    let scoreGap = top.score - second.score
                    if scoreGap < 10 {
                        print("⚠️ Inferred match conflict for '\(target.name)' field '\(field)' (score gap \(scoreGap)); skipping ambiguous field.")
                        return nil
                    }
                    print("⚠️ Inferred match conflict for '\(target.name)' field '\(field)' resolved by higher confidence (gap \(scoreGap)); using top value.")
                }
            }
            return StableTraitValue(value: top.value, source: top.source)
        }
        
        if resolved.ethnicity.isEmpty, let ethnicity = resolvedValue({ stableTraitSnapshot(for: $0).ethnicity }, field: "ethnicity") {
            resolved.ethnicity = ethnicity.value
            print("🔎 Inferred field source for '\(target.name)' ethnicity: \(ethnicity.source)")
        }
        if resolved.gender.isEmpty, let gender = resolvedValue({ stableTraitSnapshot(for: $0).gender }, field: "gender") {
            resolved.gender = gender.value
            print("🔎 Inferred field source for '\(target.name)' gender: \(gender.source)")
        }
        if resolved.hairAndFeatures.isEmpty, let hair = resolvedValue({ stableTraitSnapshot(for: $0).hairAndFeatures }, field: "hairAndFeatures") {
            resolved.hairAndFeatures = hair.value
            print("🔎 Inferred field source for '\(target.name)' hairAndFeatures: \(hair.source)")
        }
        
        if resolved.ethnicity != target.ethnicity || resolved.gender != target.gender || resolved.hairAndFeatures != target.hairAndFeatures {
            let bestScore = sortedCandidates.first?.score ?? 0
            print("🔎 Inferred stable traits for '\(target.name)' using high-confidence match (score: \(bestScore)).")
            return resolved
        }
        
        print("⏭️ Inferred match found for '\(target.name)' but no safe field updates were applied.")
        return nil
    }

    private func backfillMissingStableTraitsByName(
        _ target: CharacterDetails.Character,
        entry: MemoryEntry,
        profileID: UUID
    ) -> CharacterDetails.Character {
        var resolved = target
        let needsEthnicity = resolved.ethnicity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsGender = resolved.gender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsHair = resolved.hairAndFeatures.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needsEthnicity || needsGender || needsHair else { return resolved }

        let normalizedName = normalizeLooseText(resolved.name)
        guard !normalizedName.isEmpty else {
            print("⏭️ Name-based fallback skipped: target has no usable name.")
            return resolved
        }

        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = MemoryUserScope.profilePredicate(profileID: profileID)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]

        let sourceMemories: [MemoryEntry]
        do {
            sourceMemories = try PersistenceController.shared.container.viewContext.fetch(request)
        } catch {
            print("⚠️ Name-based fallback failed to fetch memories for '\(resolved.name)': \(error.localizedDescription)")
            return resolved
        }

        let currentID = entry.objectID
        var candidates: [InferredMatchCandidate] = []
        var scannedMemories = 0
        var nameMatchCount = 0

        for memory in sourceMemories where memory.objectID != currentID {
            scannedMemories += 1
            guard let detailsString = memory.characterDetails,
                  !detailsString.isEmpty,
                  let data = detailsString.data(using: .utf8),
                  let details = try? JSONDecoder().decode(CharacterDetails.self, from: data) else { continue }

            for candidate in details.characters {
                guard normalizeLooseText(candidate.name) == normalizedName else { continue }

                // If both are linked and IDs disagree, they are explicitly different people.
                if let targetGlobal = resolved.globalCharacterId,
                   let candidateGlobal = candidate.globalCharacterId,
                   targetGlobal != candidateGlobal {
                    continue
                }

                nameMatchCount += 1
                let baseScore = inferredMatchScore(target: resolved, candidate: candidate, memoryDate: memory.createdAt) ?? 50
                candidates.append(
                    InferredMatchCandidate(character: candidate, memoryDate: memory.createdAt, score: baseScore)
                )
            }
        }

        print("🔎 Name fallback scan '\(resolved.name)': scanned \(scannedMemories) memories, matched \(nameMatchCount) same-name candidates.")
        guard !candidates.isEmpty else {
            return resolved
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return (lhs.memoryDate ?? .distantPast) > (rhs.memoryDate ?? .distantPast)
            }
            return lhs.score > rhs.score
        }

        func resolveFallbackValue(_ extractor: (CharacterDetails.Character) -> StableTraitValue?, field: String) -> StableTraitValue? {
            let rankedValues = sortedCandidates.compactMap { candidate -> (value: String, normalized: String, score: Int, source: String)? in
                guard let trait = extractor(candidate.character) else { return nil }
                let value = trait.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, !isWeakTraitValue(value) else { return nil }
                return (value, normalizeLooseText(value), candidate.score, trait.source)
            }
            print("🔎 Name fallback field scan '\(resolved.name)' '\(field)': \(rankedValues.count) usable candidate values.")
            guard !rankedValues.isEmpty else {
                print("⏭️ Name fallback '\(field)' no usable candidate for '\(resolved.name)'.")
                return nil
            }

            let top = rankedValues[0]
            if rankedValues.count > 1 {
                let second = rankedValues[1]
                if top.normalized != second.normalized {
                    let scoreGap = top.score - second.score
                    if scoreGap < 10 {
                        print("⚠️ Name fallback '\(field)' ambiguous for '\(resolved.name)' (score gap \(scoreGap)); skipping field.")
                        return nil
                    }
                    print("⚠️ Name fallback '\(field)' conflict resolved by higher confidence (gap \(scoreGap)) for '\(resolved.name)'.")
                }
            }
            return StableTraitValue(value: top.value, source: top.source)
        }

        if needsEthnicity {
            print("🧭 Missing field detected for '\(resolved.name)': ethnicity")
            if let ethnicity = resolveFallbackValue({ stableTraitSnapshot(for: $0).ethnicity }, field: "ethnicity") {
                resolved.ethnicity = ethnicity.value
                print("✅ Name fallback filled '\(resolved.name)' field ethnicity from \(ethnicity.source)")
            }
        }
        if needsGender {
            print("🧭 Missing field detected for '\(resolved.name)': gender")
            if let gender = resolveFallbackValue({ stableTraitSnapshot(for: $0).gender }, field: "gender") {
                resolved.gender = gender.value
                print("✅ Name fallback filled '\(resolved.name)' field gender from \(gender.source)")
            }
        }
        if needsHair {
            print("🧭 Missing field detected for '\(resolved.name)': hairAndFeatures")
            if let hair = resolveFallbackValue({ stableTraitSnapshot(for: $0).hairAndFeatures }, field: "hairAndFeatures") {
                resolved.hairAndFeatures = hair.value
                print("✅ Name fallback filled '\(resolved.name)' field hairAndFeatures from \(hair.source)")
            }
        }

        return resolved
    }
    
    private func enrichCharacterForPrompt(
        _ character: CharacterDetails.Character,
        entry: MemoryEntry,
        profileID: UUID
    ) -> CharacterDetails.Character {
        var enriched = applyingStableTraitSnapshot(to: character, logContext: "preEnrichment")
        enriched = enrichFromGlobalCharacter(enriched, entry: entry, profileID: profileID)
        let beforeNameFallback = enriched
        enriched = backfillMissingStableTraitsByName(enriched, entry: entry, profileID: profileID)
        if beforeNameFallback.ethnicity != enriched.ethnicity {
            print("✅ Name-based profile fallback applied for '\(character.name)' field: ethnicity")
        }
        if beforeNameFallback.gender != enriched.gender {
            print("✅ Name-based profile fallback applied for '\(character.name)' field: gender")
        }
        if beforeNameFallback.hairAndFeatures != enriched.hairAndFeatures {
            print("✅ Name-based profile fallback applied for '\(character.name)' field: hairAndFeatures")
        }
        
        let stillMissingStableTraits = enriched.ethnicity.isEmpty || enriched.gender.isEmpty || enriched.hairAndFeatures.isEmpty
        if stillMissingStableTraits {
            if enriched.globalCharacterId != nil {
                print("🔁 Global-ID enrichment incomplete for '\(character.name)'; attempting inferred fallback for remaining missing stable traits.")
            }
            if let inferred = bestInferredTraitSource(for: enriched, entry: entry, profileID: profileID) {
                let before = enriched
                enriched = inferred
                if before.ethnicity != enriched.ethnicity {
                    print("✅ Fallback inferred fill applied for '\(character.name)' field: ethnicity")
                }
                if before.gender != enriched.gender {
                    print("✅ Fallback inferred fill applied for '\(character.name)' field: gender")
                }
                if before.hairAndFeatures != enriched.hairAndFeatures {
                    print("✅ Fallback inferred fill applied for '\(character.name)' field: hairAndFeatures")
                }
            } else {
                print("⏭️ No safe inferred fallback applied for '\(character.name)' after global-ID enrichment.")
            }
        }
        
        return enriched
    }
    
    private func buildCharacterContext(for entry: MemoryEntry) -> String {
        guard let detailsString = entry.value(forKey: "characterDetails") as? String,
              !detailsString.isEmpty,
              let data = detailsString.data(using: .utf8),
              let characterDetails = try? JSONDecoder().decode(CharacterDetails.self, from: data),
              !characterDetails.characters.isEmpty else {
            print("ℹ️ No character details found for memory: \(entry.prompt ?? "Untitled")")
            return ""
        }
        
        var characterDescriptions: [String] = []
        let contextProfileID = currentProfileID
            ?? (entry.value(forKey: "profileID") as? UUID)
            ?? UUID()
        
        for rawCharacter in characterDetails.characters {
            let character = enrichCharacterForPrompt(rawCharacter, entry: entry, profileID: contextProfileID)
            var description = ""
            
            if !character.name.isEmpty {
                description += character.name
            } else {
                description += "A person"
            }
            
            var traits: [String] = []
            
            if !character.age.isEmpty {
                traits.append("age \(character.age)")
            }
            
            // Gender: keep explicit user entry only
            if !character.gender.isEmpty {
                traits.append(character.gender.lowercased())
            }
            
            // Appearance: Use new split fields, fall back to combined/legacy
            if !character.ethnicity.isEmpty {
                traits.append(character.ethnicity)
            }
            if !character.hairAndFeatures.isEmpty {
                traits.append(character.hairAndFeatures)
            }
            if !character.clothes.isEmpty {
                traits.append("wearing \(character.clothes)")
            }
            
            // Fall back to combined appearance or legacy fields if new fields are all empty
            if character.ethnicity.isEmpty && character.hairAndFeatures.isEmpty && character.clothes.isEmpty {
                if !character.combinedAppearance.isEmpty {
                    traits.append(character.combinedAppearance)
                }
            }
            
            // Relationship
            if !character.relationshipToNarrator.isEmpty {
                traits.append("(\(character.relationshipToNarrator))")
            }
            
            if !traits.isEmpty {
                description += " - " + traits.joined(separator: ", ")
            }
            
            characterDescriptions.append(description)
        }
        
        let characterContext = "SCENE CHARACTERS: " + characterDescriptions.joined(separator: "; ") + ". "
        print("🎭 Enhanced character context: \(characterContext)")
        return characterContext
    }
    
    // Helper function to convert specific ages to DALL-E 3 safe ranges
    private func convertAgeToSafeRange(_ age: String) -> String {
        let ageInt = Int(age.trimmingCharacters(in: CharacterSet.letters.union(.whitespaces))) ?? 0
        
        switch ageInt {
        case 0...12: return "child"
        case 13...17: return "teenager"
        case 18...25: return "young adult"
        case 26...40: return "adult"
        case 41...60: return "middle-aged adult"
        case 61...100: return "older adult"
        default: return age.lowercased().contains("teen") ? "teenager" : "adult"
        }
    }
    
    // MARK: - Hybrid Option 1.5: Character Injection + Enforcement
    
    /// Attempts to inject character names into memory for better enrichment
    /// Falls back gracefully if no suitable keywords found (Part A of Hybrid 1.5)
    private func injectCharacterNames(_ rawText: String, for entry: MemoryEntry) -> String {
        let characterContext = buildCharacterContext(for: entry)
        guard !characterContext.isEmpty else { return rawText }
        
        // Extract simple character list: "Ian (Brazilian), Robbie (White), Ben (pale)"
        let characterSummary = extractSimpleCharacterList(from: characterContext)
        guard !characterSummary.isEmpty else { return rawText }
        
        // Try to find a place to inject character info
        var enriched = rawText
        let groupTerms = ["roommates", "roommate", "friends", "friend", "people", "guys", "group", "we", "us"]
        
        for term in groupTerms {
            if enriched.lowercased().contains(term) {
                // Find the first occurrence and replace it
                if let range = enriched.range(of: term, options: [.caseInsensitive]) {
                    let originalTerm = String(enriched[range])
                    enriched.replaceSubrange(range, with: "\(originalTerm) including \(characterSummary)")
                    print("✅ Injected character names into memory via '\(originalTerm)'")
                    return enriched
                }
            }
        }
        
        // If no keyword found, append character info at the end
        print("⚠️ No group term found, appending character info to memory")
        return rawText + " (with \(characterSummary))"
    }
    
    /// Extracts simple character list from verbose character context
    /// Returns format: "Ian (Brazilian), Robbie (White), Ben (pale blonde)"
    private func extractSimpleCharacterList(from context: String) -> String {
        let lines = context.components(separatedBy: "\n")
        var simplified: [String] = []
        
        for line in lines {
            // Skip headers and empty lines
            if line.contains("SCENE CHARACTERS") || line.isEmpty || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            
            // Parse lines like: "Ian (the friend) - young adult, Brazilian, Short brown hair..."
            if let dashIndex = line.firstIndex(of: "-") {
                let namePart = String(line[..<dashIndex]).trimmingCharacters(in: .whitespaces)
                let detailsPart = String(line[line.index(after: dashIndex)...])
                
                // Extract name (remove relationship info in parentheses)
                var name = namePart
                if let parenIndex = namePart.firstIndex(of: "(") {
                    name = String(namePart[..<parenIndex]).trimmingCharacters(in: .whitespaces)
                }
                
                // Extract race/ethnicity (usually after first comma, before second)
                let details = detailsPart.components(separatedBy: ",")
                if details.count >= 2 {
                    let race = details[1].trimmingCharacters(in: .whitespaces)
                    simplified.append("\(name) (\(race))")
                }
            }
        }
        
        return simplified.joined(separator: ", ")
    }

    private enum NarratorPresence: String {
        case likelyPresent
        case uncertain
        case likelyAbsent

        var shouldAttachHeadshot: Bool {
            self != .likelyAbsent
        }
    }

    private struct NarratorPresenceDecision {
        let presence: NarratorPresence
        let reason: String
        let firstPersonDetected: Bool
        let confidenceScore: Int
    }

    private func countRegexMatches(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    private func inferNarratorPresence(memoryText: String, entry: MemoryEntry) -> NarratorPresenceDecision {
        let lower = memoryText.lowercased()

        let strongAbsentPatterns = [
            #"\bwithout me\b"#,
            #"\bnot me\b"#,
            #"\bi was not there\b"#,
            #"\bi wasn't there\b"#,
            #"\bi did not attend\b"#,
            #"\bi didn't attend\b"#,
            #"\bthey told me about\b"#,
            #"\bi heard about\b"#,
            #"\bhe told me about\b"#,
            #"\bshe told me about\b"#,
            #"\bmy (mom|dad|friend|brother|sister|wife|husband|partner) told me\b"#
        ]

        let selfExperiencePatterns = [
            #"\bmy birthday\b"#,
            #"\bwhen i was\b"#,
            #"\bi remember\b"#,
            #"\bour family\b"#,
            #"\bmy first\b"#,
            #"\bwe (went|were|had|celebrated|traveled|visited)\b"#
        ]

        var score = 0
        var reasons: [String] = []

        for pattern in strongAbsentPatterns where lower.range(of: pattern, options: .regularExpression) != nil {
            score -= 120
            reasons.append("explicit narrator-absent phrasing")
            break
        }

        let firstPersonPattern = #"\b(i|me|my|mine|we|our|us)\b"#
        let firstPersonCount = countRegexMatches(firstPersonPattern, in: lower)
        let firstPersonDetected = firstPersonCount > 0
        if firstPersonDetected {
            let firstPersonScore = min(120, firstPersonCount * 20)
            score += firstPersonScore
            reasons.append("first-person cues x\(firstPersonCount)")
        }

        for pattern in selfExperiencePatterns where lower.range(of: pattern, options: .regularExpression) != nil {
            score += 35
            reasons.append("self-experience context")
            break
        }

        if let chapter = entry.chapter?.trimmingCharacters(in: .whitespacesAndNewlines), !chapter.isEmpty {
            score += 15
            reasons.append("chapter metadata present")
        }

        if let profileName = self.profileName {
            let profileToken = normalizedFirstToken(profileName)
            if !profileToken.isEmpty,
               lower.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: profileToken))\b"#, options: .regularExpression) != nil {
                score += 10
                reasons.append("mentions profile name")
            }
        }

        let presence: NarratorPresence
        if score >= 60 {
            presence = .likelyPresent
        } else if score <= -60 {
            presence = .likelyAbsent
        } else {
            presence = .uncertain
        }

        let reasonText = reasons.isEmpty ? "no clear narrator signal" : reasons.joined(separator: ", ")
        return NarratorPresenceDecision(
            presence: presence,
            reason: reasonText,
            firstPersonDetected: firstPersonDetected,
            confidenceScore: score
        )
    }
    
    /// Creates character enforcement directly from CharacterDetails
    /// ✅ GENERAL FIX: Uses actual data fields directly, works for ANY race/ethnicity
    private func buildSimplifiedCharacterContext(for entry: MemoryEntry) -> String {
        guard let detailsString = entry.value(forKey: "characterDetails") as? String,
              let data = detailsString.data(using: .utf8),
              let details = try? JSONDecoder().decode(CharacterDetails.self, from: data) else {
            print("⚠️ buildSimplifiedCharacterContext: No character details found for entry")
            return ""
        }
        
        var characterList: [String] = []
        
        let simpProfileID = currentProfileID
            ?? (entry.value(forKey: "profileID") as? UUID)
            ?? UUID()
        for rawChar in details.characters {
            let char = enrichCharacterForPrompt(rawChar, entry: entry, profileID: simpProfileID)
            var desc = "\(char.name): "
            
            var parts: [String] = []
            if !char.ethnicity.isEmpty { parts.append(char.ethnicity) }
            if !char.hairAndFeatures.isEmpty { parts.append(char.hairAndFeatures) }
            if !char.clothes.isEmpty { parts.append(char.clothes) }
            
            if parts.isEmpty && !char.combinedAppearance.isEmpty {
                parts.append(char.combinedAppearance)
            }
            
            desc += parts.joined(separator: ", ")
            
            characterList.append(desc)
        }
        
        if characterList.isEmpty {
            print("⚠️ buildSimplifiedCharacterContext: Empty character list after processing")
            return ""
        }
        
        let result = characterList.joined(separator: ", ")
        print("✅ buildSimplifiedCharacterContext: Built context: \(result)")
        return result
    }
    
    /// Confidence-based scoring system for narrator detection
    /// Returns a weighted score indicating how likely a character is the narrator
    /// Higher scores indicate stronger confidence
    private func narratorScore(
        _ char: CharacterDetails.Character,
        in details: CharacterDetails,
        derivedNarratorName: String?,
        sceneTextForNarratorScoring: String? = nil
    ) -> Int {
        var score = 0
        let name = char.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let relationship = char.relationshipToNarrator.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Definitive: explicit markers in name (+100)
        let nameMarkers = ["(me)", "(narrator)", "(self)", "(main)", "(i)"]
        if nameMarkers.contains(where: { name.contains($0) }) {
            score += 100
        }
        
        // Definitive: relationship indicates narrator (+100)
        let narratorRels = ["me", "self", "myself", "narrator", "main character", "the narrator", "i am", "this is me"]
        if narratorRels.contains(where: { relationship == $0 || relationship.contains($0) }) {
            score += 100
        }
        
        // Strong: only character in memory (+100)
        if details.characters.count == 1 {
            score += 100
        }
        
        // Medium: first character in list (+30)
        if details.characters.first?.id == char.id {
            score += 30
        }
        
        // Weak: name matches derived narrator name (+20)
        if let narratorName = derivedNarratorName?.lowercased(), !narratorName.isEmpty {
            let charFirst = name.components(separatedBy: " ").first?.replacingOccurrences(of: "(me)", with: "").trimmingCharacters(in: .whitespaces) ?? ""
            let narrFirst = narratorName.components(separatedBy: " ").first?.replacingOccurrences(of: "(me)", with: "").trimmingCharacters(in: .whitespaces) ?? ""
            if !charFirst.isEmpty && !narrFirst.isEmpty && charFirst == narrFirst {
                score += 20
            }
        }
        
        // Weak: name matches profile name (+20)
        if let profileName = self.profileName?.lowercased(), !profileName.isEmpty {
            let profileFirst = profileName.components(separatedBy: " ").first ?? profileName
            let charFirst = name.components(separatedBy: " ").first?
                .replacingOccurrences(of: "(me)", with: "")
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !charFirst.isEmpty && !profileFirst.isEmpty && charFirst == profileFirst {
                score += 20
            }
        }
        
        // Weak: scene analysis (+15)
        if let sceneText = sceneTextForNarratorScoring?.lowercased() {
            let otherCharNames = details.characters
                .filter { $0.id != char.id }
                .map { $0.name.lowercased() }
            
            // If scene says "narrator and [otherChar]" and this char isn't mentioned, likely narrator
            for otherName in otherCharNames {
                if sceneText.contains("narrator") && sceneText.contains(otherName) && !sceneText.contains(name) {
                    score += 15
                    break
                }
            }
            
            // Also check: if scene says "only X people: narrator and [otherChar]", the unmentioned char is narrator
            if sceneText.contains("only") && sceneText.contains("people") {
                let mentionedChars = otherCharNames.filter { sceneText.contains($0) }
                if mentionedChars.count == 1 && !sceneText.contains(name) {
                    score += 15
                }
            }
        }
        
        return score
    }
    
    /// Multi-filter detection: checks if a character is the narrator/main character
    /// Uses confidence scoring threshold (>= 30) for robust detection
    private func isNarratorCharacter(
        _ char: CharacterDetails.Character,
        in details: CharacterDetails,
        derivedNarratorName: String?,
        sceneTextForNarratorScoring: String? = nil
    ) -> Bool {
        narratorScore(
            char,
            in: details,
            derivedNarratorName: derivedNarratorName,
            sceneTextForNarratorScoring: sceneTextForNarratorScoring
        ) >= 30
    }
    
    private func traitListFromCharacter(_ character: CharacterDetails.Character) -> [String] {
        var traits: [String] = []
        if !character.age.isEmpty {
            traits.append("age \(character.age)")
        }
        if !character.gender.isEmpty {
            traits.append(character.gender.lowercased())
        }
        if !character.ethnicity.isEmpty {
            traits.append(character.ethnicity)
        }
        if !character.hairAndFeatures.isEmpty {
            traits.append(character.hairAndFeatures)
        }
        if !character.clothes.isEmpty {
            traits.append("wearing \(character.clothes)")
        }
        if traits.isEmpty && !character.combinedAppearance.isEmpty {
            traits.append(character.combinedAppearance)
        }
        return traits
    }

    private struct HydratedNameCandidate {
        let name: String
        let ethnicity: String?
        let gender: String?
        let hairAndFeatures: String?
    }

    private func normalizedFirstToken(_ value: String) -> String {
        normalizeLooseText(value).split(separator: " ").first.map(String.init) ?? ""
    }

    private func knownCharacterNames(for profileID: UUID, excluding entry: MemoryEntry) -> [String] {
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = MemoryUserScope.profilePredicate(profileID: profileID)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]

        let sourceMemories: [MemoryEntry]
        do {
            sourceMemories = try PersistenceController.shared.container.viewContext.fetch(request)
        } catch {
            print("⚠️ Name detection: failed to fetch memories for known names: \(error.localizedDescription)")
            return []
        }

        var names: [String] = []
        for memory in sourceMemories where memory.objectID != entry.objectID {
            guard let detailsString = memory.characterDetails,
                  !detailsString.isEmpty,
                  let data = detailsString.data(using: .utf8),
                  let details = try? JSONDecoder().decode(CharacterDetails.self, from: data) else { continue }
            for char in details.characters {
                let trimmed = char.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                names.append(trimmed)
            }
        }

        var seen = Set<String>()
        return names.filter { raw in
            let normalized = normalizeLooseText(raw)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }

    private func autoDetectedNames(
        from memoryText: String,
        profileID: UUID,
        excluding entry: MemoryEntry,
        excludedTokens: Set<String>
    ) -> [String] {
        let lowerText = memoryText.lowercased()
        let knownNames = knownCharacterNames(for: profileID, excluding: entry)
        var detected: [String] = []
        var seen = Set<String>()

        // First pass: known names from profile memory history (works even if user typed lowercase).
        for known in knownNames {
            let normalizedKnown = normalizeLooseText(known)
            let firstToken = normalizedFirstToken(known)
            guard !normalizedKnown.isEmpty, !firstToken.isEmpty else { continue }
            guard !excludedTokens.contains(firstToken) else { continue }

            let fullPattern = "(^|\\b)\(NSRegularExpression.escapedPattern(for: normalizedKnown))($|\\b)"
            let tokenPattern = "(^|\\b)\(NSRegularExpression.escapedPattern(for: firstToken))($|\\b)"
            let matched = lowerText.range(of: fullPattern, options: .regularExpression) != nil
                || lowerText.range(of: tokenPattern, options: .regularExpression) != nil
            guard matched, !seen.contains(normalizedKnown) else { continue }
            seen.insert(normalizedKnown)
            detected.append(known)
        }

        // Second pass: capitalized name-like tokens for new names.
        let regex = try? NSRegularExpression(pattern: #"\b[A-Z][a-z]{1,20}(?:\s+[A-Z][a-z]{1,20})?\b"#)
        let nsText = memoryText as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let stopWords: Set<String> = [
            "one", "day", "we", "our", "my", "me", "i", "the", "a", "an", "it", "and",
            "in", "on", "at", "to", "for", "with", "of", "middle", "park", "woods", "creek"
        ]
        regex?.enumerateMatches(in: memoryText, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let raw = nsText.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = normalizeLooseText(raw)
            let firstToken = normalizedFirstToken(raw)
            guard !normalized.isEmpty, !firstToken.isEmpty else { return }
            guard !stopWords.contains(firstToken), !excludedTokens.contains(firstToken) else { return }
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            detected.append(raw)
        }

        print("🔎 Auto-detected names for memory '\(entry.prompt ?? "Untitled")': \(detected)")
        return detected
    }

    private func hydratedStableTraitsByName(
        _ name: String,
        entry: MemoryEntry,
        profileID: UUID
    ) -> HydratedNameCandidate? {
        let normalizedName = normalizeLooseText(name)
        guard !normalizedName.isEmpty else { return nil }

        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = MemoryUserScope.profilePredicate(profileID: profileID)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]

        let sourceMemories: [MemoryEntry]
        do {
            sourceMemories = try PersistenceController.shared.container.viewContext.fetch(request)
        } catch {
            print("⚠️ Hydration failed to fetch memories for '\(name)': \(error.localizedDescription)")
            return nil
        }

        typealias TraitCandidate = (value: String, normalized: String, createdAt: Date, source: String)
        var ethnicityCandidates: [TraitCandidate] = []
        var genderCandidates: [TraitCandidate] = []
        var hairCandidates: [TraitCandidate] = []
        var scannedMemories = 0
        var matchedCharacters = 0

        for memory in sourceMemories where memory.objectID != entry.objectID {
            scannedMemories += 1
            guard let detailsString = memory.characterDetails,
                  !detailsString.isEmpty,
                  let data = detailsString.data(using: .utf8),
                  let details = try? JSONDecoder().decode(CharacterDetails.self, from: data) else { continue }
            let createdAt = memory.createdAt ?? .distantPast

            for candidate in details.characters where normalizeLooseText(candidate.name) == normalizedName {
                matchedCharacters += 1
                let snapshot = stableTraitSnapshot(for: candidate)
                if let ethnicity = snapshot.ethnicity {
                    let normalized = normalizeLooseText(ethnicity.value)
                    if !normalized.isEmpty, !isWeakTraitValue(ethnicity.value) {
                        ethnicityCandidates.append((ethnicity.value, normalized, createdAt, ethnicity.source))
                    }
                }
                if let gender = snapshot.gender {
                    let normalized = normalizeLooseText(gender.value)
                    if !normalized.isEmpty, !isWeakTraitValue(gender.value) {
                        genderCandidates.append((gender.value, normalized, createdAt, gender.source))
                    }
                }
                if let hair = snapshot.hairAndFeatures {
                    let normalized = normalizeLooseText(hair.value)
                    if !normalized.isEmpty, !isWeakTraitValue(hair.value) {
                        hairCandidates.append((hair.value, normalized, createdAt, hair.source))
                    }
                }
            }
        }

        print("🔎 Hydration scan '\(name)': scanned \(scannedMemories) memories, matched \(matchedCharacters) same-name characters.")

        func resolve(_ values: [TraitCandidate], field: String) -> String? {
            print("🔎 Hydration field '\(field)' for '\(name)': \(values.count) usable candidates.")
            guard !values.isEmpty else {
                print("⏭️ Hydration '\(field)' no candidate for '\(name)'.")
                return nil
            }

            let grouped = Dictionary(grouping: values, by: { $0.normalized })
            let ranked = grouped.map { normalized, entries -> (normalized: String, count: Int, newest: Date, chosen: TraitCandidate) in
                let sortedByDate = entries.sorted { $0.createdAt > $1.createdAt }
                return (normalized, entries.count, sortedByDate.first?.createdAt ?? .distantPast, sortedByDate[0])
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.newest > rhs.newest
                }
                return lhs.count > rhs.count
            }

            guard let top = ranked.first else { return nil }
            if ranked.count > 1 {
                let second = ranked[1]
                if top.normalized != second.normalized && top.count == second.count {
                    print("⚠️ Hydration '\(field)' ambiguous for '\(name)' (equal support); skipping field.")
                    return nil
                }
            }
            return top.chosen.value
        }

        let ethnicity = resolve(ethnicityCandidates, field: "ethnicity")
        let gender = resolve(genderCandidates, field: "gender")
        let hair = resolve(hairCandidates, field: "hairAndFeatures")
        if ethnicity == nil && gender == nil && hair == nil {
            return nil
        }
        return HydratedNameCandidate(name: name, ethnicity: ethnicity, gender: gender, hairAndFeatures: hair)
    }

    private func stableTraitList(from candidate: HydratedNameCandidate) -> [String] {
        var traits: [String] = []
        if let gender = candidate.gender, !gender.isEmpty {
            traits.append(gender.lowercased())
        }
        if let ethnicity = candidate.ethnicity, !ethnicity.isEmpty {
            traits.append(ethnicity)
        }
        if let hair = candidate.hairAndFeatures, !hair.isEmpty {
            traits.append(hair)
        }
        return traits
    }

    /// Narrator line when there is no matching character card row (or narrator not in JSON list).
    private func fallbackNarratorCharacterLine(characterIndex: Int, profileName: String) -> String {
        if subjectPhoto != nil {
            return "Character \(characterIndex): \(profileName) - narrator (appearance guided by provided headshot image)"
        }
        var traits: [String] = []
        let eth = ethnicity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !eth.isEmpty {
            traits.append(eth)
        }
        let gen = gender.trimmingCharacters(in: .whitespacesAndNewlines)
        if !gen.isEmpty {
            traits.append("presenting as \(gen.lowercased())")
        }
        let other = otherDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        if !other.isEmpty {
            traits.append(translateRaceToDescriptor(other))
        }
        if traits.isEmpty {
            return "Character \(characterIndex): \(profileName) - narrator (no photo: use NARRATOR APPEARANCE section and CHARACTER CARDS for likeness)"
        }
        return "Character \(characterIndex): \(profileName) - narrator - \(traits.joined(separator: ", "))"
    }

    /// Text-only and headshot policy for the memoir subject, injected into every interior image prompt when the narrator may appear.
    private func narratorIdentityPromptSection(narratorPresence: NarratorPresence, hasHeadshot: Bool) -> String? {
        guard narratorPresence != .likelyAbsent else { return nil }
        var lines: [String] = []
        if hasHeadshot {
            lines.append("A headshot reference image is attached. Use it as the primary face and appearance anchor for the memoir subject when they appear.")
        } else {
            lines.append("No headshot reference image is attached. Follow the text guidance below for the memoir subject; do not substitute a different ethnicity or regional appearance than specified.")
        }
        if let name = profileName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            lines.append("Memoir subject display name (for 'I' / pronoun mapping): \(name).")
        }
        var bits: [String] = []
        if let vision = faceDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !vision.isEmpty {
            bits.append(vision)
        }
        let eth = ethnicity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !eth.isEmpty {
            bits.append("Ethnicity / heritage (for skin tone and features): \(eth). Render with appropriate skin tone, facial features, and hair characteristics for this heritage.")
        }
        let gen = gender.trimmingCharacters(in: .whitespacesAndNewlines)
        if !gen.isEmpty {
            bits.append("presenting as \(gen.lowercased())")
        }
        let other = otherDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        if !other.isEmpty {
            bits.append(translateRaceToDescriptor(other))
        }
        if !bits.isEmpty {
            lines.append("Apply when the memoir subject or narrator is shown: " + bits.joined(separator: "; ") + ".")
        } else if !hasHeadshot {
            lines.append("If CHARACTER CARDS list ethnicity or heritage for a named person, render it consistently.")
        }
        return lines.joined(separator: "\n")
    }

    /// Builds final character lines using explicit character-card details with minimal mutation.
    private func buildCharacterList(for entry: MemoryEntry, sceneDescription: String? = nil, includeNarrator: Bool) -> String {
        var characterLines: [String] = []
        var characterIndex = 1
        let derivedNarratorName = deriveSubjectName(from: entry)

        // Characters from database (minimal mutation, no face-descriptor merging)
        if let detailsString = entry.value(forKey: "characterDetails") as? String,
           let data = detailsString.data(using: .utf8),
           let details = try? JSONDecoder().decode(CharacterDetails.self, from: data) {
            let listProfileID = currentProfileID
                ?? (entry.value(forKey: "profileID") as? UUID)
                ?? UUID()
            let enrichedDetailsCharacters = details.characters.map {
                enrichCharacterForPrompt($0, entry: entry, profileID: listProfileID)
            }
            let enrichedDetails = CharacterDetails(characters: enrichedDetailsCharacters)
            
            let narratorCandidate = enrichedDetails.characters.max { lhs, rhs in
                narratorScore(lhs, in: enrichedDetails, derivedNarratorName: derivedNarratorName, sceneTextForNarratorScoring: sceneDescription) <
                narratorScore(rhs, in: enrichedDetails, derivedNarratorName: derivedNarratorName, sceneTextForNarratorScoring: sceneDescription)
            }
            let narratorId = includeNarrator ? narratorCandidate?.id : nil

            if includeNarrator, let narrator = narratorCandidate {
                let narratorTraits = traitListFromCharacter(narrator)
                var line = "Character \(characterIndex): \(narrator.name)"
                if !narratorTraits.isEmpty {
                    line += " - \(narratorTraits.joined(separator: ", "))"
                }
                characterLines.append(line)
                characterIndex += 1
            } else if includeNarrator, let profileName = self.profileName, !profileName.isEmpty {
                characterLines.append(fallbackNarratorCharacterLine(characterIndex: characterIndex, profileName: profileName))
                characterIndex += 1
            }

            for char in enrichedDetails.characters where char.id != narratorId {
                var line = "Character \(characterIndex): \(char.name)"
                let traits = traitListFromCharacter(char)
                if !traits.isEmpty {
                    line += " - \(traits.joined(separator: ", "))"
                }
                characterLines.append(line)
                characterIndex += 1
            }
        } else {
            if includeNarrator, let profileName = self.profileName, !profileName.isEmpty {
                characterLines.append(fallbackNarratorCharacterLine(characterIndex: characterIndex, profileName: profileName))
                characterIndex += 1
            }

            // Auto-detect recurring names for memories with missing characterDetails
            let listProfileID = currentProfileID
                ?? (entry.value(forKey: "profileID") as? UUID)
                ?? UUID()
            let rawText = (entry.text ?? "") + " " + (entry.prompt ?? "")
            var excludedTokens: Set<String> = ["i", "me", "my", "mine", "we", "our", "us", "narrator"]
            if let profileName = self.profileName {
                let profileToken = normalizedFirstToken(profileName)
                if !profileToken.isEmpty {
                    excludedTokens.insert(profileToken)
                }
            }
            let detectedNames = autoDetectedNames(
                from: rawText,
                profileID: listProfileID,
                excluding: entry,
                excludedTokens: excludedTokens
            )
            for detectedName in detectedNames {
                guard let hydrated = hydratedStableTraitsByName(detectedName, entry: entry, profileID: listProfileID) else { continue }
                let stableTraits = stableTraitList(from: hydrated)
                guard !stableTraits.isEmpty else { continue }
                let line = "Character \(characterIndex): \(hydrated.name) - \(stableTraits.joined(separator: ", "))"
                characterLines.append(line)
                print("✅ Injected hydrated character line: \(line)")
                characterIndex += 1
            }
        }
        
        if characterLines.isEmpty {
            return ""
        }
        
        return characterLines.joined(separator: "\n")
    }
    
    /// Builds character enforcement string using actual CharacterDetails data
    /// ✅ GENERAL FIX: Data-driven, works for ANY race/ethnicity combination
    private func buildStrongCharacterEnforcement(simplifiedContext: String, for entry: MemoryEntry) -> String {
        guard let detailsString = entry.value(forKey: "characterDetails") as? String,
              let data = detailsString.data(using: .utf8),
              let details = try? JSONDecoder().decode(CharacterDetails.self, from: data) else {
            // Fallback to simple enforcement if parsing fails
            return """
            CRITICAL VISUAL REQUIREMENT: This scene contains MULTIPLE DISTINCT PEOPLE with DIFFERENT APPEARANCES.
            Characters: \(simplifiedContext)
            EACH PERSON MUST BE VISUALLY DISTINCT. DO NOT make all characters share the same appearance.
            
            """
        }
        
        let enforceProfileID = currentProfileID
            ?? (entry.value(forKey: "profileID") as? UUID)
            ?? UUID()
        var characterBreakdown: [String] = []
        for (index, rawChar) in details.characters.enumerated() {
            let char = enrichCharacterForPrompt(rawChar, entry: entry, profileID: enforceProfileID)
            var charDesc = "Character \(index + 1) (\(char.name)): "
            
            var enforceParts: [String] = []
            if !char.ethnicity.isEmpty { enforceParts.append(char.ethnicity) }
            if !char.hairAndFeatures.isEmpty { enforceParts.append(char.hairAndFeatures) }
            if !char.clothes.isEmpty { enforceParts.append("wearing \(char.clothes)") }
            
            if enforceParts.isEmpty && !char.combinedAppearance.isEmpty {
                enforceParts.append(char.combinedAppearance)
            }
            
            charDesc += enforceParts.isEmpty ? "appearance not specified" : enforceParts.joined(separator: ", ")
            
            // Add age if available
            if !char.age.isEmpty {
                charDesc += ", age \(char.age)"
            }
            
            characterBreakdown.append(charDesc)
        }
        
        let characterList = characterBreakdown.joined(separator: "\n")
        
        return """
        CRITICAL VISUAL REQUIREMENT: This scene contains MULTIPLE DISTINCT PEOPLE with DIFFERENT APPEARANCES.
        
        \(characterList)
        
        EACH PERSON MUST BE VISUALLY DISTINCT with their specified appearance.
        DO NOT make all characters share the same appearance or skin tone.
        DO NOT default to a single appearance. Show clear diversity across all characters.
        
        """
    }
    
    // MARK: - Prompt Assembler v2 Helpers
    private func deriveSubjectName(from entry: MemoryEntry) -> String? {
        guard let detailsString = entry.value(forKey: "characterDetails") as? String,
              let data = detailsString.data(using: .utf8),
              let details = try? JSONDecoder().decode(CharacterDetails.self, from: data) else {
            return nil
        }
        
        // Check for explicit markers in name
        let nameMarkers = ["(me)", "(narrator)", "(self)", "(main)", "(i)"]
        for marker in nameMarkers {
            if let me = details.characters.first(where: { $0.name.lowercased().contains(marker) }) {
                return me.name
            }
        }
        
        // Check for narrator relationships
        let narratorRels = ["me", "self", "myself", "narrator", "main character", "the narrator", "i am"]
        for rel in narratorRels {
            if let narrator = details.characters.first(where: {
                let r = $0.relationshipToNarrator.lowercased()
                return r == rel || r.contains(rel)
            }) {
                return narrator.name
            }
        }
        
        // First character with empty relationship when others have relationships
        if let firstChar = details.characters.first,
           firstChar.relationshipToNarrator.isEmpty,
           details.characters.dropFirst().contains(where: { !$0.relationshipToNarrator.isEmpty }) {
            return firstChar.name
        }
        
        return nil
    }
    
    /// Extracts the style requirement text for the final prompt
    private func extractStyleRequirement(for style: ArtStyle, custom: String?) -> String {
        style.memoryIllustrationStyleDescription(customText: custom)
    }
    
    private func styleDescriptorLine(for style: ArtStyle, custom: String?) -> String {
        switch style {
        case .kidsBook:
            return "Style: Children's book watercolor; simple shapes; gentle colors; no photorealism."
        case .comic:
            return "Style: Comic book art; bold ink outlines; halftone shading; vibrant colors; dynamic poses."
        case .realistic:
            return "Style: Soft naturalistic illustration; realistic proportions; gentle lighting."
        case .custom:
            let text = (custom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Style: Artistic illustration." : "Style: \(text)."
        }
    }
    
    /// Sends prompt to the selected Gemini image model for image generation
    private func generateImageWithGemini(
        _ prompt: String,
        size: String = "1792x1024",
        referenceImages: [UIImage] = []
    ) async throws -> UIImage? {
        print("🔍 Checking Gemini service availability...")
        print("🔍 geminiImageSvc is \(geminiImageSvc != nil ? "available" : "nil")")
        
        guard let geminiSvc = geminiImageSvc else {
            print("⚠️ Gemini service not available (geminiImageSvc is nil), skipping")
            return nil
        }
        
        let model = effectiveGeminiModel
        print("🚀 Using Gemini model \(model) for image generation with \(referenceImages.count) reference image(s)...")
        return try await geminiSvc.generateImage(
            prompt: prompt,
            size: size,
            model: model,
            referenceImages: referenceImages
        )
    }

    private var imageGenerationSizeForCurrentStyle: String {
        currentArtStyle == .kidsBook ? "4:3" : "1792x1024"
    }
    
    /// Sends prompt directly to GPT-5 - GPT-5 handles everything and returns the image
    /// Just like ChatGPT web - no system prompts, no function calling setup, just the prompt
    private func generateImageWithGPT5(_ prompt: String, size: String = "1792x1024") async throws -> UIImage? {
        var body: [String: Any] = [
            "model": "gpt-5",
            "messages": [
                ["role": "user", "content": prompt]
            ]
            // No system prompt, no tools, no instructions - just the prompt
        ]
        
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Set timeout to 3 minutes - image generation takes a while
        req.timeoutInterval = 180.0
        
        print("🚀 Sending prompt directly to GPT-5 (no instructions, no function calling)...")
        
        do {
            let startedAt = Date()
            let (data, response) = try await URLSession.shared.data(for: req)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ GPT-5: Invalid response type")
                return nil
            }
            await logOpenAIChatTelemetry(
                model: "gpt-5",
                promptChars: prompt.count,
                responseData: data,
                statusCode: httpResponse.statusCode,
                success: (200...299).contains(httpResponse.statusCode),
                startedAt: startedAt
            )
            
            print("🔍 GPT-5 HTTP status: \(httpResponse.statusCode)")
            
            // If GPT-5 doesn't exist or doesn't support this, fall back
            if httpResponse.statusCode == 404 {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("⚠️ GPT-5 model not found (404). Response: \(errorText)")
                print("⚠️ GPT-5 not available, will fall back to GPT-4o enhancement + DALL-E 3")
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ GPT-5 returned error \(httpResponse.statusCode): \(errorText)")
                return nil
            }
            
            print("✅ GPT-5 request succeeded, parsing response...")
        
            // Parse response - GPT-5 might return image URL directly, function call, or content
            let responseText = String(data: data, encoding: .utf8) ?? ""
            print("🔍 GPT-5 raw response (first 1000 chars): \(responseText.prefix(1000))")
            
            struct ToolCall: Decodable {
                let id: String?
                let type: String
                let function: FunctionCall?
            }
            
            struct FunctionCall: Decodable {
                let name: String?
                let arguments: String?
            }
            
            struct Message: Decodable {
                let role: String?
                let content: String?
                let tool_calls: [ToolCall]?
            }
            
            struct Choice: Decodable {
                let message: Message
            }
            
            struct Root: Decodable {
                let choices: [Choice]
            }
            
            let result = try JSONDecoder().decode(Root.self, from: data)
            
            // Check if GPT-5 returned a function call (it might do this automatically)
            if let toolCalls = result.choices.first?.message.tool_calls,
               let firstCall = toolCalls.first,
               firstCall.type == "function",
               let argsString = firstCall.function?.arguments,
               let argsData = argsString.data(using: .utf8),
               let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                
                // If GPT-5 called generate_image function, extract the prompt and call DALL-E 3
                if let dallePrompt = args["prompt"] as? String {
                    print("✅ GPT-5 automatically called image generation, using optimized prompt")
                    let imageSvc = OpenAIImageService(apiKey: openAIKey)
                    let images = try await imageSvc.generateImages(
                        prompt: dallePrompt,
                        referencedImageIDs: [],
                        n: 1,
                        size: args["size"] as? String ?? size
                    )
                    return images.first
                }
            }
            
            // Check if GPT-5 returned image URL directly in content
            if let content = result.choices.first?.message.content {
                // Try to extract image URL from content
                if let urlRange = content.range(of: "https://[^\\s]+", options: .regularExpression),
                   let imageURL = URL(string: String(content[urlRange])) {
                    print("✅ GPT-5 returned image URL directly, downloading...")
                    let (imageData, _) = try await URLSession.shared.data(from: imageURL)
                    return UIImage(data: imageData)
                }
            }
            
            print("⚠️ GPT-5 response format not recognized, falling back")
            return nil
            
        } catch let error as NSError {
            if error.code == NSURLErrorTimedOut {
                print("⏱️ GPT-5 request timed out after 3 minutes")
                print("💡 This likely means GPT-5 is not available or the model name is incorrect")
            } else {
                print("❌ GPT-5 request failed with error: \(error.localizedDescription)")
                print("❌ Error code: \(error.code), domain: \(error.domain)")
            }
            return nil
        } catch {
            print("❌ GPT-5 request failed with unknown error: \(error)")
            return nil
        }
    }
    
    /// Fallback: Rewrites/enhances the prompt using GPT-4o if GPT-5 doesn't work
    private func enhancePromptForDALLE3(_ prompt: String) async throws -> String {
        let systemPrompt = """
        You are an expert at creating image generation prompts for DALL-E 3. Your job is to rewrite the given prompt to be more effective, clear, and optimized for image generation.
        
        CRITICAL RULES:
        - PRESERVE the character list section (Character 1, Character 2, etc.) EXACTLY as provided - do not remove or modify it
        - PRESERVE the STYLE section exactly as provided
        - Only enhance the scene description portion for better visual clarity
        - Improve clarity and visual specificity in the scene description
        - Ensure the prompt flows naturally
        - Do not add details that weren't in the original prompt
        - Do not remove important character or style information
        
        The prompt structure should remain: Character list, then scene description, then STYLE section.
        
        Return ONLY the enhanced prompt, no explanations or extra text.
        """
        
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]
        
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("✨ Enhancing prompt with GPT-4o (fallback)...")
        let startedAt = Date()
        let (data, response) = try await URLSession.shared.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        
        struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
        struct Root: Decodable { let choices: [Choice] }
        
        let enhancedPrompt = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content ?? prompt
        print("✨ Enhanced prompt → \(enhancedPrompt.prefix(200))...")
        await logOpenAIChatTelemetry(
            model: "gpt-4o",
            promptChars: prompt.count,
            responseData: data,
            statusCode: statusCode,
            success: true,
            startedAt: startedAt
        )
        return enhancedPrompt
    }
    
    /// Assembles a concise structured prompt: style + no-text rule first, then memory/scene, then reminders.
    private func assembleFinalPrompt(
        memoryText: String,
        characters: String,
        narratorPresence: NarratorPresence,
        sceneDescription: String,
        style: ArtStyle,
        customStyle: String?,
        hasHeadshot: Bool
    ) -> String {
        var parts: [String] = []
        let styleText = extractStyleRequirement(for: style, custom: customStyle)

        parts.append("IMAGE STYLE (high priority, must follow): \(styleText)")
        parts.append(ArtStyle.coverStyleBindingInstruction)
        parts.append("")
        if hasHeadshot {
            if style == .kidsBook {
                parts.append("STYLE OVERRIDE (highest priority): The attached reference photo is for IDENTITY/LIKENESS ONLY. RE-RENDER the person in the IMAGE STYLE above. Do NOT preserve photographic skin texture, lens depth-of-field, photo lighting, fabric weave, or HDR tonality. Pose and clothing may be illustrative; only the face must read as the same person as the reference.")
            } else {
                parts.append("STYLE OVERRIDE (highest priority): The final rendering MUST match the IMAGE STYLE above. The attached reference photo is for IDENTITY/LIKENESS ONLY — do NOT copy its photographic textures. Do NOT default to watercolor, children's-book, or storybook rendering. Pose and clothing may be illustrative; only the face must read as the same person as the reference. Render strictly in: \(styleText)")
            }
            parts.append("")
        }
        parts.append("TEXT RENDERING RULE (mandatory): Do not render any words, letters, numbers, titles, chapter headings, captions, page numbers, QR codes, watermarks, signs, logos, or any typographic marks anywhere in the image. The output must be pure illustration with zero text.")
        if style == .kidsBook {
            parts.append("FACIAL DETAIL RULE: Eyes warm, painted, and expressive in a soft children's-book way. Suggest iris and pupil with gentle painted shapes, not photographic detail. Faces stay soft and hand-drawn.")
        }
        parts.append("")
        parts.append("MEMORY TEXT (do not contradict): \(memoryText)")
        parts.append("")

        // Character cards (minimal mutation)
        if !characters.isEmpty {
            parts.append("CHARACTER CARDS:")
            parts.append(characters)
            parts.append("")
        }

        parts.append("NARRATOR PRESENCE HINT: \(narratorPresence.rawValue)")
        parts.append("")
        if let identityBlock = narratorIdentityPromptSection(narratorPresence: narratorPresence, hasHeadshot: hasHeadshot) {
            parts.append("NARRATOR APPEARANCE (likeness policy + profile notes):")
            parts.append(identityBlock)
            parts.append("")
        }

        parts.append("SCENE SUMMARY: \(sceneDescription)")
        parts.append("")

        parts.append("STYLE: \(styleText)")
        if let styleRefHint = styleReferencePromptHint(for: style) {
            parts.append("")
            parts.append(styleRefHint)
        }
        if narratorPresence != .likelyAbsent {
            parts.append("")
            parts.append("NARRATOR REFERENCE IMAGE RULE: If a narrator headshot reference image is attached, use it as the primary visual identity anchor for the narrator whenever the narrator is present or plausibly present in this memory.")
            parts.append("NARRATOR IDENTITY RULE: If a narrator reference image is attached, preserve that person's core identity. You may adapt apparent age to fit memory-era cues without changing who the narrator is.")
        }

        // Add realistic face blurring if needed
        if style == .realistic {
            parts.append("")
            parts.append("Camera pulled back, face partly turned away or softly out of focus so exact features are not discernible. Or another method where the face isn't perfectly clear.")
        }

        parts.append("")
        parts.append("STYLE REMINDER (must follow):")
        parts.append(styleText)

        return parts.joined(separator: "\n")
    }
    
    /// Extracts the key visual scene from a memory - identifies the most important moment and describes it visually
    /// Trusts the LLM to be smart about condensing long memories or using them fully
    private func extractVisualScene(memory rawText: String, characterContext: String = "") async throws -> String {
        // Build character guidance if provided
        let characterGuidance: String
        if !characterContext.isEmpty {
            characterGuidance = """
            
            CHARACTER INFORMATION PROVIDED:
            \(characterContext)
            
            Use the exact physical descriptions provided above for each character when describing the scene.
            """
        } else {
            characterGuidance = ""
        }
        
        // Extract first character name (they are the narrator)
        let narratorName: String? = {
            // Parse "SCENE CHARACTERS: Name1 - ...; Name2 - ..."
            if characterContext.hasPrefix("SCENE CHARACTERS:") {
                let afterPrefix = characterContext.dropFirst("SCENE CHARACTERS:".count).trimmingCharacters(in: .whitespaces)
                if let dashIndex = afterPrefix.firstIndex(of: "-") {
                    return String(afterPrefix[..<dashIndex]).trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }()
        
        let narratorGuidance: String
        if let name = narratorName {
            narratorGuidance = """
            
            NARRATOR IDENTITY: The first character listed (\(name)) IS the narrator/main character telling this story.
            - When the memory says "I", "me", or "my", that refers to \(name).
            - DO NOT say "the narrator and \(name)" - they are the SAME person.
            - Use \(name)'s name directly instead of "the narrator".
            """
        } else {
            narratorGuidance = ""
        }
        
        let systemPrompt = """
        You are a visual scene extractor. Extract the key visual moment from this memory.
        
        CRITICAL RULES:
        1. **ACCURACY IS PARAMOUNT**: The number of people must match EXACTLY.
           - Example: "Me and 4 roommates" = 5 people total.
           - IMPORTANT: The narrator IS one of the named characters (usually the first one). Do NOT count them twice.
           - If the narrator is "Melody" and the memory says "I and Caleb", that's 2 people (Melody + Caleb), NOT 3.
        2. **Identify the Key Scene**: Pick the most important visual moment.
        3. **Keep it Simple but Complete**: Describe the setting, who is there, and what they are doing.
        4. **No Redundant Descriptions**: Do not describe physical appearance (hair, skin, etc.) as that is handled separately. Just use names.
        5. **Direct Style**: Use simple, factual sentences.
        6. **Body Position Accuracy**: Preserve the EXACT body positions described in the memory (sitting, standing, laying, kneeling, running, etc.). If the memory says "sitting", the scene MUST describe them sitting. If "laying down", they MUST be laying down. Never change or omit described postures.
        \(narratorGuidance)
        \(characterGuidance)
        
        Output: One paragraph describing the scene action and participants accurately.
        """
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": rawText]
            ],
            "temperature": 0.1 // Low temperature - keep it minimal and factual
        ]
        
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🎨 Extracting visual scene from memory...")
        let startedAt = Date()
        let (data, response) = try await URLSession.shared.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        
        struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
        struct Root: Decodable { let choices: [Choice] }
        
        let sceneDescription = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content ?? rawText
        print("📝 Visual scene → \(sceneDescription)")
        await logOpenAIChatTelemetry(
            model: "gpt-4o-mini",
            promptChars: rawText.count,
            responseData: data,
            statusCode: statusCode,
            success: true,
            startedAt: startedAt
        )
        return sceneDescription
    }

    /// One memory’s storybook pipeline result (parallel generation merges by `index`).
    private struct StorybookMemoryPipelineOutcome {
        let index: Int
        let generatedImage: UIImage?
        let skipped: SkippedStoryImageMemory?
        let appendedPageItems: [PageItem]
    }

    /// Bounded concurrent memories during storybook generation (OpenAI + Gemini). Higher values increase 429/OOM risk.
    private static let storybookMemoryParallelism = 3

    /// Runs the same per-memory steps as the original sequential loop; must be called from `MainActor`.
    private func runStorybookMemoryPipeline(
        index idx: Int,
        entry: MemoryEntry,
        sortedEntriesCount: Int,
        totalMemories: Int,
        artStyleForGeneration: ArtStyle,
        customArtStyleTextSnapshot: String,
        subjectPhotoSnapshot: UIImage?
    ) async throws -> StorybookMemoryPipelineOutcome {
        guard let entryID = entry.id else {
            return StorybookMemoryPipelineOutcome(index: idx, generatedImage: nil, skipped: nil, appendedPageItems: [])
        }
        let raw = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            return StorybookMemoryPipelineOutcome(index: idx, generatedImage: nil, skipped: nil, appendedPageItems: [])
        }

        StorybookGenLog.fence("MEMORY PIPELINE (on-device) \(idx + 1)/\(sortedEntriesCount) id=\(entryID.uuidString.prefix(8))…")
        StorybookGenLog.verboseLine("artStyle=\(artStyleForGeneration.rawValue) customStyleLen=\(customArtStyleTextSnapshot.count) hasProfilePhoto=\(subjectPhotoSnapshot != nil)")
        StorybookGenLog.verboseLine("memoryText (\(raw.count) chars): \(String(raw.prefix(500)))\(raw.count > 500 ? "…" : "")")

        let characterContextForExtraction = buildCharacterContext(for: entry)
        StorybookGenLog.verboseLine("characterContextForExtraction (\(characterContextForExtraction.count) chars): \(characterContextForExtraction)")
        let sceneDescription: String
        if let s1 = try? await extractVisualScene(memory: raw, characterContext: characterContextForExtraction) {
            sceneDescription = s1
        } else {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let s2 = try? await extractVisualScene(memory: raw, characterContext: characterContextForExtraction) {
                sceneDescription = s2
            } else {
                let label = memoryDisplayLabel(for: entry, fallbackOrdinal: idx + 1)
                let skipped = SkippedStoryImageMemory(
                    id: entryID,
                    memoryLabel: label,
                    detail: "Couldn’t read this memory’s visual scene. Try again in a moment."
                )
                return StorybookMemoryPipelineOutcome(index: idx, generatedImage: nil, skipped: skipped, appendedPageItems: [])
            }
        }
        let extracted = await extractTitleAndCharacters(from: raw, characterContext: characterContextForExtraction)
        StorybookGenLog.verboseLine("extractTitleAndCharacters → title=\"\(extracted.title)\" featuring=\"\(extracted.featuring)\"")

        let narratorDecision = inferNarratorPresence(memoryText: raw, entry: entry)
        let narratorPresence = narratorDecision.presence
        print("🧭 Narrator presence classification: \(narratorPresence.rawValue) [score: \(narratorDecision.confidenceScore), reason: \(narratorDecision.reason)]")
        let includeNarrator = narratorPresence.shouldAttachHeadshot
        if narratorDecision.firstPersonDetected {
            print("🧷 Narrator reference trigger: first-person cues detected; score = \(narratorDecision.confidenceScore); headshot attachment enabled = \(includeNarrator)")
        } else {
            print("🧷 Narrator reference trigger: \(narratorDecision.reason); score = \(narratorDecision.confidenceScore); headshot attachment enabled = \(includeNarrator)")
        }

        let characterList = buildCharacterList(
            for: entry,
            sceneDescription: sceneDescription,
            includeNarrator: includeNarrator
        )
        StorybookGenLog.verboseLine("characterList (\(characterList.count) chars):\n\(characterList)")

        let assembledPrompt = assembleFinalPrompt(
            memoryText: raw,
            characters: characterList,
            narratorPresence: narratorPresence,
            sceneDescription: sceneDescription,
            style: artStyleForGeneration,
            customStyle: customArtStyleTextSnapshot,
            hasHeadshot: subjectPhotoSnapshot != nil
        )

        print("🖼️ ASSEMBLED PROMPT (\(assembledPrompt.count) chars) ►", assembledPrompt)
        StorybookGenLog.line("ASSEMBLED_PROMPT length=\(assembledPrompt.count) (see line above: 🖼️ ASSEMBLED PROMPT)")

        print("🔍 Attempting image generation with Gemini only (no fallback)...")
        let headshotReferences: [UIImage] = includeNarrator ? (subjectPhotoSnapshot.map { [$0] } ?? []) : []
        let styleReferenceImage = loadSelectedStyleReferenceIfNeeded(lockedArtStyle: artStyleForGeneration)
        var referenceImages = headshotReferences
        if let styleReferenceImage {
            referenceImages.append(styleReferenceImage.image)
        }
        print("🖌️ Style reference profile selected: \(styleReferenceProfile.rawValue)")
        print("🖼️ Headshot attachment count for generation: \(headshotReferences.count)")
        print("🖼️ Style reference file for generation: \(styleReferenceImage?.filename ?? "none")")
        print("🖼️ Style reference attachment count for generation: \(styleReferenceImage == nil ? 0 : 1)")
        print("🖼️ Total reference attachment count for generation: \(referenceImages.count)")
        let geminiSize = artStyleForGeneration == .kidsBook ? "4:3" : "1792x1024"
        var geminiImageErrorDescription: String?
        let img: UIImage?
        do {
            img = try await generateImageWithGemini(
                assembledPrompt,
                size: geminiSize,
                referenceImages: referenceImages
            )
        } catch {
            geminiImageErrorDescription = error.localizedDescription
            print("⚠️ Gemini image generation threw for memory \(idx + 1) of \(sortedEntriesCount): \(error.localizedDescription)")
            img = nil
        }

        guard let img else {
            let label = memoryDisplayLabel(for: entry, fallbackOrdinal: idx + 1)
            let detail: String
            if let geminiImageErrorDescription {
                detail = geminiImageErrorDescription
            } else if geminiImageSvc == nil {
                detail = "Image generation is not configured (missing Gemini API key or service)."
            } else {
                detail = "The illustration request did not return an image. Try generating the storybook again."
            }
            let skipped = SkippedStoryImageMemory(id: entryID, memoryLabel: label, detail: detail)
            print("⏭️ Skipping memory \(idx + 1) (no image); continuing with remaining memories.")
            return StorybookMemoryPipelineOutcome(index: idx, generatedImage: nil, skipped: skipped, appendedPageItems: [])
        }

        let isKids = artStyleForGeneration == .kidsBook
        let exportHeight: CGFloat = isKids ? 612 : 792
        let exportWidth: CGFloat = isKids ? 792 : 612
        let memoryPrompt = entry.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let questionDriven = isQuestionDrivenMemory(entry)
        let displayTitle = questionDriven ? (memoryPrompt?.isEmpty == false ? memoryPrompt : extracted.title) : extracted.title
        let displaySubtitle = questionDriven ? extracted.title : nil

        let textPages = paginateText(
            raw,
            title: displayTitle,
            subtitle: displaySubtitle,
            pageHeight: exportHeight,
            pageWidth: exportWidth,
            memoryID: entryID
        )
        var newPages: [PageItem] = textPages

        let llmBarTitle = extracted.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let illustrationBarTitle = llmBarTitle.isEmpty ? displayTitle : llmBarTitle
        newPages.append(.illustration(image: img, memoryID: entryID, title: illustrationBarTitle))

        return StorybookMemoryPipelineOutcome(index: idx, generatedImage: img, skipped: nil, appendedPageItems: newPages)
    }

    /// A temporary struct to hold a memory and its inferred chronological age.
    private struct ChronologicalMemory {
        let entry: MemoryEntry
        let age: Int
    }

    private struct TitleAndCharacters: Codable {
        let title: String
        let featuring: String
    }

    private func extractTitleAndCharacters(from memoryText: String, characterContext: String) async -> TitleAndCharacters {
        let systemPrompt = """
        You are a book editor. Your job is to create a title and a 'featuring' list for a memory.
        
        1. Title: Create a short, engaging title (max 5 words).
        2. Featuring: List the people in the memory. Format: "Feat: [List]".
           - Use "me" for the narrator.
           - Use first names if known.
           - If names are unknown, count them (e.g., "2 friends", "my mom").
           - Format example: "Feat: me, Robbie, and 2 friends" or "Feat: me and my mom".
           - Keep it concise.
        
        Return ONLY JSON: { "title": "...", "featuring": "..." }
        """
        
        let prompt = """
        Memory: \(memoryText)
        
        Known Characters: \(characterContext)
        
        Extract title and featuring list.
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 100,
            "response_format": ["type": "json_object"]
        ]

        do {
            let startedAt = Date()
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            
            struct Response: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String }
                    let message: Message
                }
                let choices: [Choice]
            }
            
            let decodedResponse = try JSONDecoder().decode(Response.self, from: data)
            if let content = decodedResponse.choices.first?.message.content,
               let jsonData = content.data(using: .utf8),
               let result = try? JSONDecoder().decode(TitleAndCharacters.self, from: jsonData) {
                await logOpenAIChatTelemetry(
                    model: "gpt-4o-mini",
                    promptChars: prompt.count,
                    responseData: data,
                    statusCode: statusCode,
                    success: true,
                    startedAt: startedAt
                )
                return result
            }
        } catch {
            print("⚠️ Failed to extract title/characters: \(error)")
        }
        
        return TitleAndCharacters(title: "A Special Memory", featuring: "")
    }

    private func explicitAge(from memoryText: String) -> Int? {
        let lower = memoryText.lowercased()
        let patterns = [
            #"\b(?:i was|when i was|at age|age|turned|turning)\s+(\d{1,2})\b"#,
            #"\b(\d{1,2})\s*(?:years old|year old|yrs old)\b"#
        ]
        for pattern in patterns {
            if let range = lower.range(of: pattern, options: .regularExpression) {
                let match = String(lower[range])
                if let number = match.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .compactMap({ Int($0) })
                    .first,
                   (1...110).contains(number) {
                    return number
                }
            }
        }

        let wordAges: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20
        ]
        let wordPattern = #"\b(?:i was|when i was|at age|age|turned|turning)\s+([a-z\-]+)\b"#
        if let range = lower.range(of: wordPattern, options: .regularExpression) {
            let match = String(lower[range]).replacingOccurrences(of: "-", with: " ")
            for (word, value) in wordAges where match.contains(word) {
                return value
            }
        }
        return nil
    }

    private func heuristicAgeFromLifeStage(memoryText: String) -> Int? {
        let lower = memoryText.lowercased()

        if lower.contains("kindergarten") { return 5 }
        if lower.contains("elementary school") || lower.contains("primary school") { return 9 }
        if lower.contains("middle school") || lower.contains("junior high") { return 12 }
        if lower.contains("high school") || lower.contains("freshman year") || lower.contains("sophomore year") || lower.contains("junior year") || lower.contains("senior year") { return 16 }
        if lower.contains("learned to drive") || lower.contains("learning to drive") || lower.contains("driver's license") || lower.contains("driving test") { return 16 }
        if lower.contains("college") || lower.contains("university") || lower.contains("graduated college") { return 22 }
        if lower.contains("first job") || lower.contains("my first job") || lower.contains("growing up") { return 18 }
        if lower.contains("got married") || lower.contains("our wedding") || lower.contains("married") { return 28 }
        if lower.contains("first child") || lower.contains("my daughter was born") || lower.contains("my son was born") { return 30 }
        if lower.contains("first grandchild") || lower.contains("grandchild was born") || lower.contains("became a grandparent") { return 56 }
        if lower.contains("retired") || lower.contains("retirement") { return 66 }

        return nil
    }

    /// Uses deterministic + LLM + heuristic inference to extract user's age from memory text.
    private func extractAge(from memoryText: String) async -> Int? {
        if let explicit = explicitAge(from: memoryText) {
            print("🧠 Age inference source: regex -> \(explicit)")
            return explicit
        }

        let systemPrompt = """
        You are a data extraction expert. Your task is to read a user's memory and determine the user's age at the time of the event.
        - Look for explicit mentions of age like "I was 13", "when I turned ten", "at age seven".
        - If no age is explicitly mentioned, infer a plausible age based on context and life-stage cues.
        - You MUST respond with ONLY a single integer number and nothing else. For example: 13.
        - If you cannot determine an age with reasonable confidence, respond with 999.
        """
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": memoryText]
            ],
            "temperature": 0.0,
            "max_tokens": 5
        ]
        
        do {
            let startedAt = Date()
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: req)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            
            struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
            struct Root: Decodable { let choices: [Choice] }
            
            if let responseText = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content {
                let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                let age = Int(trimmed)
                    ?? trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }.first
                if let age, (1...110).contains(age), age != 999 {
                    print("🧠 Age inference source: llm -> \(age)")
                    await logOpenAIChatTelemetry(
                        model: "gpt-4o-mini",
                        promptChars: memoryText.count,
                        responseData: data,
                        statusCode: statusCode,
                        success: true,
                        startedAt: startedAt
                    )
                    return age
                }
                print("⚠️ Age LLM returned low-confidence/unknown value '\(trimmed)'; trying heuristic fallback.")
            }

            if let heuristic = heuristicAgeFromLifeStage(memoryText: memoryText) {
                print("🧠 Age inference source: heuristic -> \(heuristic)")
                await logOpenAIChatTelemetry(
                    model: "gpt-4o-mini",
                    promptChars: memoryText.count,
                    responseData: data,
                    statusCode: statusCode,
                    success: true,
                    startedAt: startedAt
                )
                return heuristic
            }
        } catch {
            print("🚫 Age extraction failed:", error.localizedDescription)
        }
        
        // Caller logs per-memory context; avoid spamming "fallback_999" for every unknown age.
        return 999
    }

    private var storybookGenerationCounter: UInt64 = 0

    /// How many full illustrated pages are in the current in-memory book (replaces the legacy `images` array for allowance accounting).
    var storybookGeneratedIllustrationCount: Int {
        pageItems.reduce(0) { n, p in
            if case .illustration = p { return n + 1 }
            return n
        }
    }

    // MARK: - In-progress generation persistence (resume / kill)

    private func buildPersistableStorybookForInProgress(
        profileID: UUID,
        createdAt: Date
    ) -> PersistableStorybook? {
        guard !pageItems.isEmpty else { return nil }
        let policy = CoverCopyPolicy(artStyle: currentArtStyle, profileDisplayName: profileName ?? "")
        var titleStored = bookDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if titleStored.isEmpty { titleStored = policy.defaultBookTitle() }
        let pitchRaw = backCoverPitch.trimmingCharacters(in: .whitespacesAndNewlines)
        let pitchStored = pitchRaw.isEmpty ? policy.fallbackBackCoverPitch(bookTitle: titleStored) : backCoverPitch
        let presetStored = coverFontPreset.isEmpty ? policy.coverFontPreset().rawValue : coverFontPreset
        return PersistableStorybook(
            profileID: profileID,
            pageItems: persistablePageItemsFromCurrentState(),
            artStyle: artStyleRaw,
            createdAt: createdAt,
            bookDisplayTitle: titleStored,
            backCoverPitch: pitchStored,
            coverFontPreset: presetStored
        )
    }

    private func mergeGenerationMarkerFromChunkOutcomes(
        marker: inout GenerationProgressMarker,
        chunkOutcomes: [StorybookMemoryPipelineOutcome]
    ) {
        for o in chunkOutcomes {
            if let skipped = o.skipped, !marker.skippedMemoryIDs.contains(skipped.id) {
                marker.skippedMemoryIDs.append(skipped.id)
            }
            if o.generatedImage != nil, o.skipped == nil {
                let list = o.appendedPageItems
                for item in list {
                    if case .illustration(_, let mid, _) = item {
                        if !marker.completedMemoryIDs.contains(mid) {
                            marker.completedMemoryIDs.append(mid)
                        }
                    }
                }
            }
        }
        marker.lastHeartbeatAt = Date()
    }

    private func flushInProgressBookToDisk(profileID: UUID, bookVersionId: String, createdAt: Date, marker: inout GenerationProgressMarker) {
        autoreleasepool {
            guard let data = buildPersistableStorybookForInProgress(profileID: profileID, createdAt: createdAt) else { return }
            do {
                var encoded = try JSONEncoder().encode(data)
                _ = try StorybookLocalStore.writeCurrentBook(data: encoded, profileID: profileID)
            } catch {
                print("❌ flushInProgressBookToDisk: \(error.localizedDescription)")
            }
        }
        marker.lastHeartbeatAt = Date()
        marker.save()
    }

    private func emergencyFlushInProgressGenerationToDisk() {
        guard let profileID = currentProfileID, let b = lastSyncedBookVersionId, let c = lastPersistedBookCreatedAt, !pageItems.isEmpty,
              var marker = GenerationProgressMarker.load(for: profileID), marker.bookVersionId == b else { return }
        marker.phase = .finalizing
        print("⚠️ [Storybook] background task expiring — emergency flush; pages=\(pageItems.count)")
        flushInProgressBookToDisk(profileID: profileID, bookVersionId: b, createdAt: c, marker: &marker)
    }

    /// Returns `true` when a resume was started; caller should set `hasRequestedGeneration` and skip an immediate full `loadStorybookForProfile`.
    func resumeInProgressGenerationIfMarkerExists(
        profileID: UUID,
        profileName: String?,
        profileEthnicity: String?
    ) async -> Bool {
        if let job = try? await FirestoreSyncService.shared.fetchLatestActiveStorybookJob(profileId: profileID) {
            await attachToCloudStorybookJob(
                jobId: job.jobId,
                profileID: profileID,
                profileName: profileName,
                profileEthnicity: profileEthnicity
            )
            return true
        }
        if GenerationProgressMarker.load(for: profileID) != nil {
            GenerationProgressMarker.clear(for: profileID)
        }
        return false
    }

    // MARK: - Cloud storybook generation (Firestore job + worker)

    private func stopStorybookCloudJobListener() {
        storybookCloudJobListener?.remove()
        storybookCloudJobListener = nil
        cloudStorybookFinalizeStarted = false
    }

    /// Dumps every entry from the `memoryFailures` map written by the cloud
    /// worker into the device console (so we can copy/paste exact reasons when
    /// debugging) and returns the most-common reason as a short user-readable
    /// string for the error banner.
    ///
    /// Returns `nil` when the doc has no `memoryFailures` map yet — in that
    /// case the existing `error` string from the cloud is enough.
    static func logAndSummariseMemoryFailures(data: [String: Any], jobId: String) -> String? {
        guard let failures = data["memoryFailures"] as? [String: [String: Any]],
              !failures.isEmpty else {
            return nil
        }
        print("🩺 [storybookJob \(jobId)] memoryFailures count=\(failures.count)")
        var reasonCounts: [String: Int] = [:]
        for (memoryId, info) in failures {
            let stage = (info["stage"] as? String) ?? "unknown"
            let message = (info["message"] as? String) ?? "no message"
            let http = info["httpStatus"]
            let finishReason = info["geminiFinishReason"]
            let blockReason = info["geminiBlockReason"]
            let textResponse = info["geminiTextResponse"]
            let noImage = info["noImageBytes"]
            print("🩺   memory=\(memoryId.prefix(8))… stage=\(stage) http=\(String(describing: http)) finishReason=\(String(describing: finishReason)) blockReason=\(String(describing: blockReason)) noImageBytes=\(String(describing: noImage)) textResponse=\(String(describing: textResponse))")
            print("🩺     message: \(message)")
            let key = "[\(stage)] \(message)"
            reasonCounts[key, default: 0] += 1
        }
        guard let top = reasonCounts.sorted(by: { $0.value > $1.value }).first else {
            return nil
        }
        if reasonCounts.count == 1 {
            return "Reason: \(top.key)"
        }
        return "Most common reason (\(top.value)/\(failures.count)): \(top.key)"
    }

    private func memoryPlainText(_ entry: MemoryEntry) -> String {
        entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func rebuildPageItemsFromCloudJobData(_ data: [String: Any], profileID: UUID) async throws {
        let ordered = (data["orderedMemoryIds"] as? [String]) ?? []
        let results = (data["memoryResults"] as? [String: [String: Any]]) ?? [:]
        let skippedStrings = (data["skippedMemoryIds"] as? [String]) ?? []
        var skipped: [SkippedStoryImageMemory] = []
        for s in skippedStrings {
            guard let u = UUID(uuidString: s) else { continue }
            skipped.append(SkippedStoryImageMemory(id: u, memoryLabel: "Memory", detail: "Skipped during cloud generation."))
        }
        skippedMemoriesDuringGeneration = skipped

        let isKids = currentArtStyle == .kidsBook
        let exportHeight: CGFloat = isKids ? 612 : 792
        let exportWidth: CGFloat = isKids ? 792 : 612

        var newPages: [PageItem] = []
        let pool = try await fetchMemoryEntries(for: profileID)
        var byId: [UUID: MemoryEntry] = [:]
        for e in pool { if let mid = e.id { byId[mid] = e } }

        for midString in ordered {
            guard let mid = UUID(uuidString: midString),
                  let res = results[midString],
                  let entry = byId[mid] else { continue }
            let raw = memoryPlainText(entry)
            guard !raw.isEmpty else { continue }
            guard let urlStr = res["illustrationURL"] as? String,
                  let u = URL(string: urlStr) else { continue }
            let (imgData, _) = try await URLSession.shared.data(from: u)
            guard let img = UIImage(data: imgData) else { continue }

            let displayTitle = (res["displayTitle"] as? String) ?? (entry.prompt ?? "Memory")
            let displaySubtitle = res["displaySubtitle"] as? String
            let illustrationBarTitle = (res["illustrationBarTitle"] as? String) ?? displayTitle

            let textPages = paginateText(
                raw,
                title: displayTitle,
                subtitle: displaySubtitle,
                pageHeight: exportHeight,
                pageWidth: exportWidth,
                memoryID: mid
            )
            newPages.append(contentsOf: textPages)
            newPages.append(.illustration(image: img, memoryID: mid, title: illustrationBarTitle))
        }
        pageItems = newPages
    }

    private func startStorybookCloudJobListener(jobId: String, profileID: UUID, thisRun: UInt64) {
        stopStorybookCloudJobListener()
        cloudStorybookFinalizeStarted = false
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("storybookJobs").document(jobId)
        storybookCloudJobListener = ref.addSnapshotListener { [weak self] snap, err in
            guard let self, err == nil, let snap, snap.exists else { return }
            Task { @MainActor in
                guard thisRun == self.storybookGenerationCounter else { return }
                let data = snap.data() ?? [:]
                await self.handleStorybookCloudJobSnapshot(data: data, jobId: jobId, profileID: profileID, thisRun: thisRun)
            }
        }
    }

    private func handleStorybookCloudJobSnapshot(data: [String: Any], jobId: String, profileID: UUID, thisRun: UInt64) async {
        let status = String(describing: data["status"] ?? "")
        let prog = data["progress"] as? [String: Any] ?? [:]
        let completed = (prog["completedMemoryCount"] as? NSNumber)?.intValue ?? (prog["completedMemoryCount"] as? Int) ?? 0
        let total = (prog["totalMemories"] as? NSNumber)?.intValue ?? (prog["totalMemories"] as? Int) ?? 0
        if total > 0 {
            totalMemories = total
            currentMemoryIndex = min(completed, total)
            progress = Double(completed) / Double(total)
        }
        if let cs = prog["currentStatus"] as? String, !cs.isEmpty {
            currentStatus = cs
        } else {
            switch status {
            case "queued": currentStatus = "Queued for cloud generation…"
            case "ranking": currentStatus = "Selecting best memories…"
            case "running": currentStatus = "Generating illustrations in the cloud…"
            case "aiComplete": currentStatus = "Finalizing your book…"
            case "failed": currentStatus = "Generation failed"
            default: break
            }
        }

        if status == "failed" {
            let baseError = String(describing: data["error"] ?? "Unknown error")
            // Dump every per-memory failure to the console so we never have to
            // guess what went wrong — and append the top reason (if any) to the
            // user-visible message.
            let topReason = Self.logAndSummariseMemoryFailures(data: data, jobId: jobId)
            if let topReason {
                errorMessage = "\(baseError)\n\n\(topReason)"
            } else {
                errorMessage = baseError
            }
            stopStorybookCloudJobListener()
            isLoading = false
            isFinalizingAssets = false
            return
        }

        if status == "running" || status == "ranking" || status == "queued" {
            try? await rebuildPageItemsFromCloudJobData(data, profileID: profileID)
            hasGeneratedStorybook = !pageItems.isEmpty
            return
        }

        if status == "aiComplete" {
            if cloudStorybookFinalizeStarted { return }
            cloudStorybookFinalizeStarted = true
            guard let reservedAt = lastPersistedBookCreatedAt else { return }
            await runFinalizeAfterCloudAI(jobId: jobId, profileID: profileID, jobData: data, reservedCreatedAt: reservedAt, thisRun: thisRun)
        }
    }

    private func runFinalizeAfterCloudAI(jobId: String, profileID: UUID, jobData: [String: Any], reservedCreatedAt: Date, thisRun: UInt64) async {
        do {
            currentStatus = "Finalizing your book…"
            isFinalizingAssets = true
            let cloudPitch = jobData["backCoverPitch"] as? String
            try await rebuildPageItemsFromCloudJobData(jobData, profileID: profileID)
            guard !pageItems.isEmpty else {
                // The cloud job claims `aiComplete` but produced no usable
                // illustrations.  Mark the job as `failed` in Firestore so the
                // aggressive auto-route in `ContentView` doesn't keep
                // re-attaching us to this same broken document and looping.
                Task.detached { [jobId] in
                    try? await FirestoreSyncService.shared.markStorybookJobFailed(
                        jobId: jobId,
                        reason: "Image generation failed for every memory. Please try again."
                    )
                }
                stopStorybookCloudJobListener()
                GenerationProgressMarker.clear(for: profileID)
                throw NSError(
                    domain: "MemoirAI",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Image generation failed. Please tap “Try Creating Again”."]
                )
            }
            await preparePrintPackagingBeforePersist(existingBackCoverPitchFromCloud: cloudPitch)
            persistStorybook(for: profileID, reservedCreatedAt: reservedCreatedAt, reservedBookVersionId: jobId)
            currentStatus = "Finalizing cover and print assets…"
            if let bookVersionId = lastSyncedBookVersionId {
                let readinessTimeout = Self.canonicalReadinessBudgetSeconds(pageCount: pageItems.count)
                let ready = await waitForCanonicalBookReadiness(bookVersionId: bookVersionId, timeoutSeconds: readinessTimeout)
                if !ready {
                    isVisualBookReady = !pageItems.isEmpty
                }
            }
            if let bookId = lastSyncedBookVersionId {
                let pollBudget = Self.canonicalReadinessBudgetSeconds(pageCount: pageItems.count)
                await installFreshBookVersionRecordAfterGeneration(bookVersionId: bookId, pollBudgetSeconds: pollBudget)
            }
            if let bookId = lastSyncedBookVersionId, thisRun == storybookGenerationCounter {
                scheduleBackgroundCoverBackfillIfNeeded(bookVersionId: bookId)
            }
            try await FirestoreSyncService.shared.markStorybookJobComplete(jobId: jobId)
            stopStorybookCloudJobListener()
            if thisRun == storybookGenerationCounter {
                GenerationProgressMarker.clear(for: profileID)
            }
        } catch {
            errorMessage = error.localizedDescription
            cloudStorybookFinalizeStarted = false
        }
        isFinalizingAssets = false
        isLoading = false
        isVisualBookReady = !pageItems.isEmpty
        requiresVisualReadyGate = false
    }

    /// Force-syncs every Core Data memory the cloud worker is going to look
    /// for to Firestore.  Runs in parallel with a small concurrency cap so we
    /// don't blow up the network with hundreds of writes at once.
    ///
    /// `setData(merge: true)` makes this idempotent — already-synced memories
    /// just get a `syncedAt` bump.  We use the same `profileName` that gets
    /// written to the storybookJob doc so the cloud function always sees a
    /// consistent label.
    private func ensureMemoriesSyncedToCloud(entries: [MemoryEntry], profileID: UUID) async {
        guard !entries.isEmpty else { return }
        let profileName = self.profileName

        let preflightStart = Date()
        print("☁️ [storybookKickoff] preflight syncing \(entries.count) memories to Firestore for profile=\(profileID.uuidString.prefix(8))…")

        await withTaskGroup(of: Void.self) { group in
            let maxConcurrent = 6
            var inFlight = 0
            for entry in entries {
                if inFlight >= maxConcurrent {
                    await group.next()
                    inFlight -= 1
                }
                group.addTask {
                    await FirestoreSyncService.shared.syncMemory(entry, profileName: profileName)
                }
                inFlight += 1
            }
            await group.waitForAll()
        }

        let elapsed = String(format: "%.1f", Date().timeIntervalSince(preflightStart))
        print("☁️ [storybookKickoff] preflight sync complete in \(elapsed)s")
    }

    private func kickoffCloudStorybookGeneration(
        profileID: UUID,
        profileEthnicity: String?,
        artStyleForGeneration: ArtStyle,
        targetPageCount: Int,
        thisRun: UInt64
    ) async throws {
        stopStorybookCloudJobListener()
        currentStatus = "Uploading subject photo…"
        let photoPath = try await FirestoreSyncService.shared.uploadSubjectPhotoIfNeeded(subjectPhoto, profileId: profileID)

        currentStatus = "Starting cloud generation…"
        let entries = try await fetchMemoryEntries(for: profileID)
        guard !entries.isEmpty else {
            throw NSError(domain: "MemoirAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "No memories available to generate."])
        }
        StorybookGenLog.fence("CLOUD STORYBOOK KICKOFF (iOS)")
        StorybookGenLog.line("Illustration prompts for interior pages run in **Cloud Functions** (`processStorybookJob`), not in the app. Filter device logs for [StorybookGen] here, and Firebase/Cloud Logging for `storybook.*` / `storybook.assembledPreview` on the worker.")
        StorybookGenLog.line("Local memory candidates: count=\(entries.count) (worker will rank + order by age; may use fewer than pageCountTarget).")
        for (i, e) in entries.enumerated() {
            let idStr = e.id?.uuidString ?? "nil"
            let raw = e.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let promptLine = (e.prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ch = (e.value(forKey: "characterDetails") as? String) ?? ""
            StorybookGenLog.verboseLine("  [\(i + 1)] id=\(idStr.prefix(8))… textLen=\(raw.count) prompt=\"\(String(promptLine.prefix(80)))\(promptLine.count > 80 ? "…" : "")\"")
            StorybookGenLog.verboseLine("      memory text head: \(String(raw.prefix(320)))\(raw.count > 320 ? "…" : "")")
            if !ch.isEmpty {
                StorybookGenLog.verboseLine("      characterDetails head: \(String(ch.prefix(400)))\(ch.count > 400 ? "…" : "")")
            }
        }
        self.profileName = resolvedNarratorDisplayName(profileName: self.profileName, from: entries)

        // Make sure every memory we want the cloud to use is actually in
        // Firestore *before* the cloud worker reads them.  Memories rely on a
        // fire-and-forget queue (`queueMemorySyncWithProfile`) that can lag
        // when the app is killed, was offline, or the row was created before
        // sync existed.  `setData(merge:true)` makes this idempotent and cheap
        // for already-synced rows.  Failures here just log — the cloud worker
        // will surface a clear "no memories on cloud" error if uploads truly
        // failed.
        currentStatus = "Syncing memories to the cloud…"
        await ensureMemoriesSyncedToCloud(entries: entries, profileID: profileID)

        let reservedCreatedAt = Date()
        let reservedBookId = "\(profileID.uuidString)_\(Int(reservedCreatedAt.timeIntervalSince1970))"
        lastSyncedBookVersionId = reservedBookId
        lastPersistedBookCreatedAt = reservedCreatedAt

        if artStyleForGeneration == .kidsBook {
            _ = loadSelectedStyleReferenceIfNeeded(lockedArtStyle: artStyleForGeneration)
        }

        var job: [String: Any] = [
            "profileId": profileID.uuidString,
            "bookVersionId": reservedBookId,
            "artStyle": artStyleRaw,
            "pageCountTarget": targetPageCount,
            "profileName": self.profileName ?? "",
            "profileEthnicity": profileEthnicity ?? "",
            "customArtStyleText": customArtStyleText,
            "styleReferencePreset": styleReferencePresetRawValue,
            "gender": gender,
            "otherDetails": otherDetails,
            "faceDescription": faceDescription ?? "",
            "status": "queued",
            "clientVersion": 1,
            "region": "us-central1",
            "progress": [
                "completedMemoryCount": 0,
                "totalMemories": 0,
                "currentStatus": "Queued…"
            ] as [String: Any],
            "memoryResults": [:] as [String: Any],
            "skippedMemoryIds": [] as [String]
        ]
        if let photoPath {
            job["subjectPhotoStoragePath"] = photoPath
        }
        let photoSummary: String = {
            guard let p = photoPath, !p.isEmpty else { return "no" }
            return "yes path=\(p)"
        }()
        StorybookGenLog.line("Job written: bookVersionId (jobId)=\(reservedBookId) artStyle=\(artStyleRaw) pageCountTarget=\(targetPageCount) styleRef=\(styleReferencePresetRawValue) subjectPhoto=\(photoSummary)")
        StorybookGenLog.verboseLine("Job fields: profileName=\(self.profileName ?? "") ethnicity=\(profileEthnicity ?? "") gender=\(gender) customArtStyleLen=\(customArtStyleText.count) faceDescriptionLen=\(faceDescription?.count ?? 0) otherDetailsLen=\(otherDetails.count)")
        try await FirestoreSyncService.shared.writeStorybookCloudJob(jobId: reservedBookId, data: job)

        GenerationProgressMarker.clear(for: profileID)

        startStorybookCloudJobListener(jobId: reservedBookId, profileID: profileID, thisRun: thisRun)
        StorybookGenLog.line("Listener started for storybookJobs/\(reservedBookId.prefix(24))… — progress updates will follow from Firestore.")
        currentStatus = "Generating in the cloud — you can close the app and come back."
    }

    /// Resume an in-flight cloud job (cold launch / auto-route).
    func attachToCloudStorybookJob(jobId: String, profileID: UUID, profileName: String?, profileEthnicity: String?) async {
        stopStorybookCloudJobListener()
        currentProfileID = profileID
        if let profileName, !profileName.isEmpty { self.profileName = profileName }
        if ethnicity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let pe = profileEthnicity?.trimmingCharacters(in: .whitespacesAndNewlines), !pe.isEmpty {
            ethnicity = pe
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snap = try? await Firestore.firestore()
            .collection("users").document(uid)
            .collection("storybookJobs").document(jobId)
            .getDocument()
        if let ts = snap?.data()?["createdAt"] as? Timestamp {
            lastPersistedBookCreatedAt = ts.dateValue()
        } else {
            lastPersistedBookCreatedAt = Date()
        }
        lastSyncedBookVersionId = jobId
        isLoading = true
        isFinalizingAssets = false
        requiresVisualReadyGate = true
        isVisualBookReady = false
        errorMessage = nil
        let thisRun = storybookGenerationCounter
        startStorybookCloudJobListener(jobId: jobId, profileID: profileID, thisRun: thisRun)
        if let data = snap?.data() {
            await handleStorybookCloudJobSnapshot(data: data, jobId: jobId, profileID: profileID, thisRun: thisRun)
        }
    }

    func generateStorybook(forProfileID id: UUID, profileName name: String? = nil, overridePageCount: Int? = nil, profileEthnicity: String? = nil) async {
        currentProfileID = id // Set current profile
        if let name = name {
            self.profileName = name
        }
        if ethnicity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let pe = profileEthnicity?.trimmingCharacters(in: .whitespacesAndNewlines), !pe.isEmpty {
            ethnicity = pe
        }
        // NOTE: profileName should already be set from loadStorybookForProfile
        // Add warning to catch if it's nil
        if profileName == nil {
            print("⚠️ WARNING: profileName is nil during generation! Narrator detection may fail.")
        }
        isLoading = true
        isFinalizingAssets = false
        requiresVisualReadyGate = true
        isVisualBookReady = false
        errorMessage = nil
        progress = 0
        print("[StorybookLoad] generateStorybook START profile=\(id.uuidString.prefix(8)) — clearing in-memory book")
        pageItems.removeAll()
        precomposedIllustrationMemoryIDs = []
        illustrationReloadSources = [:]
        illustrationRetryInProgress = []
        skippedMemoriesDuringGeneration = []
        currentMemoryIndex = 0
        totalMemories = 0
        currentStatus = "Preparing..."
        // Clear stale book-identity state from any previously-loaded book so the
        // cover/title/pitch don't leak from the previous generation into the new view.
        // (Equivalent to clearCurrentStorybook() minus the on-disk delete.)
        currentBookVersionRecord = nil
        bookDisplayTitle = ""
        backCoverPitch = ""
        coverFontPreset = ""
        lastSyncedBookVersionId = nil
        lastPersistedBookCreatedAt = nil
        loadedBookOrientation = nil
        loadedBookPageWidth = nil
        loadedBookPageHeight = nil
        hasGeneratedStorybook = false
        cloudStorybookFinalizeStarted = false
        // Snapshot before any async work so concurrent cloud loads cannot overwrite `artStyleRaw` mid-generation.
        let artStyleForGeneration = currentArtStyle
        let thisRun: UInt64 = { storybookGenerationCounter += 1; return storybookGenerationCounter }()

        do {
            let targetPageCount = max(1, overridePageCount ?? pageCountSetting)
            try await kickoffCloudStorybookGeneration(
                profileID: id,
                profileEthnicity: profileEthnicity,
                artStyleForGeneration: artStyleForGeneration,
                targetPageCount: targetPageCount,
                thisRun: thisRun
            )
        } catch is CancellationError {
            errorMessage = nil
            isVisualBookReady = false
            isFinalizingAssets = false
            stopStorybookCloudJobListener()
            print("[StorybookLoad] generateStorybook cancelled (new run or Task.cancel)")
        } catch {
            if thisRun == storybookGenerationCounter {
                GenerationProgressMarker.clear(for: id)
            }
            stopStorybookCloudJobListener()
            if let nsError = error as? NSError, nsError.code == 429 {
                errorMessage = "Too many requests to OpenAI. Please wait a few minutes and try again."
                print("StoryPageViewModel ERROR: Rate limited (429)")
            } else {
                errorMessage = error.localizedDescription
                print("StoryPageViewModel ERROR:", error.localizedDescription)
            }
            isVisualBookReady = false
            isFinalizingAssets = false
        }

        if storybookCloudJobListener == nil {
            requiresVisualReadyGate = false
            isFinalizingAssets = false
            isLoading = false
        } else {
            requiresVisualReadyGate = false
        }
    }

    /// After generation, fill in a missing print cover in the background so the UI is not blocked on `coverURL`.
    private func scheduleBackgroundCoverBackfillIfNeeded(bookVersionId: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            print("[CoverFlow] coverBackfillTask START book=\(bookVersionId.prefix(24))…")
            // One shot: regenerate only when the doc exists but `coverURL` is still empty (do not repeat inside the poll loop).
            _ = await FirestoreSyncService.shared.ensureCoverDesignExistsIfMissing(
                bookVersionId: bookVersionId,
                respectSessionBudget: false
            )
            let maxAttempts = 30
            let delayNs: UInt64 = 2_000_000_000
            for attempt in 0..<maxAttempts {
                if let updated = await FirestoreSyncService.shared.fetchBookVersion(bookVersionId: bookVersionId) {
                    let hasPdf = updated.printCoverPDFURL != nil
                    if attempt == 0 || attempt == maxAttempts - 1 || hasPdf {
                        print("[CoverFlow] coverBackfill poll \(attempt + 1)/\(maxAttempts) hasPdf=\(hasPdf)")
                    }
                    await refreshBookVersionAfterCoverBackfill(updated: updated, bookVersionId: bookVersionId)
                    if hasPdf {
                        print("[CoverFlow] coverBackfillTask END (has print PDF)")
                        return
                    }
                }
                if attempt + 1 < maxAttempts {
                    try? await Task.sleep(nanoseconds: delayNs)
                }
            }
            print("[CoverFlow] coverBackfillTask EXHAUSTED")
        }
    }

    /// Polls Firestore until `printCoverPDFURL` resolves or `pollBudgetSeconds` elapses (aligned with canonical readiness timeout).
    private func installFreshBookVersionRecordAfterGeneration(
        bookVersionId: String,
        pollBudgetSeconds: TimeInterval
    ) async {
        let interval: TimeInterval = 1.5
        let maxAttempts = max(10, Int(ceil(pollBudgetSeconds / interval)) + 6)
        print("[CoverFlow] installFresh START book=\(bookVersionId.prefix(24))… maxAttempts=\(maxAttempts) budget=\(pollBudgetSeconds)s")
        for attempt in 0..<maxAttempts {
            if let fresh = await FirestoreSyncService.shared.fetchBookVersion(bookVersionId: bookVersionId) {
                currentBookVersionRecord = fresh
                let hasPdf = fresh.printCoverPDFURL != nil
                if attempt == 0 || attempt == maxAttempts - 1 || hasPdf {
                    print("[CoverFlow] installFresh poll \(attempt + 1)/\(maxAttempts) hasDoc=true hasPrintCoverPDF=\(hasPdf)")
                }
                if hasPdf {
                    enqueuePrefetchPrintCoverPanels(for: fresh)
                    print("[CoverFlow] installFresh END (print PDF ready)")
                    return
                }
            } else if attempt == 0 || attempt == maxAttempts - 1 {
                print("[CoverFlow] installFresh poll \(attempt + 1)/\(maxAttempts) hasDoc=false")
            }
            if attempt + 1 < maxAttempts {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
        print("[CoverFlow] installFresh EXHAUSTED (no printCoverPDFURL)")
    }

    /// Prefetches the front panel thumbnail from the flat print cover PDF (best effort, background).
    private func enqueuePrefetchPrintCoverPanels(for record: BookVersionRecord) {
        guard let coverURL = record.printCoverPDFURL else {
            print("[CoverFlow] prefetch SKIP (no printCoverPDFURL) book=\(record.bookVersionId.prefix(20))…")
            return
        }
        let layout = record.coverFlatLayoutKind
        let revision = record.coverThumbnailCacheRevision
        let cacheId = record.coverStoragePath ?? ""
        print("[CoverFlow] prefetch START book=\(record.bookVersionId.prefix(20))… layout=\(String(describing: layout)) revPrefix=\(String(revision.prefix(24)))…")
        Task {
            // Warm only the front panel on open; back loads lazily when the user reaches the closing page.
            let frontThumb = await CoverPDFThumbnailService.loadAndCache(
                url: coverURL,
                layout: layout,
                panel: .front,
                targetSize: CGSize(width: 1200, height: 900),
                cacheRevision: revision,
                cacheIdentity: cacheId
            )
            print("[CoverFlow] prefetch END frontOK=\(frontThumb != nil) (back panel lazy)")
        }
    }

    private func refreshBookVersionAfterCoverBackfill(updated: BookVersionRecord, bookVersionId: String) async {
        // Only update the record — do NOT call applyBookVersionRecord here, which would
        // trigger a full page rebuild and risk racing with the user's current view state.
        // currentBookVersionRecord is @Published, so StoryPageDetailView's printCoverPDFURL()
        // will re-evaluate automatically and show the AI cover.
        await MainActor.run { currentBookVersionRecord = updated }
        if updated.printCoverPDFURL != nil {
            print("[CoverFlow] refreshAfterCoverBackfill prefetch book=\(bookVersionId.prefix(20))…")
            enqueuePrefetchPrintCoverPanels(for: updated)
            // Notify any open gallery views so they can update the matching card.
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .bookCoverBackfillComplete,
                    object: nil,
                    userInfo: ["bookVersionId": bookVersionId, "record": updated]
                )
            }
        }
    }

    /// Firestore + Storage can lag behind local generation; keep poll budgets generous and aligned.
    private static func canonicalReadinessBudgetSeconds(pageCount: Int) -> TimeInterval {
        TimeInterval(min(180, max(95, 80 + pageCount * 4)))
    }

    private func waitForCanonicalBookReadiness(bookVersionId: String, timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let record = await FirestoreSyncService.shared.fetchBookVersion(bookVersionId: bookVersionId),
               canonicalVisualReadiness(for: record) {
                print("[CoverFlow] canonicalReadiness MET book=\(bookVersionId.prefix(20))… renderStatus=\(record.renderStatus)")
                await applyBookVersionRecord(record)
                enqueuePrefetchPrintCoverPanels(for: record)
                isVisualBookReady = true
                return true
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        return false
    }

    func fetchMemoryEntries(for profileID: UUID) async throws -> [MemoryEntry] {
        let ctx = PersistenceController.shared.container.viewContext
        // Capture the setting before entering the closure
        let sourceSetting = self.memorySourceSetting
        
        return try await ctx.perform {
            let req: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
            
            // Base predicate for profile + current Firebase user scope
            var predicates = [MemoryUserScope.profilePredicate(profileID: profileID)]
            
            // Filter by memory source setting
            switch sourceSetting {
            case "memoir":
                // Only memories with chapter (from guided memoir flow)
                predicates.append(NSPredicate(format: "chapter != nil"))
            case "recordings":
                // Only memories without chapter (from quick record)
                predicates.append(NSPredicate(format: "chapter == nil"))
            default:
                // "all" - no additional filter
                break
            }
            
            req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            return try ctx.fetch(req)
        }
    }

    private struct MemoryStub: Codable { let id: UUID; let summary: String; let chapter: String? }
    private struct ChatMessage: Encodable { let role: String; let content: String }
    private struct ChatCompletionRequest: Encodable {
        let model: String; let messages: [ChatMessage]
        let max_tokens: Int; let temperature: Double
    }

    private func rankMemoriesWithLLM(_ all: [MemoryEntry], top n: Int) async -> [MemoryEntry] {
        let requestedCount = max(1, n)
        guard requestedCount < all.count else { return all }
        let stubs = all.compactMap { mem -> MemoryStub? in
            guard let id = mem.id, let txt = mem.text?.trimmingCharacters(in: .whitespacesAndNewlines), !txt.isEmpty else { return nil }
            let words = txt.split(separator: " ")
            let summary = words.prefix(100).joined(separator: " ")
            return MemoryStub(id: id, summary: String(summary), chapter: mem.chapter)
        }
        guard let stubJSON = try? JSONEncoder().encode(stubs), let stubStr = String(data: stubJSON, encoding: .utf8) else {
            return Array(all.prefix(requestedCount))
        }
        let system = ChatMessage(role: "system", content: """
            You are a memoir editor selecting memories for a printed storybook. \
            Pick the \(requestedCount) most emotionally significant, vivid, and visually rich memories. \
            Prefer variety across different life chapters. Each memory includes a summary and optionally the chapter it belongs to.
            """)
        let user = ChatMessage(role: "user", content: "Return ONLY JSON { \"top\": [\"uuid1\",\"uuid2\"] }. \nMemories: \(stubStr)")
        let req = ChatCompletionRequest(model: "gpt-4o-mini", messages: [system, user], max_tokens: 512, temperature: 0)
        var urlReq = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        urlReq.httpMethod = "POST"
        urlReq.httpBody   = try? JSONEncoder().encode(req)
        urlReq.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        urlReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let startedAt = Date()
            let (data, response) = try await URLSession.shared.data(for: urlReq)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            await logOpenAIChatTelemetry(
                model: "gpt-4o-mini",
                promptChars: stubStr.count,
                responseData: data,
                statusCode: statusCode,
                success: true,
                startedAt: startedAt
            )
            
            guard let content = extractContent(from: data) else {
                print("⚠️ LLM ranking failed to extract content.")
                return Array(all.prefix(requestedCount))
            }
            
            guard let contentData = content.data(using: .utf8),
                  let idsDict = try? JSONDecoder().decode([String:[UUID]].self, from: contentData),
                  let ids = idsDict["top"] else {
                print("⚠️ LLM ranking failed to decode UUIDs from content: \(content)")
                return Array(all.prefix(requestedCount))
            }

            var normalizedIDs: [UUID] = []
            var seen = Set<UUID>()
            for id in ids where !seen.contains(id) {
                seen.insert(id)
                normalizedIDs.append(id)
                if normalizedIDs.count == requestedCount { break }
            }

            guard !normalizedIDs.isEmpty else {
                print("⚠️ LLM ranking returned no usable IDs.")
                return Array(all.prefix(requestedCount))
            }

            let idOrder = normalizedIDs.enumerated().reduce(into: [UUID: Int]()) { $0[$1.element] = $1.offset }
            return Array(
                all.filter { $0.id.map { idOrder[$0] != nil } ?? false }
                      .sorted {
                          guard let id1 = $0.id, let id2 = $1.id,
                                let order1 = idOrder[id1], let order2 = idOrder[id2] else { return false }
                          return order1 < order2
                      }
                      .prefix(requestedCount)
            )
        } catch {
            print("LLM ranking failed:", error.localizedDescription)
            return Array(all.prefix(requestedCount))
        }
    }
    
    private func extractContent(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let msgDict = choices.first?["message"] as? [String: Any],
              let content = msgDict["content"] as? String else {
            return nil
        }
        
        // COMPLETELY SAFE VERSION: Use string methods instead of dangerous indexing
        guard !content.isEmpty else { return content }
        
        // Find the first { and last } using safe string methods
        if let startIndex = content.firstIndex(of: "{"),
           let endIndex = content.lastIndex(of: "}"),
           startIndex < endIndex {
            
            // Use safe substring extraction
            let substring = content[startIndex...endIndex]
            return String(substring)
        }
        
        // If no JSON brackets found, return the original content
        return content
    }

    private func logOpenAIChatTelemetry(
        model: String,
        promptChars: Int,
        responseData: Data,
        statusCode: Int?,
        success: Bool,
        startedAt: Date
    ) async {
        let usage = DevCostTelemetryService.extractOpenAIUsage(from: responseData)
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .openAI,
                operation: .openAIChat,
                model: model,
                statusCode: statusCode,
                success: success,
                durationMs: Date().timeIntervalSince(startedAt) * 1000,
                promptCharacters: promptChars,
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                inputImageCount: 0,
                outputImageCount: 0,
                uploadedBytes: 0
            )
        )
    }
    
    // MARK: - Image Editing (smart context)
    
    /// Caps very long memory text for API payloads while favoring sentence boundaries.
    private func clampedMemoryTextForImageEdit(_ text: String, maxChars: Int = 2400) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        guard t.count > maxChars else { return t }
        let endIdx = t.index(t.startIndex, offsetBy: maxChars)
        let prefix = String(t[..<endIdx])
        if let range = prefix.range(of: ". ", options: .backwards) {
            return String(prefix[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines) + " …"
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + " …"
    }
    
    /// Deterministic scene grounding (no extra LLM call) — excerpt of memory for edit-time context.
    private func deterministicSceneSummaryForImageEdit(from memoryText: String) -> String {
        let t = memoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "(No memory text — use the input image and the user's revision.)" }
        let maxLen = 900
        if t.count <= maxLen { return t }
        let endIdx = t.index(t.startIndex, offsetBy: maxLen)
        let prefix = String(t[..<endIdx])
        if let range = prefix.range(of: ". ", options: .backwards) {
            return String(prefix[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines) + " …"
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + " …"
    }
    
    private func displayNameForNarratorMapping(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "(me)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "(narrator)", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Assembles memory, character, narrator, and style context for Gemini image edit (balanced mode — no extra vision step).
    private func buildFullImageEditInstruction(
        entry: MemoryEntry?,
        memoryID: UUID,
        pageTitle: String?,
        userRevision: String
    ) -> String {
        let trimmedUser = userRevision.trimmingCharacters(in: .whitespacesAndNewlines)

        var memoryText = ""
        var memoryPromptLine = ""
        if let entry {
            memoryText = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            memoryPromptLine = entry.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        
        let textForNarrator = memoryText.isEmpty ? memoryPromptLine : memoryText
        let cappedMemory = clampedMemoryTextForImageEdit(memoryText)
        let sceneSummary = deterministicSceneSummaryForImageEdit(from: memoryText)
        
        var characterCards = ""
        var narratorLines: [String] = []
        var narratorPresenceLabel = "unknown"
        
        if let entry {
            let narratorDecision = inferNarratorPresence(memoryText: textForNarrator, entry: entry)
            narratorPresenceLabel = narratorDecision.presence.rawValue
            let includeNarrator = narratorDecision.presence.shouldAttachHeadshot
            characterCards = buildCharacterList(for: entry, sceneDescription: sceneSummary, includeNarrator: includeNarrator)
            
            let subjectRaw = deriveSubjectName(from: entry) ?? profileName
            if let s = subjectRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                let label = displayNameForNarratorMapping(s)
                if !label.isEmpty {
                    narratorLines.append("When the user says \"me\", \"I\", \"my\", \"mine\", \"we\", \"us\", or \"our\" in the revision, those usually refer to: \(label).")
                }
            }
            if let p = profileName?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                let subjectFirst = deriveSubjectName(from: entry).map { displayNameForNarratorMapping($0) } ?? ""
                if subjectFirst.isEmpty || subjectFirst.caseInsensitiveCompare(p) != .orderedSame {
                    narratorLines.append("Memoir profile / subject display name (disambiguation): \(p).")
                }
            }
            narratorLines.append("NARRATOR PRESENCE classification: \(narratorPresenceLabel). If this is \(NarratorPresence.likelyAbsent.rawValue), do not force the profile subject into the scene when interpreting pronouns.")
        } else {
            narratorLines.append("No Core Data memory row found for this page's memory ID — pronoun resolution may be limited.")
            if let p = profileName?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                narratorLines.append("If the user says \"me\", they may mean the memoir subject: \(p).")
            }
        }
        
        var styleParts: [String] = []
        let custom = customArtStyleText.trimmingCharacters(in: .whitespacesAndNewlines)
        styleParts.append(extractStyleRequirement(for: currentArtStyle, custom: custom.isEmpty ? nil : custom))
        if let hint = styleReferencePromptHint(for: currentArtStyle) {
            styleParts.append(hint)
        }
        styleParts.append("TEXT RENDERING RULE: Do not add new readable text, letters, numbers, captions, signs, logos, or typographic marks unless the user explicitly requests text. Illustration only.")
        if currentArtStyle == .kidsBook {
            styleParts.append("FACIAL DETAIL RULE: Keep eyes expressive and human-like with visible iris/pupil detail and gentle eyelid/eyebrow definition, while preserving the soft watercolor children's-book vibe.")
        }
        if currentArtStyle == .realistic {
            styleParts.append("Camera pulled back, face partly turned away or softly out of focus so exact features are not discernible when appropriate.")
        }
        
        let characterSection: String
        if characterCards.isEmpty {
            characterSection = "No structured character cards on file. Infer who is who from MEMORY SOURCE and the INPUT IMAGE; keep each person visually consistent across the edit."
        } else {
            characterSection = characterCards
        }
        
        let titleLine: String
        if let t = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            titleLine = "PAGE / MEMORY DISPLAY TITLE: \(t)\n"
        } else {
            titleLine = ""
        }
        
        return """
        REVISION REQUEST (apply these changes — user's direct instruction):
        \(trimmedUser.isEmpty ? "(empty)" : trimmedUser)
        
        MEMORY ID (traceability): \(memoryID.uuidString)
        \(titleLine)MEMORY SOURCE OF TRUTH (do not contradict unless the revision explicitly overrides):
        \(cappedMemory.isEmpty ? "(No memory text on file.)" : cappedMemory)
        \(memoryPromptLine.isEmpty ? "" : "MEMORY PROMPT / QUESTION (context): \(memoryPromptLine)\n")
        SCENE SUMMARY (excerpt for grounding):
        \(sceneSummary)
        
        CHARACTER IDENTITY CARDS (preserve faces, skin tone, hair, age cues, and clothing unless the user asks to change them):
        \(characterSection)
        
        NARRATOR / PRONOUN RESOLUTION:
        \(narratorLines.joined(separator: "\n"))
        
        STYLE AND QUALITY RULES:
        \(styleParts.joined(separator: "\n"))
        
        EDITING CONSTRAINTS:
        - The INPUT IMAGE is the current illustration — use it as the starting canvas.
        - Preserve overall art style, palette, and character identities unless the user asks to change them.
        - Apply only the changes needed for the REVISION REQUEST.
        - Keep the same number of distinct people unless the user explicitly asks to add or remove someone.
        - Do not swap or merge identities between characters.
        - For "him", "her", "they", map to specific people using CHARACTER IDENTITY CARDS and memory cues when possible.
        """
    }
    
    // MARK: - Image Editing
    
    /// Edit an image at a specific page index with a revision prompt
    func editImage(at pageIndex: Int, revisionPrompt: String) async {
        // Validate index
        guard pageIndex >= 0, pageIndex < pageItems.count else {
            print("❌ Invalid page index for editing: \(pageIndex)")
            return
        }
        
        // Get the current image from the page item
        guard case .illustration(let currentImage, let memoryID, let existingTitle) = pageItems[pageIndex] else {
            print("❌ Page at index \(pageIndex) is not an illustration")
            return
        }
        
        // Set loading state
        await MainActor.run {
            imageEditingStates[pageIndex] = true
        }
        
        print("🖼️ Editing image at index \(pageIndex) with revision: \(revisionPrompt)")
        
        let memoryEntry = PersistenceController.shared.entry(id: memoryID)
        let fullEditInstruction = buildFullImageEditInstruction(
            entry: memoryEntry,
            memoryID: memoryID,
            pageTitle: existingTitle,
            userRevision: revisionPrompt
        )
        print("🖼️ Image edit full instruction length: \(fullEditInstruction.count) characters")
        
        do {
            // Use Gemini/Nano Banana to edit the image
            guard let geminiSvc = geminiImageSvc else {
                print("⚠️ Gemini service not available for image editing")
                await MainActor.run {
                    imageEditingStates[pageIndex] = false
                }
                return
            }
            
            if let editedImage = try await geminiSvc.editImage(
                image: currentImage,
                editInstruction: fullEditInstruction,
                size: imageGenerationSizeForCurrentStyle,
                model: effectiveGeminiModel
            ) {
                // Update the page item with the new image
                await MainActor.run {
                    pageItems[pageIndex] = .illustration(
                        image: editedImage,
                        memoryID: memoryID,
                        title: existingTitle
                    )
                    // Clear loading state
                    imageEditingStates[pageIndex] = false
                    // Note: editingImageIndex is managed by the View, don't clear it here
                }
                // Persist the updated storybook in place (same `bookVersionId` — do not mint a new doc)
                await saveCurrentBookInPlace(reason: "imageEdit")
                print("✅ Successfully edited image at index \(pageIndex)")
            } else {
                print("❌ Failed to edit image - no image returned from Gemini")
                await MainActor.run {
                    imageEditingStates[pageIndex] = false
                }
            }
        } catch {
            print("❌ Error editing image: \(error.localizedDescription)")
            await MainActor.run {
                imageEditingStates[pageIndex] = false
            }
        }
    }
    
    /// Check if an image at a specific index is currently being edited
    func isEditingImage(at index: Int) -> Bool {
        return imageEditingStates[index] == true
    }

    // MARK: - Print cover art editing (instruction-based, Gemini edit + PDF re-upload)

    private func buildCoverPanelEditInstruction(panel: BookCoverFlatPanel, userRevision: String) -> String {
        let trimmed = userRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        let custom = customArtStyleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let styleLine = extractStyleRequirement(for: currentArtStyle, custom: custom.isEmpty ? nil : custom)
        if panel == .front {
            return """
            BOOK COVER FRONT PANEL — full bleed print cover. The input is the current front cover (title may be painted into the art).

            USER REVISION REQUEST:
            \(trimmed)

            RULES:
            - Apply the revision while preserving the overall \(styleLine) look unless the user asks otherwise.
            - If the title appears in the artwork, keep it legible in the lower area unless the user explicitly asks to change or remove it.
            - Maintain professional dust-jacket composition; avoid clutter.
            """
        }
        return """
        BOOK COVER BACK PANEL — full bleed. The input may include illustration plus print typography from the current cover PDF.

        USER REVISION REQUEST:
        \(trimmed)

        RULES:
        - Apply the revision while preserving the overall \(styleLine) look unless the user asks otherwise.
        - Prefer calmer upper-left and readable contrast for overlaid marketing copy; avoid adding new stray words unless the user asks.
        """
    }

    /// Regenerates one panel of the print cover from user instructions, re-uploads `cover.pdf`, and refreshes `currentBookVersionRecord`.
    func editCoverPanel(_ panel: BookCoverFlatPanel, revisionPrompt: String) async {
        let trimmed = revisionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard panel == .front || panel == .back else { return }
        guard let bookId = lastSyncedBookVersionId,
              let record = currentBookVersionRecord,
              let pdfURL = record.printCoverPDFURL else {
            print("❌ editCoverPanel: missing synced book, record, or print cover PDF")
            return
        }
        guard let geminiSvc = geminiImageSvc else {
            print("⚠️ Gemini not available for cover edit")
            return
        }

        await MainActor.run { coverPanelEditing = panel }

        let layout = record.coverFlatLayoutKind
        let cacheRevision = record.coverThumbnailCacheRevision
        let cacheId = record.coverStoragePath ?? ""
        let targetSize = CGSize(width: 1536, height: 1152)

        async let frontTask = CoverPDFThumbnailService.loadAndCache(
            url: pdfURL,
            layout: layout,
            panel: .front,
            targetSize: targetSize,
            cacheRevision: cacheRevision,
            cacheIdentity: cacheId
        )
        async let backTask = CoverPDFThumbnailService.loadAndCache(
            url: pdfURL,
            layout: layout,
            panel: .back,
            targetSize: targetSize,
            cacheRevision: cacheRevision,
            cacheIdentity: cacheId
        )
        let (frontLoaded, backLoaded) = await (frontTask, backTask)

        guard let frontBase = frontLoaded else {
            print("❌ editCoverPanel: failed to load front panel raster")
            await MainActor.run { coverPanelEditing = nil }
            return
        }

        let instruction = buildCoverPanelEditInstruction(panel: panel, userRevision: trimmed)
        let editSize = "5:4"

        do {
            let frontFinal: UIImage
            let backFinal: UIImage?

            switch panel {
            case .front:
                guard let edited = try await geminiSvc.editImage(
                    image: frontBase,
                    editInstruction: instruction,
                    size: editSize,
                    model: effectiveGeminiModel
                ) else {
                    print("❌ editCoverPanel: Gemini returned no front image")
                    await MainActor.run { coverPanelEditing = nil }
                    return
                }
                frontFinal = edited
                backFinal = backLoaded
            case .back:
                guard let backBase = backLoaded else {
                    print("❌ editCoverPanel: failed to load back panel raster")
                    await MainActor.run { coverPanelEditing = nil }
                    return
                }
                guard let editedBack = try await geminiSvc.editImage(
                    image: backBase,
                    editInstruction: instruction,
                    size: editSize,
                    model: effectiveGeminiModel
                ) else {
                    print("❌ editCoverPanel: Gemini returned no back image")
                    await MainActor.run { coverPanelEditing = nil }
                    return
                }
                frontFinal = frontBase
                backFinal = editedBack
            case .full, .spine:
                await MainActor.run { coverPanelEditing = nil }
                return
            }

            let policy = CoverCopyPolicy(artStyle: currentArtStyle, profileDisplayName: profileName ?? "")
            let titleForPrint = bookDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? policy.defaultBookTitle()
                : bookDisplayTitle
            let pitch = backCoverPitch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? policy.fallbackBackCoverPitch(bookTitle: titleForPrint)
                : backCoverPitch
            let preset = CoverFontPreset(rawValue: coverFontPreset) ?? policy.coverFontPreset()
            let nameForRender = profileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (profileName ?? "Narrator")
                : "Narrator"
            let pageCount = pageItems.count

            let pdfData: Data?
            if record.pageWidth > record.pageHeight {
                pdfData = BookCoverRenderer.renderPDF(
                    frontCoverArt: frontFinal,
                    backCoverArt: backFinal,
                    profileName: nameForRender,
                    pageCount: pageCount,
                    frontTitle: titleForPrint,
                    backCoverPitch: pitch,
                    fontPreset: preset,
                    useNativeFrontTitleOverlay: false
                )
            } else {
                pdfData = BookCoverRenderer.renderPortraitPDF(
                    frontCoverArt: frontFinal,
                    backCoverArt: backFinal,
                    profileName: nameForRender,
                    pageCount: pageCount,
                    frontTitle: titleForPrint,
                    backCoverPitch: pitch,
                    fontPreset: preset,
                    useNativeFrontTitleOverlay: false
                )
            }

            guard let pdfData else {
                print("❌ editCoverPanel: PDF render failed")
                await MainActor.run { coverPanelEditing = nil }
                return
            }

            try await FirestoreSyncService.shared.mergeUploadedPrintCoverPDF(bookVersionId: bookId, pdfData: pdfData)
            if let updated = await FirestoreSyncService.shared.fetchBookVersion(bookVersionId: bookId) {
                await MainActor.run {
                    currentBookVersionRecord = updated
                    coverPanelEditing = nil
                }
            } else {
                await MainActor.run { coverPanelEditing = nil }
            }
            print("✅ editCoverPanel: cover PDF updated for panel \(panel)")
        } catch {
            print("❌ editCoverPanel: \(error.localizedDescription)")
            await MainActor.run { coverPanelEditing = nil }
        }
    }
    
    // MARK: - Text Editing

    /// Page dimensions (points) used by `paginateText` / generation; matches `runStorybookMemoryPipeline` fallbacks when not yet loaded.
    private func paginationViewportSizePoints() -> (width: CGFloat, height: CGFloat) {
        let isKids = currentArtStyle == .kidsBook
        if let w = loadedBookPageWidth, let h = loadedBookPageHeight, w > 1, h > 1 {
            return (w, h)
        }
        return isKids ? (792, 612) : (612, 792)
    }

    /// Rejoin split text pages before re-pagination (mirrors paragraph spacing per art style).
    private func combineTextPageBodiesForRepagination(_ bodies: [String]) -> String {
        guard !bodies.isEmpty else { return "" }
        let sep = currentArtStyle == .kidsBook ? "\n" : "\n\n"
        return bodies.joined(separator: sep)
    }

    /// Contiguous `.textPage` slice in `pageItems` for one memory (stops before illustration / other types).
    private func contiguousTextPageRun(around index: Int, memoryID: UUID) -> Range<Int>? {
        guard index >= 0, index < pageItems.count else { return nil }
        guard case .textPage(_, _, _, _, _, let mid) = pageItems[index], mid == memoryID else { return nil }
        var start = index
        while start > 0 {
            if case .textPage(_, _, _, _, _, let m) = pageItems[start - 1], m == memoryID {
                start -= 1
            } else { break }
        }
        var end = index
        while end + 1 < pageItems.count {
            if case .textPage(_, _, _, _, _, let m) = pageItems[end + 1], m == memoryID {
                end += 1
            } else { break }
        }
        return start..<(end + 1)
    }
    
    /// Update text content for a text page at the given index. Persists automatically.
    /// For ordinary memories, re-joins all text pages of that memory, applies the edit, re-paginates, and replaces the run.
    func updatePageText(at index: Int, title: String?, body: String?, subtitle: String?) {
        guard index >= 0, index < pageItems.count else { return }
        guard case .textPage(_, _, _, _, _, let memoryID) = pageItems[index] else { return }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil
        let trimmedSubtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSubtitle = (trimmedSubtitle?.isEmpty == false) ? trimmedSubtitle : nil

        if memoryID == BookInteriorAnchor.titlePageMemoryId || memoryID == BookInteriorAnchor.closingPageMemoryId {
            if case .textPage(let pageIndex, let total, _, _, _, _) = pageItems[index] {
                pageItems[index] = .textPage(
                    index: pageIndex,
                    total: total,
                    body: body ?? "",
                    title: effectiveTitle,
                    subtitle: effectiveSubtitle,
                    memoryID: memoryID
                )
                Task { await saveCurrentBookInPlace(reason: "textPageEdit") }
            }
            return
        }

        guard let run = contiguousTextPageRun(around: index, memoryID: memoryID) else {
            if case .textPage(let pageIndex, let total, _, _, _, _) = pageItems[index] {
                pageItems[index] = .textPage(
                    index: pageIndex,
                    total: total,
                    body: body ?? "",
                    title: effectiveTitle,
                    subtitle: effectiveSubtitle,
                    memoryID: memoryID
                )
                Task { await saveCurrentBookInPlace(reason: "textPageEdit") }
            }
            return
        }

        var bodies: [String] = []
        for i in run {
            guard case .textPage(_, _, let b, _, _, let m) = pageItems[i], m == memoryID else { continue }
            bodies.append(i == index ? (body ?? "") : b)
        }

        let combined = combineTextPageBodiesForRepagination(bodies)
        let trimmedCombined = combined.trimmingCharacters(in: .whitespacesAndNewlines)

        let repaged: [PageItem]
        if trimmedCombined.isEmpty {
            repaged = [
                .textPage(
                    index: 1,
                    total: 1,
                    body: "",
                    title: effectiveTitle,
                    subtitle: effectiveSubtitle,
                    memoryID: memoryID
                )
            ]
        } else {
            let (pw, ph) = paginationViewportSizePoints()
            repaged = paginateText(
                combined,
                title: effectiveTitle,
                subtitle: effectiveSubtitle,
                pageHeight: ph,
                pageWidth: pw,
                memoryID: memoryID
            )
        }

        guard !repaged.isEmpty else {
            if case .textPage(let pageIndex, let total, _, _, _, _) = pageItems[index] {
                pageItems[index] = .textPage(
                    index: pageIndex,
                    total: total,
                    body: body ?? "",
                    title: effectiveTitle,
                    subtitle: effectiveSubtitle,
                    memoryID: memoryID
                )
                Task { await saveCurrentBookInPlace(reason: "textPageEdit") }
            }
            return
        }

        var newItems = pageItems
        newItems.replaceSubrange(run, with: repaged)
        pageItems = newItems
        Task { await saveCurrentBookInPlace(reason: "textPageEdit") }
    }
    
    /// Update the title for an illustration page at the given index. Persists automatically.
    func updatePageIllustrationTitle(at index: Int, title: String?) {
        guard index >= 0, index < pageItems.count else { return }
        if case .illustration(let image, let memoryID, _) = pageItems[index] {
            pageItems[index] = .illustration(image: image, memoryID: memoryID, title: title)
            Task { await saveCurrentBookInPlace(reason: "illustrationTitleEdit") }
        }
    }
    
    /// Generate a QR code image from a text string
    static func qrCode(from text: String, size: CGFloat = 300) -> UIImage {
        return UIImage.memoirQRCode(from: text, size: size)
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale  = maxSide / longest
        let newSz  = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSz, false, 0)
        draw(in: CGRect(origin: .zero, size: newSz))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return out
    }
    static func memoirQRCode(from text: String, size: CGFloat = 300) -> UIImage {
        let ctx = CIContext()
        let f   = CIFilter.qrCodeGenerator()
        guard let messageData = text.data(using: String.Encoding.utf8) else {
            return UIImage()
        }
        f.message = messageData
        guard let ci = f.outputImage else { return UIImage() }
        let scaleX = size / ci.extent.size.width
        let scaleY = size / ci.extent.size.height
        let scaled = ci.transformed(by: .init(scaleX: scaleX, y: scaleY))
        if let cg = ctx.createCGImage(scaled, from: scaled.extent) {
            return UIImage(cgImage: cg)
        }
        return UIImage()
    }
}

