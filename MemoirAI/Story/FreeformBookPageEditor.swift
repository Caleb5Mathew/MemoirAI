import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct ImportedBookPagePhoto: Transferable {
    let fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("memoir-page-photo-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedBookPagePhoto(fileURL: destination)
        }
    }
}

struct FreeformBookPageEditor: View {
    private enum InspectorField: Hashable {
        case text
        case caption
    }

    @Binding var document: BookPageDocument
    @Binding var isImportingPhotos: Bool
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    let onReset: (() -> Void)?
    let memoryID: UUID?
    let pageNumber: Int?
    let isLandscapePage: Bool
    let isIllustrationPage: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedElementID: UUID?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var moveStart: (id: UUID, frame: NormalizedPageRect)?
    @State private var resizeStart: (id: UUID, handle: BookPageResizeHandle, frame: NormalizedPageRect)?
    @State private var importErrorMessage: String?
    @State private var photoImportTask: Task<Void, Never>?
    @State private var history = BookPageEditorHistory()
    @State private var cropElementID: UUID?
    @State private var cropOriginalDocument: BookPageDocument?
    @State private var cropDragStart: BookPageImageCropTransform?
    @State private var cropZoomStart: Double?
    @FocusState private var focusedInspectorField: InspectorField?

    init(
        document: Binding<BookPageDocument>,
        isImportingPhotos: Binding<Bool> = .constant(false),
        isSaving: Bool = false,
        onCancel: @escaping () -> Void = {},
        onSave: @escaping () -> Void = {},
        onReset: (() -> Void)? = nil,
        memoryID: UUID? = nil,
        pageNumber: Int? = nil,
        isLandscapePage: Bool = false,
        isIllustrationPage: Bool = false
    ) {
        _document = document
        _isImportingPhotos = isImportingPhotos
        self.isSaving = isSaving
        self.onCancel = onCancel
        self.onSave = onSave
        self.onReset = onReset
        self.memoryID = memoryID
        self.pageNumber = pageNumber
        self.isLandscapePage = isLandscapePage
        self.isIllustrationPage = isIllustrationPage
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            GeometryReader { geometry in
                let canvasSize = fittedCanvasSize(
                    in: CGSize(
                        width: max(0, geometry.size.width - 28),
                        height: max(0, geometry.size.height - 20)
                    )
                )

                ZStack {
                    Tokens.bgPrimary
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard cropElementID == nil else { return }
                            selectedElementID = nil
                            focusedInspectorField = nil
                        }

                    ZStack {
                        Color(red: 0.99, green: 0.97, blue: 0.94)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard cropElementID == nil else { return }
                                selectedElementID = nil
                                focusedInspectorField = nil
                            }

                        ForEach(document.elements) { element in
                            editorElement(element, canvasSize: canvasSize)
                        }

                        BookPageDocumentChrome(
                            memoryID: memoryID,
                            pageNumber: pageNumber,
                            isLandscape: isLandscapePage,
                            isIllustration: isIllustrationPage
                        )
                        .allowsHitTesting(false)
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipShape(Rectangle())
                    .overlay(Rectangle().stroke(Tokens.ink.opacity(0.34), lineWidth: 1.5))
                    .shadow(color: Tokens.ink.opacity(0.15), radius: 10, y: 4)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .accessibilityLabel("Book page canvas")
                }
            }
        }
        .background(Tokens.bgPrimary.ignoresSafeArea())
        .accessibilityIdentifier("freeformPageEditor")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editorControlDock
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedElementID)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedInspectorField = nil
                }
            }
        }
        .alert(
            "Couldn’t Add Item",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "The item could not be added.")
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            photoImportTask?.cancel()
            photoImportTask = Task { @MainActor in
                importErrorMessage = nil
                isImportingPhotos = true
                defer {
                    isImportingPhotos = false
                    selectedPhotoItems = []
                }

                var failureCount = 0
                for item in items {
                    guard !Task.isCancelled else { break }
                    do {
                        guard let imported = try await item.loadTransferable(type: ImportedBookPagePhoto.self) else {
                            failureCount += 1
                            continue
                        }
                        defer { try? FileManager.default.removeItem(at: imported.fileURL) }
                        let remainingPixelBudget = max(
                            0,
                            BookPageCapacityPolicy.maximumStoredImagePixelCount - document.storedImagePixelCount
                        )
                        let storedImage = try await Task.detached(priority: .userInitiated) {
                            try BookPageImagePreparation.prepareForStorage(
                                fileURL: imported.fileURL,
                                maximumPixelCount: remainingPixelBudget
                            )
                        }.value
                        let previous = document
                        selectedElementID = try document.addImage(storedImage)
                        history.recordMutation(from: previous, to: document)
                    } catch let error as BookPageCapacityError {
                        importErrorMessage = error.localizedDescription
                        break
                    } catch {
                        failureCount += 1
                    }
                }

                if failureCount > 0, importErrorMessage == nil {
                    importErrorMessage = failureCount == 1
                        ? "One photo could not be prepared."
                        : "\(failureCount) photos could not be prepared."
                }
            }
        }
        .onDisappear {
            photoImportTask?.cancel()
            photoImportTask = nil
        }
    }

    private var editorControlDock: some View {
        VStack(spacing: 8) {
            Group {
                if selectedElementID != nil {
                    selectedElementInspector
                } else {
                    Text("Select an item to move, resize, crop, or edit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            editorToolbar
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(height: 158)
        .background(Tokens.bgPrimary)
        .overlay(alignment: .top) {
            Divider().overlay(Tokens.ink.opacity(0.16))
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 7) {
            Button(action: {
                if cropElementID != nil {
                    cancelCropping()
                } else {
                    onCancel()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Tokens.ink.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Close page editor")
            .disabled(isSaving)

            VStack(alignment: .leading, spacing: 1) {
                Text(cropElementID == nil ? "Edit Page" : "Crop Photo")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .lineLimit(1)
                Text(editorInstruction)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                history.undo(current: &document)
                clearSelectionIfNeeded()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 32, height: 36)
            }
            .disabled(!history.canUndo || isSaving || cropElementID != nil)
            .accessibilityLabel("Undo")

            Button {
                history.redo(current: &document)
                clearSelectionIfNeeded()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 32, height: 36)
            }
            .disabled(!history.canRedo || isSaving || cropElementID != nil)
            .accessibilityLabel("Redo")

            Button(action: onSave) {
                Group {
                    if isSaving {
                        ProgressView().tint(Tokens.ink)
                    } else {
                        Text("Save").fontWeight(.semibold)
                    }
                }
                .frame(minWidth: 48, minHeight: 38)
                .padding(.horizontal, 5)
                .foregroundStyle(Tokens.ink)
                .background(Tokens.accentSoft, in: Capsule())
            }
            .disabled(isSaving || isImportingPhotos || cropElementID != nil)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tokens.ink)
        .padding(.horizontal, 16)
    }

    private var editorInstruction: String {
        if cropElementID != nil {
            return "Drag to reposition · pinch to zoom"
        }
        return selectedElementID == nil ? "Tap an item to select it" : "Drag to move · use corners to resize"
    }

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            if cropElementID != nil {
                Label("Drag to reposition · pinch to zoom", systemImage: "hand.draw")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 42)
            } else {
            Button {
                let previous = document
                do {
                    selectedElementID = try document.addText()
                    history.recordMutation(from: previous, to: document)
                } catch {
                    importErrorMessage = error.localizedDescription
                }
            } label: {
                Label("Add Text", systemImage: "text.badge.plus")
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Tokens.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: max(
                    1,
                    min(
                        12,
                        min(
                            BookPageCapacityPolicy.maximumElementCount - document.elements.count,
                            BookPageCapacityPolicy.maximumImageCount - document.imageCount
                        )
                    )
                ),
                matching: .images
            ) {
                Label(isImportingPhotos ? "Adding" : "Add Photos", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Tokens.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(
                isImportingPhotos
                    || document.elements.count >= BookPageCapacityPolicy.maximumElementCount
                    || document.imageCount >= BookPageCapacityPolicy.maximumImageCount
                    || document.storedImageByteCount >= BookPageCapacityPolicy.maximumStoredImageByteCount
            )

            if let selectedElementID {
                Menu {
                    Button {
                        let previous = document
                        document.bringToFront(id: selectedElementID)
                        history.recordMutation(from: previous, to: document)
                    } label: {
                        Label("Bring to Front", systemImage: "square.3.layers.3d.top.filled")
                    }
                    Button {
                        let previous = document
                        document.sendToBack(id: selectedElementID)
                        history.recordMutation(from: previous, to: document)
                    } label: {
                        Label("Send to Back", systemImage: "square.2.layers.3d.bottom.filled")
                    }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .frame(width: 42, height: 42)
                        .background(Tokens.ink.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Arrange selected item")

                Button(role: .destructive) {
                    deleteElement(selectedElementID)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 42, height: 42)
                        .background(Color.red.opacity(0.10), in: Circle())
                }
                .accessibilityLabel("Delete selected item")
            }

            if let onReset {
                Button(role: .destructive, action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 42, height: 42)
                        .background(Color.red.opacity(0.10), in: Circle())
                }
                .accessibilityLabel("Reset to original page")
            }
            }
        }
        .buttonStyle(.plain)
        .tint(Tokens.accent)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var selectedElementInspector: some View {
        if let selectedElementID,
           let element = document.elements.first(where: { $0.id == selectedElementID }),
           case .text(let textContent) = element.content {
            VStack(alignment: .leading, spacing: 7) {
                TextField("Text", text: Binding(
                    get: {
                        guard let current = document.elements.first(where: { $0.id == selectedElementID }),
                              case .text(let content) = current.content else { return "" }
                        return content.text
                    },
                    set: {
                        let previous = document
                        if !document.updateText(id: selectedElementID, text: $0) {
                            importErrorMessage = BookPageCapacityError.maximumTextCharactersReached.localizedDescription
                        } else {
                            history.recordMutation(from: previous, to: document)
                        }
                    }
                ), axis: .vertical)
                .lineLimit(1...2)
                .focused($focusedInspectorField, equals: .text)
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tokens.ink.opacity(0.12)))
                .accessibilityLabel("Selected text")

                HStack(spacing: 10) {
                    Image(systemName: "textformat.size")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: {
                                guard let current = document.elements.first(where: { $0.id == selectedElementID }),
                                      case .text(let content) = current.content else {
                                    return BookPageEditingPolicy.defaultFontSize
                                }
                                return content.fontSize
                            },
                            set: {
                                document.updateFontSize(id: selectedElementID, fontSize: $0)
                            }
                        ),
                        in: BookPageEditingPolicy.minimumFontSize...BookPageEditingPolicy.maximumFontSize,
                        onEditingChanged: { isEditing in
                            if isEditing {
                                history.beginMutation(from: document)
                            } else {
                                history.commitMutation(to: document)
                            }
                        }
                    )
                    .accessibilityLabel("Text size")
                    Text("\(Int((textContent.fontSize * 612).rounded())) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)

                    Menu {
                        ForEach(BookPageTextAlignment.allCases, id: \.self) { alignment in
                            Button(alignment.displayName) {
                                let previous = document
                                document.updateTextAlignment(id: selectedElementID, alignment: alignment)
                                history.recordMutation(from: previous, to: document)
                            }
                        }
                    } label: {
                        Label("Align", systemImage: "text.alignleft")
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 62, minHeight: 36)
                    }
                }
            }
            .padding(.horizontal)
        } else if let selectedElementID,
                  let element = document.elements.first(where: { $0.id == selectedElementID }),
                  case .image = element.content {
            VStack(alignment: .leading, spacing: 7) {
                TextField(
                    "Add a caption",
                    text: Binding(
                        get: {
                            guard let current = document.elements.first(where: { $0.id == selectedElementID }),
                                  case .image(let content) = current.content else { return "" }
                            return content.caption
                        },
                        set: {
                            let previous = document
                            document.updateImageCaption(id: selectedElementID, caption: $0)
                            history.recordMutation(from: previous, to: document)
                        }
                    )
                )
                .focused($focusedInspectorField, equals: .caption)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Tokens.ink.opacity(0.12)))
                .accessibilityLabel("Photo caption")

                HStack(spacing: 8) {
                    if cropElementID == selectedElementID {
                        compactInspectorButton("Cancel", systemImage: "xmark", role: .destructive) {
                            cancelCropping()
                        }
                        compactInspectorButton("Done Cropping", systemImage: "checkmark", prominent: true) {
                            finishCropping()
                        }
                    } else {
                        Menu {
                            Button("Fit entire photo") { updateImageFit(.fit, id: selectedElementID) }
                            Button("Fill frame") { updateImageFit(.fill, id: selectedElementID) }
                        } label: {
                            Label("Frame", systemImage: "rectangle.inset.filled")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(Tokens.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                        }
                        .accessibilityLabel("Photo frame style")

                        compactInspectorButton("Crop", systemImage: "crop", prominent: true) {
                            beginCropping(id: selectedElementID)
                        }
                    }
                }
            }
            .padding(.horizontal)
        } else {
            EmptyView()
        }
    }

    private func compactInspectorButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(Tokens.ink)
                .background(
                    prominent ? Tokens.accentSoft : Tokens.bgWash,
                    in: RoundedRectangle(cornerRadius: 9)
                )
        }
        .buttonStyle(.plain)
    }

    private func editorElement(_ element: BookPageElement, canvasSize: CGSize) -> AnyView {
        let frame = element.frame
        let width = canvasSize.width * CGFloat(frame.width)
        let height = canvasSize.height * CGFloat(frame.height)
        let isSelected = selectedElementID == element.id

        if element.isLockedBackground {
            return AnyView(
                BookPageElementView(element: element, semanticTemplate: document.semanticTemplate)
                    .frame(width: width, height: height)
                    .position(
                        x: canvasSize.width * CGFloat(frame.x + frame.width / 2),
                        y: canvasSize.height * CGFloat(frame.y + frame.height / 2)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
        }

        let interactiveElement = AnyView(
            BookPageElementView(element: element, semanticTemplate: document.semanticTemplate)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .overlay {
                if isSelected {
                    selectionOverlay(for: element, canvasSize: canvasSize)
                }
            }
            .position(
                x: canvasSize.width * CGFloat(frame.x + frame.width / 2),
                y: canvasSize.height * CGFloat(frame.y + frame.height / 2)
            )
            .onTapGesture {
                guard cropElementID == nil || cropElementID == element.id else { return }
                selectedElementID = element.id
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if cropElementID == element.id {
                            updateCropDrag(for: element, translation: value.translation, elementSize: CGSize(
                                width: width,
                                height: height
                            ))
                            return
                        }
                        if moveStart?.id != element.id {
                            moveStart = (element.id, element.frame)
                            selectedElementID = element.id
                            history.beginMutation(from: document)
                        }
                        guard let start = moveStart, start.id == element.id else { return }
                        let translation = CGSize(
                            width: value.translation.width / max(canvasSize.width, 1),
                            height: value.translation.height / max(canvasSize.height, 1)
                        )
                        document.moveElement(
                            id: element.id,
                            startingAt: start.frame,
                            normalizedTranslation: translation
                        )
                    }
                    .onEnded { _ in
                        if cropElementID == element.id {
                            cropDragStart = nil
                            return
                        }
                        moveStart = nil
                        history.commitMutation(to: document)
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        guard cropElementID == element.id else { return }
                        updateCropZoom(
                            for: element,
                            magnification: value.magnification,
                            elementSize: CGSize(width: width, height: height)
                        )
                    }
                    .onEnded { _ in
                        cropZoomStart = nil
                    }
            )
            .allowsHitTesting(cropElementID == nil || cropElementID == element.id)
        )

        return AnyView(interactiveElement
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: element))
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double tap to select. Use actions to arrange or delete this item.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: "Select") {
                guard cropElementID == nil || cropElementID == element.id else { return }
                selectedElementID = element.id
            }
            .accessibilityAction(named: "Bring to Front") {
                document.bringToFront(id: element.id)
            }
            .accessibilityAction(named: "Send to Back") {
                document.sendToBack(id: element.id)
            }
            .accessibilityAction(named: "Move Left") {
                document.moveElement(id: element.id, normalizedTranslation: CGSize(width: -0.02, height: 0))
            }
            .accessibilityAction(named: "Move Right") {
                document.moveElement(id: element.id, normalizedTranslation: CGSize(width: 0.02, height: 0))
            }
            .accessibilityAction(named: "Move Up") {
                document.moveElement(id: element.id, normalizedTranslation: CGSize(width: 0, height: -0.02))
            }
            .accessibilityAction(named: "Move Down") {
                document.moveElement(id: element.id, normalizedTranslation: CGSize(width: 0, height: 0.02))
            }
            .accessibilityAction(named: "Make Larger") {
                document.resizeElement(
                    id: element.id,
                    handle: .bottomTrailing,
                    normalizedTranslation: CGSize(width: 0.03, height: 0.03)
                )
            }
            .accessibilityAction(named: "Make Smaller") {
                document.resizeElement(
                    id: element.id,
                    handle: .bottomTrailing,
                    normalizedTranslation: CGSize(width: -0.03, height: -0.03)
                )
            }
            .accessibilityAction(named: "Delete") {
                deleteElement(element.id)
            }
        )
    }

    private func deleteElement(_ id: UUID) {
        let previous = document
        document.deleteElement(id: id)
        history.recordMutation(from: previous, to: document)
        guard selectedElementID == id else { return }
        selectedElementID = nil
    }

    private func clearSelectionIfNeeded() {
        guard let selectedElementID else { return }
        guard !document.elements.contains(where: { $0.id == selectedElementID }) else { return }
        self.selectedElementID = nil
    }

    private func selectionOverlay(
        for element: BookPageElement,
        canvasSize: CGSize
    ) -> some View {
        ZStack {
            Rectangle()
                .stroke(cropElementID == element.id ? Tokens.accent : Color.accentColor, lineWidth: cropElementID == element.id ? 3 : 2)
                .allowsHitTesting(false)

            if cropElementID != element.id {
                ForEach(BookPageResizeHandle.allCases, id: \.self) { handle in
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: 16, height: 16)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .position(handlePosition(handle, elementSize: CGSize(
                        width: canvasSize.width * CGFloat(element.frame.width),
                        height: canvasSize.height * CGFloat(element.frame.height)
                    )))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if resizeStart?.id != element.id || resizeStart?.handle != handle {
                                    resizeStart = (element.id, handle, element.frame)
                                    history.beginMutation(from: document)
                                }
                                guard let start = resizeStart,
                                      start.id == element.id,
                                      start.handle == handle else { return }
                                let translation = CGSize(
                                    width: value.translation.width / max(canvasSize.width, 1),
                                    height: value.translation.height / max(canvasSize.height, 1)
                                )
                                document.resizeElement(
                                    id: element.id,
                                    startingAt: start.frame,
                                    handle: handle,
                                    normalizedTranslation: translation
                                )
                            }
                            .onEnded { _ in
                                resizeStart = nil
                                history.commitMutation(to: document)
                            }
                    )
                    .accessibilityLabel("Resize \(handle.accessibilityName)")
                    .accessibilityHint("Drag to resize the selected item")
                }
            }

        }
    }

    private func updateImageFit(_ fit: BookPageImageFit, id: UUID) {
        let previous = document
        document.updateImageFit(id: id, fit: fit)
        history.recordMutation(from: previous, to: document)
    }

    private func beginCropping(id: UUID) {
        guard cropElementID == nil,
              let element = document.elements.first(where: { $0.id == id }),
              case .image = element.content else { return }
        focusedInspectorField = nil
        cropOriginalDocument = document
        cropElementID = id
        document.updateImageFit(id: id, fit: .fill)
    }

    private func cancelCropping() {
        if let cropOriginalDocument {
            document = cropOriginalDocument
        }
        clearCropState()
    }

    private func finishCropping() {
        if let cropOriginalDocument {
            history.recordMutation(from: cropOriginalDocument, to: document)
        }
        clearCropState()
    }

    private func clearCropState() {
        cropElementID = nil
        cropOriginalDocument = nil
        cropDragStart = nil
        cropZoomStart = nil
    }

    private func updateCropDrag(for element: BookPageElement, translation: CGSize, elementSize: CGSize) {
        guard case .image(let image) = element.content else { return }
        let start = cropDragStart ?? image.cropTransform
        cropDragStart = start
        let mediaSize = imageMediaSize(for: image, elementSize: elementSize)
        let candidate = BookPageImageCropTransform(
            zoom: start.zoom,
            offsetX: start.offsetX + Double(translation.width / max(mediaSize.width, 1)),
            offsetY: start.offsetY + Double(translation.height / max(mediaSize.height, 1))
        )
        document.updateImageCropTransform(id: element.id, transform: candidate, viewportSize: mediaSize)
    }

    private func updateCropZoom(
        for element: BookPageElement,
        magnification: CGFloat,
        elementSize: CGSize
    ) {
        guard case .image(let image) = element.content else { return }
        let start = cropZoomStart ?? image.cropTransform.zoom
        cropZoomStart = start
        let candidate = BookPageImageCropTransform(
            zoom: start * Double(magnification),
            offsetX: image.cropTransform.offsetX,
            offsetY: image.cropTransform.offsetY
        )
        document.updateImageCropTransform(
            id: element.id,
            transform: candidate,
            viewportSize: imageMediaSize(for: image, elementSize: elementSize)
        )
    }

    private func imageMediaSize(for image: BookPageStoredImage, elementSize: CGSize) -> CGSize {
        let captionHeight = BookPageImageLayout.captionHeight(
            caption: image.caption,
            containerSize: elementSize
        )
        return CGSize(width: elementSize.width, height: max(1, elementSize.height - captionHeight))
    }

    private func fittedCanvasSize(in available: CGSize) -> CGSize {
        let aspectRatio = CGFloat(document.pageAspectRatio)
        guard available.width > 0, available.height > 0, aspectRatio.isFinite, aspectRatio > 0 else {
            return .zero
        }
        let widthAtFullHeight = available.height * aspectRatio
        if widthAtFullHeight <= available.width {
            return CGSize(width: widthAtFullHeight, height: available.height)
        }
        return CGSize(width: available.width, height: available.width / aspectRatio)
    }

    private func handlePosition(_ handle: BookPageResizeHandle, elementSize: CGSize) -> CGPoint {
        let inset = min(10, max(0, min(elementSize.width, elementSize.height) / 2))
        switch handle {
        case .topLeading:
            return CGPoint(x: inset, y: inset)
        case .topTrailing:
            return CGPoint(x: max(inset, elementSize.width - inset), y: inset)
        case .bottomLeading:
            return CGPoint(x: inset, y: max(inset, elementSize.height - inset))
        case .bottomTrailing:
            return CGPoint(
                x: max(inset, elementSize.width - inset),
                y: max(inset, elementSize.height - inset)
            )
        }
    }

    private func accessibilityLabel(for element: BookPageElement) -> String {
        switch element.content {
        case .text(let content):
            let trimmed = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = String(trimmed.prefix(120))
            return preview.isEmpty ? "Text box" : "Text box, \(preview)"
        case .image(let image):
            return image.accessibilityDescription
        }
    }
}

struct PreparedBookPageEditorHost: View {
    let request: PreparedPageEditorRequest
    @ObservedObject var vm: StoryPageViewModel
    let onDismiss: () -> Void

    @State private var document: BookPageDocument
    @State private var isImportingPhotos = false
    @State private var isSaving = false
    @State private var showResetConfirmation = false
    @State private var errorMessage: String?

    init(
        request: PreparedPageEditorRequest,
        vm: StoryPageViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.request = request
        self.vm = vm
        self.onDismiss = onDismiss
        _document = State(initialValue: request.document)
    }

    var body: some View {
        FreeformBookPageEditor(
            document: $document,
            isImportingPhotos: $isImportingPhotos,
            isSaving: isSaving,
            onCancel: onDismiss,
            onSave: {
                guard !isSaving, !isImportingPhotos else { return }
                let savedDocument = document
                isSaving = true
                Task {
                    defer { isSaving = false }
                    var locallyApplied = false
                    do {
                        switch request.target {
                        case .interiorPage:
                            try await vm.applyFreeformDocument(
                                savedDocument,
                                pageID: request.pageID,
                                onLocallyApplied: {
                                    locallyApplied = true
                                    onDismiss()
                                }
                            )
                        case .exteriorCover(let panel):
                            try await vm.applyExteriorCoverDocument(savedDocument, panel: panel)
                            onDismiss()
                        }
                    } catch {
                        if locallyApplied {
                            vm.errorMessage = error.localizedDescription
                        } else {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            },
            onReset: request.canReset ? { showResetConfirmation = true } : nil,
            memoryID: request.showsChrome ? request.memoryID : nil,
            pageNumber: request.showsChrome ? request.pageIndex + 1 : nil,
            isLandscapePage: request.isLandscape,
            isIllustrationPage: request.isIllustration
        )
        .allowsHitTesting(!isSaving)
        .interactiveDismissDisabled()
        .confirmationDialog(
            "Reset this page to its original layout?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Page", role: .destructive) {
                guard !isSaving else { return }
                isSaving = true
                Task {
                    defer { isSaving = false }
                    do {
                        guard case .interiorPage = request.target else {
                            throw BookPageEditorPersistenceError.editingUnavailable
                        }
                        try await vm.removeFreeformDocument(pageID: request.pageID)
                        onDismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your custom text and photos on this page will be removed.")
        }
        .alert(
            "Page Editor",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The page could not be saved.")
        }
    }
}

struct BookPageDocumentView: View {
    let document: BookPageDocument

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.99, green: 0.97, blue: 0.94)
                ForEach(document.elements) { element in
                    BookPageElementView(element: element, semanticTemplate: document.semanticTemplate)
                        .frame(
                            width: geometry.size.width * CGFloat(element.frame.width),
                            height: geometry.size.height * CGFloat(element.frame.height)
                        )
                        .position(
                            x: geometry.size.width * CGFloat(element.frame.x + element.frame.width / 2),
                            y: geometry.size.height * CGFloat(element.frame.y + element.frame.height / 2)
                        )
                }
            }
            .clipped()
        }
    }
}

struct BookPageDocumentChrome: View {
    let memoryID: UUID?
    let pageNumber: Int?
    let isLandscape: Bool
    var isIllustration: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let logicalPageWidth: CGFloat = isLandscape ? 792 : 612
            let chromeScale = geometry.size.width / logicalPageWidth
            ZStack {
                if let memoryID, !BookInteriorAnchor.isNonMemoryPage(memoryID) {
                    QRWatermark(
                        memoryID: memoryID,
                        topInset: isLandscape && isIllustration
                            ? geometry.size.height * 0.065 + (6 * chromeScale)
                            : 0,
                        qrSide: 60 * chromeScale,
                        imagePadding: 8 * chromeScale,
                        trailingPadding: 12 * chromeScale,
                        topPadding: 8 * chromeScale
                    )
                }

                if let pageNumber {
                    Text("\(pageNumber)")
                        .font(.system(size: max(4, 10 * chromeScale), design: .serif))
                        .foregroundStyle(Color(red: 0.30, green: 0.27, blue: 0.23))
                        .position(
                            x: isLandscape ? geometry.size.width * 0.89 : geometry.size.width * 0.50,
                            y: isLandscape
                                ? geometry.size.height * (isIllustration ? 0.0325 : 0.10)
                                : geometry.size.height * 0.96
                        )
                }
            }
        }
    }
}

enum BookPageImageLayout {
    static func captionHeight(caption: String, containerSize: CGSize) -> CGFloat {
        guard !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              containerSize.width > 0,
              containerSize.height > 0 else { return 0 }
        return min(containerSize.height * 0.24, max(containerSize.height * 0.14, containerSize.width * 0.055))
    }
}

private struct BookPageImageContentView: View {
    let image: BookPageStoredImage

    var body: some View {
        GeometryReader { geometry in
            let caption = image.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let captionHeight = BookPageImageLayout.captionHeight(
                caption: caption,
                containerSize: geometry.size
            )
            let mediaSize = CGSize(
                width: geometry.size.width,
                height: max(1, geometry.size.height - captionHeight)
            )
            let crop = BookPageImageCropPolicy.clamped(
                image.cropTransform,
                imageSize: CGSize(width: CGFloat(image.pixelWidth), height: CGFloat(image.pixelHeight)),
                viewportSize: mediaSize
            )

            VStack(spacing: 0) {
                if let uiImage = UIImage(data: image.jpegData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: image.fit == .fill ? .fill : .fit)
                        .frame(width: mediaSize.width, height: mediaSize.height)
                        .scaleEffect(image.fit == .fill ? CGFloat(crop.zoom) : 1)
                        .offset(
                            x: image.fit == .fill ? CGFloat(crop.offsetX) * mediaSize.width : 0,
                            y: image.fit == .fill ? CGFloat(crop.offsetY) * mediaSize.height : 0
                        )
                        .clipped()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.10)
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: mediaSize.width, height: mediaSize.height)
                }

                if !caption.isEmpty {
                    Text(caption)
                        .font(.system(
                            size: max(7, min(captionHeight * 0.44, geometry.size.width * 0.045)),
                            design: .serif
                        ))
                        .foregroundStyle(Color(red: 0.18, green: 0.16, blue: 0.14))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, max(3, geometry.size.width * 0.018))
                        .frame(width: geometry.size.width, height: captionHeight)
                        .background(Color(red: 1.0, green: 0.992, blue: 0.965))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(caption.isEmpty ? image.accessibilityDescription : caption)
        }
    }
}

private struct BookPageElementView: View {
    let element: BookPageElement
    let semanticTemplate: BookPageSemanticTemplate?

    var body: some View {
        GeometryReader { geometry in
            switch element.content {
            case .text(let content):
                let pageHeight = geometry.size.height / max(CGFloat(element.frame.height), 0.001)
                let fontStyle: BookFontStyle = switch content.typographyPreset {
                case .kidsBook: .kidsBook
                case .comic: .comic
                case .realistic: .realistic
                case .custom: .custom
                }
                let fontSize = BookPageTextSizing.pointSize(for: content, pageHeight: pageHeight)
                let textColor: Color = switch content.color {
                case .ink: Color(red: 0.20, green: 0.20, blue: 0.20)
                case .brown: Color(red: 0.40, green: 0.30, blue: 0.20)
                case .mutedBrown: Color(red: 0.40, green: 0.30, blue: 0.20).opacity(0.70)
                case .white: .white
                case nil:
                    switch content.role {
                    case .title:
                        semanticTemplate == nil
                            ? Color(red: 0.40, green: 0.30, blue: 0.20)
                            : Color(red: 0.20, green: 0.18, blue: 0.15)
                    case .subtitle: Color(red: 0.40, green: 0.30, blue: 0.20).opacity(0.70)
                    case .body:
                        semanticTemplate == .interiorTitle
                            ? Color(red: 0.42, green: 0.38, blue: 0.33)
                            : Color(red: 0.20, green: 0.20, blue: 0.20)
                    case .custom: Color(red: 0.20, green: 0.20, blue: 0.20)
                    }
                }
                Group {
                    switch content.role {
                    case .title:
                        if semanticTemplate != nil {
                            Text(content.text)
                                .font(
                                    content.typographyPreset.interiorTitleTypography == .rounded
                                        ? .system(size: fontSize, weight: .semibold, design: .rounded)
                                        : .custom("Georgia-Bold", size: fontSize)
                                )
                                .lineLimit(3)
                                .minimumScaleFactor(0.65)
                                .allowsTightening(true)
                        } else {
                            Text(content.text)
                                .font(titleFont(style: fontStyle, size: fontSize))
                                .fontWeight(.bold)
                        }
                    case .subtitle:
                        Text(content.text)
                            .font(.system(size: fontSize, weight: .regular, design: .serif))
                            .italic()
                    case .body:
                        if semanticTemplate == .interiorClosing {
                            Text(content.text)
                                .font(.system(size: fontSize, weight: .semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                        } else if semanticTemplate == .interiorTitle {
                            Text(content.text)
                                .font(
                                    content.typographyPreset.interiorTitleTypography == .rounded
                                        ? .system(size: fontSize, weight: .regular, design: .rounded)
                                        : .custom("Georgia", size: fontSize)
                                )
                                .lineSpacing(pageHeight * 0.006)
                                .lineLimit(3)
                                .minimumScaleFactor(0.72)
                        } else {
                            Text(content.text)
                                .font(bodyFont(style: fontStyle, size: fontSize))
                                .lineSpacing(pageHeight * 0.006)
                        }
                    case .custom:
                        Text(content.text)
                            .font(.system(size: fontSize, design: .serif))
                    }
                }
                .foregroundStyle(textColor)
                .multilineTextAlignment(content.alignment.swiftUIAlignment)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: semanticTemplate == nil ? content.alignment.frameAlignment : .center
                )
                .clipped()
            case .image(let image):
                BookPageImageContentView(image: image)
            }
        }
    }

    private func titleFont(style: BookFontStyle, size: CGFloat) -> Font {
        switch style {
        case .kidsBook: return .custom("TimesNewRomanPS-BoldMT", size: size)
        case .comic: return .system(size: size, weight: .heavy, design: .serif)
        case .realistic: return .custom("Georgia-Bold", size: size)
        case .custom: return .system(size: size, weight: .semibold, design: .serif)
        }
    }

    private func bodyFont(style: BookFontStyle, size: CGFloat) -> Font {
        switch style {
        case .kidsBook: return .custom("TimesNewRomanPSMT", size: size)
        case .comic: return .system(size: size, weight: .semibold, design: .serif)
        case .realistic: return .custom("Georgia", size: size)
        case .custom: return .system(size: size, weight: .regular, design: .serif)
        }
    }
}

@MainActor
enum BookPagePrintRenderer {
    static func render(
        document: BookPageDocument,
        pixelSize: CGSize,
        memoryID: UUID? = nil,
        pageNumber: Int? = nil,
        isLandscape: Bool = false
    ) -> UIImage? {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let page = BookPageDocumentView(document: document)
            .frame(width: pixelSize.width, height: pixelSize.height)
        let content: AnyView
        content = AnyView(
            page.overlay(
                BookPageDocumentChrome(
                    memoryID: memoryID,
                    pageNumber: pageNumber,
                    isLandscape: isLandscape,
                    isIllustration: false
                )
            )
        )
        let renderer = ImageRenderer(
            content: content
        )
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(pixelSize)
        return renderer.uiImage
    }
}

private extension BookPageTextAlignment {
    var swiftUIAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: return .topLeading
        case .center: return .top
        case .trailing: return .topTrailing
        }
    }
}

private extension BookPageTextAlignment {
    var displayName: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }
}

private extension BookPageResizeHandle {
    var accessibilityName: String {
        switch self {
        case .topLeading: return "top left"
        case .topTrailing: return "top right"
        case .bottomLeading: return "bottom left"
        case .bottomTrailing: return "bottom right"
        }
    }
}
