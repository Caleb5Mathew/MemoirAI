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
    @Binding var document: BookPageDocument
    @Binding var isImportingPhotos: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedElementID: UUID?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var moveStart: (id: UUID, frame: NormalizedPageRect)?
    @State private var resizeStart: (id: UUID, handle: BookPageResizeHandle, frame: NormalizedPageRect)?
    @State private var importErrorMessage: String?
    @State private var photoImportTask: Task<Void, Never>?

    init(document: Binding<BookPageDocument>, isImportingPhotos: Binding<Bool> = .constant(false)) {
        _document = document
        _isImportingPhotos = isImportingPhotos
    }

    var body: some View {
        VStack(spacing: 12) {
            editorToolbar

            GeometryReader { geometry in
                let canvasSize = fittedCanvasSize(in: geometry.size)

                ZStack {
                    Color(red: 0.99, green: 0.98, blue: 0.95)

                    ForEach(document.elements) { element in
                        editorElement(element, canvasSize: canvasSize)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipShape(Rectangle())
                .overlay(Rectangle().stroke(Color.black.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .accessibilityLabel("Book page canvas")
            }

            selectedElementInspector
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedElementID)
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
                        let storedImage = try await Task.detached(priority: .userInitiated) {
                            try BookPageImagePreparation.prepareForStorage(fileURL: imported.fileURL)
                        }.value
                        selectedElementID = try document.addImage(storedImage)
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

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            Button {
                do {
                    selectedElementID = try document.addText()
                } catch {
                    importErrorMessage = error.localizedDescription
                }
            } label: {
                Label("Add Text", systemImage: "text.badge.plus")
            }

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
            }
            .disabled(
                isImportingPhotos
                    || document.elements.count >= BookPageCapacityPolicy.maximumElementCount
                    || document.imageCount >= BookPageCapacityPolicy.maximumImageCount
                    || document.storedImageByteCount >= BookPageCapacityPolicy.maximumStoredImageByteCount
            )

            Spacer()

            if let selectedElementID {
                Button {
                    document.sendToBack(id: selectedElementID)
                } label: {
                    Image(systemName: "square.2.layers.3d.bottom.filled")
                }
                .accessibilityLabel("Send selected item to back")

                Button {
                    document.bringToFront(id: selectedElementID)
                } label: {
                    Image(systemName: "square.3.layers.3d.top.filled")
                }
                .accessibilityLabel("Bring selected item to front")

                Button(role: .destructive) {
                    document.deleteElement(id: selectedElementID)
                    self.selectedElementID = nil
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete selected item")
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var selectedElementInspector: some View {
        if let selectedElementID,
           let element = document.elements.first(where: { $0.id == selectedElementID }),
           case .text(let textContent) = element.content {
            VStack(alignment: .leading, spacing: 8) {
                Text("Text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: Binding(
                    get: {
                        guard let current = document.elements.first(where: { $0.id == selectedElementID }),
                              case .text(let content) = current.content else { return "" }
                        return content.text
                    },
                    set: {
                        if !document.updateText(id: selectedElementID, text: $0) {
                            importErrorMessage = BookPageCapacityError.maximumTextCharactersReached.localizedDescription
                        }
                    }
                ))
                .frame(minHeight: 72, maxHeight: 120)
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Selected text")

                HStack {
                    Text("Text size")
                    Slider(
                        value: Binding(
                            get: {
                                guard let current = document.elements.first(where: { $0.id == selectedElementID }),
                                      case .text(let content) = current.content else {
                                    return BookPageEditingPolicy.defaultFontSize
                                }
                                return content.fontSize
                            },
                            set: { document.updateFontSize(id: selectedElementID, fontSize: $0) }
                        ),
                        in: BookPageEditingPolicy.minimumFontSize...BookPageEditingPolicy.maximumFontSize
                    )
                    .accessibilityLabel("Text size")
                    Text("\(Int((textContent.fontSize * 612).rounded())) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                Picker(
                    "Alignment",
                    selection: Binding(
                        get: {
                            guard let current = document.elements.first(where: { $0.id == selectedElementID }),
                                  case .text(let content) = current.content else { return BookPageTextAlignment.leading }
                            return content.alignment
                        },
                        set: { document.updateTextAlignment(id: selectedElementID, alignment: $0) }
                    )
                ) {
                    ForEach(BookPageTextAlignment.allCases, id: \.self) { alignment in
                        Text(alignment.displayName).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
        } else if let selectedElementID,
                  let element = document.elements.first(where: { $0.id == selectedElementID }),
                  case .image = element.content {
            VStack(alignment: .leading, spacing: 8) {
                Text("Photo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker(
                    "Photo sizing",
                    selection: Binding(
                        get: {
                            guard let current = document.elements.first(where: { $0.id == selectedElementID }),
                                  case .image(let content) = current.content else { return BookPageImageFit.fill }
                            return content.fit
                        },
                        set: { document.updateImageFit(id: selectedElementID, fit: $0) }
                    )
                ) {
                    Text("Fit").tag(BookPageImageFit.fit)
                    Text("Fill").tag(BookPageImageFit.fill)
                }
                .pickerStyle(.segmented)

                TextField(
                    "Photo description",
                    text: Binding(
                        get: {
                            guard let current = document.elements.first(where: { $0.id == selectedElementID }),
                                  case .image(let content) = current.content else { return "" }
                            return content.accessibilityDescription
                        },
                        set: {
                            document.updateImageAccessibilityDescription(
                                id: selectedElementID,
                                description: $0
                            )
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Photo description")
            }
            .padding(.horizontal)
        } else {
            Text("Tap an item to move, resize, edit, reorder, or delete it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    private func editorElement(_ element: BookPageElement, canvasSize: CGSize) -> some View {
        let frame = element.frame
        let width = canvasSize.width * CGFloat(frame.width)
        let height = canvasSize.height * CGFloat(frame.height)
        let isSelected = selectedElementID == element.id

        let interactiveElement = AnyView(
            BookPageElementView(element: element)
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
                selectedElementID = element.id
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if moveStart?.id != element.id {
                            moveStart = (element.id, element.frame)
                            selectedElementID = element.id
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
                        moveStart = nil
                    }
            )
        )

        return interactiveElement
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: element))
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double tap to select. Use actions to arrange or delete this item.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: "Select") {
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
    }

    private func deleteElement(_ id: UUID) {
        document.deleteElement(id: id)
        guard selectedElementID == id else { return }
        selectedElementID = nil
    }

    private func selectionOverlay(
        for element: BookPageElement,
        canvasSize: CGSize
    ) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 2)
                .allowsHitTesting(false)

            ForEach(BookPageResizeHandle.allCases, id: \.self) { handle in
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .frame(width: 32, height: 32)
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
                            }
                    )
                    .accessibilityLabel("Resize \(handle.accessibilityName)")
                    .accessibilityHint("Drag to resize the selected item")
            }
        }
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
        switch handle {
        case .topLeading:
            return CGPoint(x: 0, y: 0)
        case .topTrailing:
            return CGPoint(x: elementSize.width, y: 0)
        case .bottomLeading:
            return CGPoint(x: 0, y: elementSize.height)
        case .bottomTrailing:
            return CGPoint(x: elementSize.width, y: elementSize.height)
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

struct BookPageDocumentView: View {
    let document: BookPageDocument

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.99, green: 0.98, blue: 0.95)
                ForEach(document.elements) { element in
                    BookPageElementView(element: element)
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

private struct BookPageElementView: View {
    let element: BookPageElement

    var body: some View {
        GeometryReader { geometry in
            switch element.content {
            case .text(let content):
                Text(content.text)
                    .font(.system(
                        size: max(
                            9,
                            geometry.size.height * CGFloat(content.fontSize / max(element.frame.height, 0.001))
                        ),
                        design: .serif
                    ))
                    .foregroundStyle(Color(red: 0.18, green: 0.16, blue: 0.14))
                    .multilineTextAlignment(content.alignment.swiftUIAlignment)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: content.alignment.frameAlignment)
                    .clipped()
            case .image(let image):
                if let uiImage = UIImage(data: image.jpegData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: image.fit == .fill ? .fill : .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .accessibilityLabel(image.accessibilityDescription)
                } else {
                    ZStack {
                        Color.secondary.opacity(0.10)
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

@MainActor
enum BookPagePrintRenderer {
    static func render(
        document: BookPageDocument,
        pixelSize: CGSize,
        memoryID: UUID? = nil
    ) -> UIImage? {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let page = BookPageDocumentView(document: document)
            .frame(width: pixelSize.width, height: pixelSize.height)
        let content: AnyView
        if let memoryID,
           memoryID != BookInteriorAnchor.titlePageMemoryId,
           memoryID != BookInteriorAnchor.closingPageMemoryId {
            content = AnyView(page.overlay(QRWatermark(memoryID: memoryID)))
        } else {
            content = AnyView(page)
        }
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
