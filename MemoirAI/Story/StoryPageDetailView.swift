import SwiftUI
import UIKit

// MARK: - Zoomable Scroll View (UIScrollView wrapper for native pinch-to-zoom)
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: Content
    @Binding var zoomScale: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    
    init(
        zoomScale: Binding<CGFloat>,
        minZoom: CGFloat = 1.0,
        maxZoom: CGFloat = 4.0,
        @ViewBuilder content: () -> Content
    ) {
        self._zoomScale = zoomScale
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.content = content()
    }
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        
        scrollView.addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostingController.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        
        context.coordinator.hostingController = hostingController
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = content
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(zoomScale: $zoomScale)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var zoomScale: CGFloat
        var hostingController: UIHostingController<Content>?
        
        init(zoomScale: Binding<CGFloat>) {
            self._zoomScale = zoomScale
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return scrollView.subviews.first
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomScale = scrollView.zoomScale
        }
    }
}

// MARK: - Story Page Detail View
struct StoryPageDetailView: View {
    let initialPageIndex: Int
    @ObservedObject var vm: StoryPageViewModel
    let artStyle: ArtStyle
    let printSpec: BookPrintSpec
    let startEditingOnAppear: Bool
    var onRequestImageEdit: ((Int) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentPageIndex: Int = 0
    @State private var zoomScale: CGFloat = 1.0
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedBody: String = ""
    @State private var editedSubtitle: String = ""
    @State private var isEditingImageInline = false
    @State private var imageRevisionText = ""
    @State private var isImageSendPressed = false
    @State private var showCoverArtEditSheet = false
    @State private var coverArtEditPanel: BookCoverFlatPanel = .front
    @State private var coverArtRevisionText = ""
    @State private var showTitleBlurbEditor = false
    
    @FocusState private var imageRevisionFieldFocused: Bool
    
    private let colors = StoryPageLocalColors()
    private var isKidsBook: Bool { artStyle == .kidsBook }
    private var fontStyle: BookFontStyle { BookFontStyle(artStyle: artStyle) }
    
    // Character limits (matching PageZoomView / PageLimits)
    private let titleCharLimit = 80
    private let subtitleCharLimit = 120
    
    private var currentItem: StoryPageViewModel.PageItem? {
        guard currentPageIndex >= 0, currentPageIndex < vm.pageItems.count else { return nil }
        return vm.pageItems[currentPageIndex]
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundView
            
            VStack(spacing: 0) {
                headerView
                
                ZoomableScrollView(zoomScale: $zoomScale, minZoom: 1.0, maxZoom: 4.0) {
                    pageContentView
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Navigation chevrons
            chevronOverlay
            
            bottomChrome
        }
        .sheet(isPresented: $showCoverArtEditSheet) {
            StoryPage.CoverArtEditSheet(
                panel: coverArtEditPanel,
                revisionText: $coverArtRevisionText,
                isPresented: $showCoverArtEditSheet,
                onSend: { text in
                    Task {
                        await vm.editCoverPanel(coverArtEditPanel, revisionPrompt: text)
                    }
                },
                isEditing: vm.isEditingCoverArt(for: coverArtEditPanel),
                onEditTitleBlurb: {
                    showCoverArtEditSheet = false
                    showTitleBlurbEditor = true
                }
            )
            .presentationDetents([PresentationDetent.height(196)])
            .presentationDragIndicator(Visibility.visible)
        }
        .sheet(isPresented: $showTitleBlurbEditor) {
            StorybookCoverEditorSheet(vm: vm)
        }
        .onChange(of: vm.coverPanelEditing) { oldVal, newVal in
            if oldVal != nil && newVal == nil && showCoverArtEditSheet {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    coverArtRevisionText = ""
                    showCoverArtEditSheet = false
                }
            }
        }
        .onAppear {
            currentPageIndex = min(max(0, initialPageIndex), vm.pageItems.count - 1)
            syncEditedFieldsFromCurrentPage()
            if startEditingOnAppear {
                if case .illustration = currentItem {
                    beginInlineImageEdit()
                } else if case .textPage(_, _, _, _, _, let memoryID) = currentItem,
                          (memoryID == BookInteriorAnchor.titlePageMemoryId || memoryID == BookInteriorAnchor.closingPageMemoryId),
                          vm.hasPrintCoverPDF {
                    coverArtEditPanel = memoryID == BookInteriorAnchor.titlePageMemoryId ? .front : .back
                    coverArtRevisionText = ""
                    showCoverArtEditSheet = true
                } else {
                    isEditing = true
                }
            }
        }
        .onChange(of: currentPageIndex) { _ in
            syncEditedFieldsFromCurrentPage()
            isEditingImageInline = false
            imageRevisionText = ""
            imageRevisionFieldFocused = false
        }
    }
    
    /// Bottom chrome visible whenever the user is not in text-editing mode.
    private var isBottomToolbarVisible: Bool {
        !isEditing
    }
    
    /// Adaptive side slot sizing so header controls stay within screen bounds.
    private func headerSideSlotWidth(containerWidth: CGFloat) -> CGFloat {
        let target: CGFloat = isEditing ? 148 : 44
        let minimum: CGFloat = 44
        let horizontalPadding: CGFloat = 32 // 16 + 16
        let centerPillAllowance: CGFloat = 92
        let spacerAllowance: CGFloat = 16
        let maxPerSide = max(minimum, (containerWidth - horizontalPadding - centerPillAllowance - spacerAllowance) / 2)
        return min(target, maxPerSide)
    }
    
    private var backgroundView: some View {
        LinearGradient(
            colors: [
                Tokens.bgPrimary.opacity(0.96),
                Tokens.bgWash.opacity(0.90),
                Color.black.opacity(0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.black.opacity(0.26)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
    
    @ViewBuilder
    private var headerView: some View {
        GeometryReader { geo in
            let slotWidth = headerSideSlotWidth(containerWidth: geo.size.width)
            HStack(alignment: .center, spacing: 0) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8))
                }
                .frame(width: slotWidth, alignment: .leading)
                
                Spacer(minLength: 8)
                
                Text("\(currentPageIndex + 1) of \(max(vm.pageItems.count, 1))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(minWidth: 72, minHeight: 30)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8))
                
                Spacer(minLength: 8)
                
                HStack(spacing: 8) {
                    if isEditing {
                        actionPill(
                            title: "Save",
                            systemImage: "checkmark",
                            isProminent: true
                        ) {
                            saveEdits()
                            isEditing = false
                        }
                    }
                }
                .frame(width: slotWidth, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(height: 58)
    }
    
    private func actionPill(
        title: String,
        systemImage: String?,
        isProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isProminent {
                    Capsule().fill(
                        LinearGradient(
                            colors: [Tokens.accent.opacity(0.95), Tokens.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                } else {
                    Capsule().fill(Color.white.opacity(0.12))
                }
            }
            .overlay(
                Capsule().strokeBorder(
                    Color.white.opacity(isProminent ? 0.16 : 0.24),
                    lineWidth: 0.8
                )
            )
        }
        .buttonStyle(.plain)
    }
    
    /// Message-style field + send (`ImageEditSheet` parity); embed in expanded card or use standalone.
    @ViewBuilder
    private var imageRevisionComposerRow: some View {
        let isBusy = vm.isEditingImage(at: currentPageIndex)
        let trimmed = imageRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = !trimmed.isEmpty && !isBusy
        
        HStack(spacing: 10) {
            TextField("Describe the changes you want...", text: $imageRevisionText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .padding(.leading, 4)
                .focused($imageRevisionFieldFocused)
                .lineLimit(1...3)
                .disabled(isBusy)
                .submitLabel(.send)
                .onSubmit { sendInlineImageRevision() }
            
            Button(action: { sendInlineImageRevision() }) {
                ZStack {
                    if isBusy {
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
                .background(canSend ? colors.terracotta : Color.gray.opacity(0.45))
                .clipShape(Circle())
                .scaleEffect(isImageSendPressed ? 0.92 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isImageSendPressed)
                .animation(.easeInOut(duration: 0.15), value: canSend)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                isImageSendPressed = pressing
            }, perform: {})
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
    }
    
    private func sendInlineImageRevision() {
        let trimmed = imageRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !vm.isEditingImage(at: currentPageIndex) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let payload = trimmed
        imageRevisionText = ""
        Task {
            await vm.editImage(at: currentPageIndex, revisionPrompt: payload)
        }
    }
    
    private func exitInlineImageEditMode() {
        isEditingImageInline = false
        imageRevisionText = ""
        imageRevisionFieldFocused = false
    }
    
    private func beginInlineImageEdit() {
        isEditingImageInline = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            imageRevisionFieldFocused = true
        }
    }
    
    /// From expanded image-edit card: switch to on-page title editing.
    private func enterTitleEditFromImageFlow() {
        isEditingImageInline = false
        imageRevisionText = ""
        imageRevisionFieldFocused = false
        isEditing = true
    }
    
    /// Expanded bottom card for illustration image prompts (hybrid chrome).
    private var expandedIllustrationEditChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Button(action: { enterTitleEditFromImageFlow() }) {
                    Text("Edit title")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .underline()
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edits the page title on the illustration")
                
                Spacer(minLength: 0)
                
                Button(action: { exitInlineImageEditMode() }) {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            
            imageRevisionComposerRow
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: -4)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
    
    @ViewBuilder
    private func compactFloatingEditPill(title: String, systemImage: String?, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer(minLength: 0)
            actionPill(title: title, systemImage: systemImage, isProminent: true, action: action)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
    
    @ViewBuilder
    private var bottomChrome: some View {
        if !isBottomToolbarVisible {
            EmptyView()
        } else if case .illustration = currentItem {
            if isEditingImageInline {
                expandedIllustrationEditChrome
            } else {
                compactFloatingEditPill(title: "Edit Image", systemImage: "wand.and.stars") {
                    beginInlineImageEdit()
                }
            }
        } else if case .textPage(_, _, _, _, _, let memoryID) = currentItem,
                  memoryID == BookInteriorAnchor.titlePageMemoryId || memoryID == BookInteriorAnchor.closingPageMemoryId {
            if vm.hasPrintCoverPDF {
                VStack(spacing: 10) {
                    compactFloatingEditPill(
                        title: memoryID == BookInteriorAnchor.titlePageMemoryId ? "Edit cover art" : "Edit back cover",
                        systemImage: "wand.and.stars"
                    ) {
                        coverArtEditPanel = memoryID == BookInteriorAnchor.titlePageMemoryId ? .front : .back
                        coverArtRevisionText = ""
                        showCoverArtEditSheet = true
                    }
                    Button {
                        showTitleBlurbEditor = true
                    } label: {
                        Text("Edit book title & back cover text")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                compactFloatingEditPill(title: "Edit", systemImage: "pencil") {
                    isEditing = true
                }
            }
        } else if case .textPage = currentItem {
            compactFloatingEditPill(title: "Edit", systemImage: "pencil") {
                isEditing = true
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var pageContentView: some View {
        GeometryReader { geo in
            let frameWidth = printSpec.widthPt
            let frameHeight = printSpec.heightPt
            
            let maxDisplayWidth = geo.size.width * 0.92
            let maxDisplayHeight = geo.size.height * 0.92
            
            let renderScale = min(
                maxDisplayWidth / max(frameWidth, 1),
                maxDisplayHeight / max(frameHeight, 1)
            )
            let displayWidth = frameWidth * renderScale
            let displayHeight = frameHeight * renderScale
            
            if let item = currentItem {
                ZStack {
                    Group {
                        if isEditing {
                            inlineEditablePageContent(item: item, frameWidth: frameWidth, frameHeight: frameHeight)
                        } else {
                            displayPageContent(item: item, frameWidth: frameWidth, frameHeight: frameHeight)
                        }
                    }
                    .frame(width: frameWidth, height: frameHeight)
                    .scaleEffect(renderScale, anchor: .center)
                    .frame(width: displayWidth, height: displayHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func displayPageContent(item: StoryPageViewModel.PageItem, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        Group {
            switch item {
            case .illustration(let image, let memoryID, let title):
                illustrationPageView(image: image, memoryID: memoryID, title: title, frameWidth: frameWidth, frameHeight: frameHeight)
            case .textPage(let pageIndex, let total, let text, let title, let subtitle, let memoryID):
                textPageView(pageIndex: pageIndex, total: total, text: text, title: title, subtitle: subtitle, memoryID: memoryID, frameWidth: frameWidth, frameHeight: frameHeight)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
    }
    
    @ViewBuilder
    private func illustrationPageView(image: UIImage, memoryID: UUID, title: String?, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
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
                        pageNumber: currentPageIndex + 1
                    )
                } else {
                    VerticalBookIllustrationPage(
                        image: image,
                        memoryID: memoryID,
                        title: title,
                        fontStyle: BookFontStyle(artStyle: vm.currentArtStyle),
                        frameWidth: frameWidth,
                        frameHeight: frameHeight,
                        pageNumber: currentPageIndex + 1,
                        totalPages: vm.pageItems.count
                    )
                }
            }
        }
        .overlay {
            if !isPrecomposed {
                QRWatermark(memoryID: memoryID, topInset: frameHeight * 0.065 + 6)
            }
        }
    }
    
    @ViewBuilder
    private func textPageView(pageIndex: Int, total: Int, text: String, title: String?, subtitle: String?, memoryID: UUID, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        let fallbackFrontCover = MemoirCoverFrontPage(
            title: (title ?? vm.bookDisplayTitle).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Memoir" : (title ?? vm.bookDisplayTitle),
            subtitle: text,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            isKidsBook: isKidsBook
        )
        
        if memoryID == BookInteriorAnchor.titlePageMemoryId {
            if let pdfURL = printCoverPDFURL() {
                RemotePDFThumbnailView(
                    url: pdfURL,
                    targetSize: CGSize(width: max(frameWidth, 200), height: max(frameHeight, 200)),
                    layout: vm.currentBookVersionRecord?.coverFlatLayoutKind ?? .kidsBook,
                    panel: .front,
                    cacheRevision: vm.currentBookVersionRecord?.coverThumbnailCacheRevision ?? "",
                    cacheIdentity: vm.currentBookVersionRecord?.coverStoragePath ?? ""
                ) {
                    DetailTitleCoverLoadingPlaceholder(frameWidth: frameWidth, frameHeight: frameHeight)
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
                    layout: vm.currentBookVersionRecord?.coverFlatLayoutKind ?? .kidsBook,
                    panel: .back,
                    cacheRevision: vm.currentBookVersionRecord?.coverThumbnailCacheRevision ?? "",
                    cacheIdentity: vm.currentBookVersionRecord?.coverStoragePath ?? ""
                ) {
                    DetailTitleCoverLoadingPlaceholder(frameWidth: frameWidth, frameHeight: frameHeight)
                }
                .frame(width: frameWidth, height: frameHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                MemoirCoverBackPage(
                    heading: title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (title ?? "About this Memoir") : "About this Memoir",
                    bodyText: text,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight
                )
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
                        pageNumber: currentPageIndex + 1
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
                        pageNumber: currentPageIndex + 1
                    )
                }
            }
            .overlay(QRWatermark(memoryID: memoryID))
        }
    }
    
    // MARK: - Inline Editable Page Content (mirrors display layout exactly)
    @ViewBuilder
    private func inlineEditablePageContent(item: StoryPageViewModel.PageItem, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        Group {
            switch item {
            case .illustration(let image, let memoryID, _):
                inlineEditableIllustrationPage(image: image, memoryID: memoryID, frameWidth: frameWidth, frameHeight: frameHeight)
            case .textPage(let pageIndex, let total, _, _, _, let memoryID):
                inlineEditableTextPage(pageIndex: pageIndex, total: total, memoryID: memoryID, frameWidth: frameWidth, frameHeight: frameHeight)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
    }
    
    @ViewBuilder
    private func inlineEditableIllustrationPage(image: UIImage, memoryID: UUID, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        let isPrecomposed = vm.isPrecomposedIllustration(memoryID: memoryID)
        Group {
            if isPrecomposed {
                ZStack(alignment: .top) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: frameWidth, height: frameHeight)
                        .clipped()
                    
                    TextField("Page title", text: $editedTitle)
                        .font(.system(size: max(14, frameHeight * 0.028), weight: .semibold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                        )
                        .padding(.horizontal, max(16, frameWidth * 0.06))
                        .padding(.top, max(14, frameHeight * 0.04))
                }
            } else if isKidsBook {
                // KidsBookIllustrationPage layout: top bar (title + page#) + image
                VStack(spacing: 0) {
                    let barHeight = frameHeight * 0.065
                    HStack(alignment: .center) {
                        TextField("Memory", text: $editedTitle, axis: .vertical)
                            .font(.kidsBookTitleFont(for: frameHeight))
                            .foregroundColor(colors.chapterTitleColor)
                            .offset(y: max(1, barHeight * 0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(colors.chapterTitleColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            )
                        Spacer()
                        Text("\(currentPageIndex + 1)")
                            .font(.kidsBookPageNumberFont(for: frameHeight))
                            .foregroundColor(colors.pageNumberColor)
                    }
                    .padding(.horizontal, frameWidth * 0.08)
                    .padding(.vertical, barHeight * 0.1)
                    .frame(maxWidth: .infinity, minHeight: barHeight, alignment: .center)
                    .background(colors.bookPageBackground)

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            } else {
                // VerticalBookIllustrationPage layout: add title bar when editing
                VStack(spacing: 0) {
                    let titleBarHeight = frameHeight * 0.065
                    HStack(alignment: .center) {
                        TextField("Memory", text: $editedTitle, axis: .vertical)
                            .font(fontStyle.titleFont(for: frameHeight))
                            .foregroundColor(colors.chapterTitleColor)
                            .offset(y: max(1, titleBarHeight * 0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(colors.chapterTitleColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            )
                        Spacer()
                        Text("\(currentPageIndex + 1)")
                            .font(fontStyle.pageNumberFont(for: frameHeight))
                            .foregroundColor(colors.pageNumberColor)
                    }
                    .padding(.horizontal, frameWidth * 0.06)
                    .padding(.vertical, titleBarHeight * 0.1)
                    .frame(maxWidth: .infinity, minHeight: titleBarHeight, alignment: .center)
                    .background(colors.bookPageBackground)

                    Spacer()
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: frameHeight * 0.78)
                        .padding(.horizontal, frameWidth * 0.06)
                    Spacer()
                    HStack {
                        Text("\(currentPageIndex + 1)")
                            .font(.professionalPageNumberFont(for: frameHeight))
                            .foregroundColor(colors.pageNumberColor)
                        Spacer()
                        if currentPageIndex + 1 < vm.pageItems.count {
                            Text("\(currentPageIndex + 2)")
                                .font(.professionalPageNumberFont(for: frameHeight))
                                .foregroundColor(colors.pageNumberColor)
                        }
                    }
                    .padding(.horizontal, frameWidth * 0.06)
                    .padding(.bottom, frameHeight * 0.03)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if !isPrecomposed {
                QRWatermark(memoryID: memoryID, topInset: frameHeight * 0.065 + 6)
            }
        }
        .onChange(of: editedTitle) { newValue in
            if newValue.count > titleCharLimit { editedTitle = String(newValue.prefix(titleCharLimit)) }
        }
    }
    
    @ViewBuilder
    private func inlineEditableTextPage(pageIndex: Int, total: Int, memoryID: UUID, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        Group {
            if isKidsBook {
                // KidsBookTextPage layout: topMargin, header bar (title + page#), body TextEditor, bottomMargin
                let topMargin = frameHeight * 0.065
                let barHeight = frameHeight * 0.07
                let sideMargin = frameWidth * 0.085
                let rightMargin = frameWidth * 0.105
                let bottomMargin = frameHeight * 0.065
                
                VStack(spacing: 0) {
                    Spacer().frame(height: topMargin)
                    HStack(alignment: .center) {
                        TextField("Memory", text: $editedTitle, axis: .vertical)
                            .font(fontStyle.titleFont(for: frameHeight))
                            .foregroundColor(colors.chapterTitleColor)
                            .offset(y: max(1, barHeight * 0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(colors.chapterTitleColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            )
                        Spacer()
                        Text("\(currentPageIndex + 1)")
                            .font(fontStyle.pageNumberFont(for: frameHeight))
                            .foregroundColor(colors.pageNumberColor)
                    }
                    .padding(.horizontal, sideMargin)
                    .padding(.vertical, barHeight * 0.1)
                    .frame(maxWidth: .infinity, minHeight: barHeight, alignment: .center)
                    .background(colors.bookPageBackground)
                    
                    TextEditor(text: $editedBody)
                        .font(fontStyle.bodyFont(for: frameHeight))
                        .lineSpacing(12)
                        .foregroundColor(colors.bookTextColor)
                        .scrollContentBackground(.hidden)
                        .padding(.leading, sideMargin)
                        .padding(.trailing, rightMargin)
                        .padding(.top, frameHeight * 0.045)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(colors.bookFrameStroke.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    
                    Spacer().frame(height: bottomMargin)
                }
            } else {
                // VerticalBookTextPage layout: title, subtitle, body, page number
                ZStack {
                    colors.bookPageBackground
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: frameHeight * 0.015) {
                            TextField("Title", text: $editedTitle)
                                .font(fontStyle.titleFont(for: frameHeight))
                                .foregroundColor(colors.chapterTitleColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(colors.chapterTitleColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                )
                            
                            TextField("Subtitle", text: $editedSubtitle)
                                .font(.system(size: max(12, frameHeight * 0.021), weight: .regular))
                                .foregroundColor(colors.chapterTitleColor.opacity(0.7))
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(colors.chapterTitleColor.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                )
                        }
                        .padding(.leading, frameWidth * 0.06)
                        .padding(.trailing, frameWidth * 0.10)
                        .padding(.top, frameHeight * 0.05)
                        
                        TextEditor(text: $editedBody)
                            .font(fontStyle.bodyFont(for: frameHeight))
                            .lineSpacing(frameHeight * 0.006)
                            .foregroundColor(colors.bookTextColor)
                            .scrollContentBackground(.hidden)
                            .frame(maxWidth: .infinity, maxHeight: frameHeight * 0.75, alignment: .topLeading)
                            .padding(.leading, frameWidth * 0.06)
                            .padding(.trailing, frameWidth * 0.10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(colors.bookFrameStroke.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            )
                        
                        Spacer()
                        Text("\(currentPageIndex + 1)")
                            .font(fontStyle.pageNumberFont(for: frameHeight))
                            .foregroundColor(colors.pageNumberColor)
                            .padding(.bottom, frameHeight * 0.03)
                    }
                }
            }
        }
        .background(colors.bookPageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(QRWatermark(memoryID: memoryID))
        .onChange(of: editedTitle) { newValue in
            if newValue.count > titleCharLimit { editedTitle = String(newValue.prefix(titleCharLimit)) }
        }
        .onChange(of: editedSubtitle) { newValue in
            if newValue.count > subtitleCharLimit { editedSubtitle = String(newValue.prefix(subtitleCharLimit)) }
        }
    }
    
    private var shouldShowChevronNavigation: Bool {
        !isEditing && !isEditingImageInline
    }
    
    /// Lift chevrons above compact floating edit pill when visible (no full-width bar).
    private var chevronBottomPadding: CGFloat {
        guard shouldShowChevronNavigation else { return 34 }
        guard isBottomToolbarVisible else { return 34 }
        if isEditingImageInline { return 34 }
        switch currentItem {
        case .illustration?, .textPage?:
            return 86
        default:
            return 34
        }
    }
    
    @ViewBuilder
    private var chevronOverlay: some View {
        if shouldShowChevronNavigation {
            VStack {
                Spacer()
                HStack {
                    if currentPageIndex > 0 {
                        Button(action: { withAnimation { currentPageIndex -= 1 } }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white.opacity(0.95))
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
                                .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
                        }
                        .padding(.leading, 20)
                    } else {
                        Spacer()
                            .frame(width: 48)
                            .padding(.leading, 20)
                    }
                    
                    Spacer()
                    
                    if currentPageIndex < vm.pageItems.count - 1 {
                        Button(action: { withAnimation { currentPageIndex += 1 } }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white.opacity(0.95))
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
                                .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
                        }
                        .padding(.trailing, 20)
                    } else {
                        Spacer()
                            .frame(width: 48)
                            .padding(.trailing, 20)
                    }
                }
                .padding(.bottom, chevronBottomPadding)
            }
            .allowsHitTesting(true)
        }
    }
    
    private func syncEditedFieldsFromCurrentPage() {
        guard let item = currentItem else { return }
        switch item {
        case .illustration(_, _, let title):
            editedTitle = title ?? ""
            editedBody = ""
            editedSubtitle = ""
        case .textPage(_, _, let body, let title, let subtitle, _):
            editedTitle = title ?? ""
            editedBody = body
            editedSubtitle = subtitle ?? ""
        }
    }
    
    private func saveEdits() {
        switch currentItem {
        case .illustration:
            vm.updatePageIllustrationTitle(at: currentPageIndex, title: editedTitle.isEmpty ? nil : editedTitle)
        case .textPage:
            vm.updatePageText(at: currentPageIndex, title: editedTitle.isEmpty ? nil : editedTitle, body: editedBody, subtitle: editedSubtitle.isEmpty ? nil : editedSubtitle)
        case .none:
            break
        }
    }
    
    private func printCoverPDFURL() -> URL? {
        vm.currentBookVersionRecord?.printCoverPDFURL
    }
    
}

private struct DetailTitleCoverLoadingPlaceholder: View {
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
