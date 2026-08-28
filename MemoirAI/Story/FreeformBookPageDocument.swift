import Foundation
import ImageIO
import UIKit

struct NormalizedPageRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let defaultText = NormalizedPageRect(x: 0.10, y: 0.12, width: 0.80, height: 0.28)
    static let defaultImage = NormalizedPageRect(x: 0.15, y: 0.25, width: 0.70, height: 0.50)
}

enum BookPageResizeHandle: String, Codable, CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

enum BookPageTextAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

enum BookPageImageFit: String, Codable, CaseIterable, Sendable {
    case fit
    case fill
}

enum BookPageImageSource: String, Codable, Sendable {
    case aiGenerated
    case userPhoto
}

struct BookPageTextContent: Codable, Equatable, Sendable {
    var text: String
    var fontSize: Double
    var alignment: BookPageTextAlignment

    init(
        text: String,
        fontSize: Double = BookPageEditingPolicy.defaultFontSize,
        alignment: BookPageTextAlignment = .leading
    ) {
        self.text = text
        self.fontSize = BookPageEditingPolicy.clampedFontSize(fontSize)
        self.alignment = alignment
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case fontSize
        case alignment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedText = try container.decode(String.self, forKey: .text)
        guard BookPageEditingPolicy.acceptsText(decodedText) else {
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription: "Text box exceeds the character limit."
            )
        }
        text = decodedText
        fontSize = BookPageEditingPolicy.clampedFontSize(
            try container.decode(Double.self, forKey: .fontSize)
        )
        alignment = try container.decode(BookPageTextAlignment.self, forKey: .alignment)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(alignment, forKey: .alignment)
    }
}

struct BookPageStoredImage: Codable, Equatable, Sendable {
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    var accessibilityDescription: String
    var fit: BookPageImageFit
    var source: BookPageImageSource

    fileprivate init(
        jpegData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        accessibilityDescription: String = "Photo",
        fit: BookPageImageFit = .fill,
        source: BookPageImageSource = .userPhoto
    ) {
        self.jpegData = jpegData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.accessibilityDescription = accessibilityDescription
        self.fit = fit
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case jpegData
        case pixelWidth
        case pixelHeight
        case accessibilityDescription
        case fit
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decode(Data.self, forKey: .jpegData)
        let width = try container.decode(Int.self, forKey: .pixelWidth)
        let height = try container.decode(Int.self, forKey: .pixelHeight)

        guard data.count <= BookPageImagePreparation.maximumByteCount,
              width > 0,
              height > 0,
              max(width, height) <= BookPageImagePreparation.maximumPixelDimension,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let actualWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let actualHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              actualWidth == width,
              actualHeight == height,
              max(actualWidth, actualHeight) <= BookPageImagePreparation.maximumPixelDimension else {
            throw DecodingError.dataCorruptedError(
                forKey: .jpegData,
                in: container,
                debugDescription: "Stored page image exceeds its byte or pixel limit."
            )
        }

        jpegData = data
        pixelWidth = width
        pixelHeight = height
        accessibilityDescription = try container.decode(String.self, forKey: .accessibilityDescription)
        fit = try container.decode(BookPageImageFit.self, forKey: .fit)
        source = try container.decodeIfPresent(BookPageImageSource.self, forKey: .source) ?? .userPhoto
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jpegData, forKey: .jpegData)
        try container.encode(pixelWidth, forKey: .pixelWidth)
        try container.encode(pixelHeight, forKey: .pixelHeight)
        try container.encode(accessibilityDescription, forKey: .accessibilityDescription)
        try container.encode(fit, forKey: .fit)
        try container.encode(source, forKey: .source)
    }
}

struct BookPageElement: Codable, Equatable, Identifiable, Sendable {
    enum Content: Equatable, Sendable {
        case text(BookPageTextContent)
        case image(BookPageStoredImage)
    }

    let id: UUID
    var frame: NormalizedPageRect
    var content: Content

    init(id: UUID = UUID(), frame: NormalizedPageRect, content: Content) {
        self.id = id
        self.frame = BookPageEditingPolicy.clamped(frame)
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case frame
        case type
        case text
        case image
    }

    private enum ElementType: String, Codable {
        case text
        case image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        frame = BookPageEditingPolicy.clamped(
            try container.decode(NormalizedPageRect.self, forKey: .frame)
        )

        switch try container.decode(ElementType.self, forKey: .type) {
        case .text:
            content = .text(try container.decode(BookPageTextContent.self, forKey: .text))
        case .image:
            content = .image(try container.decode(BookPageStoredImage.self, forKey: .image))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(frame, forKey: .frame)

        switch content {
        case .text(let text):
            try container.encode(ElementType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let image):
            try container.encode(ElementType.image, forKey: .type)
            try container.encode(image, forKey: .image)
        }
    }
}

struct BookPageDocument: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let id: UUID
    private(set) var schemaVersion: Int
    var pageAspectRatio: Double
    private(set) var elements: [BookPageElement]

    init(
        id: UUID = UUID(),
        pageAspectRatio: Double = 11.0 / 8.5
    ) {
        self.id = id
        schemaVersion = Self.currentSchemaVersion
        self.pageAspectRatio = pageAspectRatio.isFinite && pageAspectRatio > 0 ? pageAspectRatio : 11.0 / 8.5
        elements = []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case pageAspectRatio
        case elements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard (1...Self.currentSchemaVersion).contains(decodedSchemaVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported book page schema version \(decodedSchemaVersion)."
            )
        }

        let decodedAspectRatio = try container.decode(Double.self, forKey: .pageAspectRatio)
        guard decodedAspectRatio.isFinite, decodedAspectRatio > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .pageAspectRatio,
                in: container,
                debugDescription: "Page aspect ratio must be finite and greater than zero."
            )
        }

        id = try container.decode(UUID.self, forKey: .id)
        schemaVersion = decodedSchemaVersion
        pageAspectRatio = decodedAspectRatio
        let decodedElements = try container.decode([BookPageElement].self, forKey: .elements)
        var elementCount = 0
        var imageCount = 0
        var storedImageByteCount = 0
        var storedImagePixelCount = 0

        do {
            for element in decodedElements {
                let newImageByteCount: Int?
                if case .image(let image) = element.content {
                    newImageByteCount = image.jpegData.count
                } else {
                    newImageByteCount = nil
                }
                try BookPageCapacityPolicy.validateAddition(
                    currentElementCount: elementCount,
                    currentImageCount: imageCount,
                    currentStoredImageByteCount: storedImageByteCount,
                    newImageByteCount: newImageByteCount,
                    currentStoredImagePixelCount: storedImagePixelCount,
                    newImagePixelCount: newImageByteCount == nil ? nil : element.imagePixelCount
                )
                elementCount += 1
                if let newImageByteCount {
                    imageCount += 1
                    storedImageByteCount += newImageByteCount
                    storedImagePixelCount += element.imagePixelCount
                }
            }
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .elements,
                in: container,
                debugDescription: error.localizedDescription
            )
        }
        elements = decodedElements
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(pageAspectRatio, forKey: .pageAspectRatio)
        try container.encode(elements, forKey: .elements)
    }

    @discardableResult
    mutating func addText(
        _ text: String = "Add your story",
        frame: NormalizedPageRect? = nil
    ) throws -> UUID {
        guard BookPageEditingPolicy.acceptsText(text) else {
            throw BookPageCapacityError.maximumTextCharactersReached
        }
        try BookPageCapacityPolicy.validateAddition(
            currentElementCount: elements.count,
            currentImageCount: imageCount,
            currentStoredImageByteCount: storedImageByteCount,
            newImageByteCount: nil,
            currentStoredImagePixelCount: storedImagePixelCount
        )
        let element = BookPageElement(
            frame: frame ?? BookPageEditingPolicy.staggeredDefaultTextFrame(existingElementCount: elements.count),
            content: .text(BookPageTextContent(text: text))
        )
        elements.append(element)
        return element.id
    }

    @discardableResult
    mutating func addImage(
        _ image: BookPageStoredImage,
        frame: NormalizedPageRect? = nil
    ) throws -> UUID {
        try BookPageCapacityPolicy.validateAddition(
            currentElementCount: elements.count,
            currentImageCount: imageCount,
            currentStoredImageByteCount: storedImageByteCount,
            newImageByteCount: image.jpegData.count,
            currentStoredImagePixelCount: storedImagePixelCount,
            newImagePixelCount: image.pixelCount
        )
        let element = BookPageElement(
            frame: frame ?? BookPageEditingPolicy.staggeredDefaultImageFrame(existingImageCount: imageCount),
            content: .image(image)
        )
        elements.append(element)
        return element.id
    }

    mutating func deleteElement(id: UUID) {
        elements.removeAll { $0.id == id }
    }

    mutating func bringToFront(id: UUID) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        elements.append(elements.remove(at: index))
    }

    mutating func sendToBack(id: UUID) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        elements.insert(elements.remove(at: index), at: 0)
    }

    mutating func moveElement(
        id: UUID,
        startingAt startingFrame: NormalizedPageRect? = nil,
        normalizedTranslation: CGSize
    ) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[index].frame = BookPageEditingPolicy.moved(
            startingFrame ?? elements[index].frame,
            normalizedTranslation: normalizedTranslation
        )
    }

    mutating func resizeElement(
        id: UUID,
        startingAt startingFrame: NormalizedPageRect? = nil,
        handle: BookPageResizeHandle,
        normalizedTranslation: CGSize
    ) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[index].frame = BookPageEditingPolicy.resized(
            startingFrame ?? elements[index].frame,
            handle: handle,
            normalizedTranslation: normalizedTranslation
        )
    }

    @discardableResult
    mutating func updateText(id: UUID, text: String) -> Bool {
        guard BookPageEditingPolicy.acceptsText(text) else { return false }
        guard let index = elements.firstIndex(where: { $0.id == id }),
              case .text(var content) = elements[index].content else { return false }
        content.text = text
        elements[index].content = .text(content)
        return true
    }

    mutating func replaceText(matching oldValue: String, with newValue: String) {
        let oldTrimmed = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldTrimmed.isEmpty else { return }
        for index in elements.indices {
            guard case .text(var content) = elements[index].content,
                  content.text.trimmingCharacters(in: .whitespacesAndNewlines) == oldTrimmed else {
                continue
            }
            guard BookPageEditingPolicy.acceptsText(newValue) else { continue }
            content.text = newValue
            elements[index].content = .text(content)
        }
    }

    mutating func updateFontSize(id: UUID, fontSize: Double) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              case .text(var content) = elements[index].content else { return }
        content.fontSize = BookPageEditingPolicy.clampedFontSize(fontSize)
        elements[index].content = .text(content)
    }

    mutating func updateTextAlignment(id: UUID, alignment: BookPageTextAlignment) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              case .text(var content) = elements[index].content else { return }
        content.alignment = alignment
        elements[index].content = .text(content)
    }

    mutating func updateImageFit(id: UUID, fit: BookPageImageFit) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              case .image(var content) = elements[index].content else { return }
        content.fit = fit
        elements[index].content = .image(content)
    }

    mutating func updateImageAccessibilityDescription(id: UUID, description: String) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              case .image(var content) = elements[index].content else { return }
        content.accessibilityDescription = String(description.prefix(240))
        elements[index].content = .image(content)
    }

    @discardableResult
    mutating func replaceFirstImage(
        from source: BookPageImageSource,
        with replacement: BookPageStoredImage
    ) throws -> Bool {
        guard let index = elements.firstIndex(where: {
            guard case .image(let image) = $0.content else { return false }
            return image.source == source
        }) else { return false }
        guard case .image(let existing) = elements[index].content else { return false }
        let replacedByteCount = storedImageByteCount - existing.jpegData.count + replacement.jpegData.count
        guard replacedByteCount <= BookPageCapacityPolicy.maximumStoredImageByteCount else {
            throw BookPageCapacityError.maximumStoredImageBytesReached
        }
        let replacedPixelCount = storedImagePixelCount - existing.pixelCount + replacement.pixelCount
        guard replacedPixelCount <= BookPageCapacityPolicy.maximumStoredImagePixelCount else {
            throw BookPageCapacityError.maximumStoredImagePixelsReached
        }
        var preserved = replacement
        preserved.fit = existing.fit
        preserved.accessibilityDescription = existing.accessibilityDescription
        elements[index].content = .image(preserved)
        return true
    }

    func containsImage(from source: BookPageImageSource) -> Bool {
        elements.contains { element in
            guard case .image(let image) = element.content else { return false }
            return image.source == source
        }
    }

    var imageCount: Int {
        elements.reduce(into: 0) { count, element in
            if case .image = element.content {
                count += 1
            }
        }
    }

    var storedImageByteCount: Int {
        elements.reduce(into: 0) { byteCount, element in
            if case .image(let image) = element.content {
                byteCount += image.jpegData.count
            }
        }
    }

    var storedImagePixelCount: Int {
        elements.reduce(into: 0) { pixelCount, element in
            pixelCount += element.imagePixelCount
        }
    }

    func storedImageData(from source: BookPageImageSource) -> Data? {
        for element in elements {
            if case .image(let image) = element.content,
               image.source == source {
                return image.jpegData
            }
        }
        return nil
    }
}

private extension BookPageElement {
    var imagePixelCount: Int {
        guard case .image(let image) = content else { return 0 }
        return image.pixelCount
    }
}

private extension BookPageStoredImage {
    var pixelCount: Int { pixelWidth * pixelHeight }
}

enum BookPageCapacityError: LocalizedError, Equatable {
    case maximumElementsReached
    case maximumImagesReached
    case maximumStoredImageBytesReached
    case maximumStoredImagePixelsReached
    case maximumTextCharactersReached

    var errorDescription: String? {
        switch self {
        case .maximumElementsReached:
            return "This page already has the maximum of \(BookPageCapacityPolicy.maximumElementCount) items."
        case .maximumImagesReached:
            return "This page already has the maximum of \(BookPageCapacityPolicy.maximumImageCount) photos."
        case .maximumStoredImageBytesReached:
            return "These photos would make the page too large. Remove a photo or choose a smaller one."
        case .maximumStoredImagePixelsReached:
            return "These photos need too much memory for one page. Remove a photo or choose smaller photos."
        case .maximumTextCharactersReached:
            return "A text box can contain up to \(BookPageEditingPolicy.maximumTextCharacterCount) characters. Shorten the text and try again."
        }
    }
}

enum BookPageCapacityPolicy {
    static let maximumElementCount = 80
    static let maximumImageCount = 24
    static let maximumStoredImageByteCount = 24_000_000
    static let maximumStoredImagePixelCount = 12_000_000
    /// Allows JSON/Base64 overhead above the compressed image byte cap.
    static let maximumEncodedDocumentByteCount = 34_000_000

    static func validateAddition(
        currentElementCount: Int,
        currentImageCount: Int,
        currentStoredImageByteCount: Int,
        newImageByteCount: Int?,
        currentStoredImagePixelCount: Int = 0,
        newImagePixelCount: Int? = nil
    ) throws {
        guard currentElementCount < maximumElementCount else {
            throw BookPageCapacityError.maximumElementsReached
        }
        guard let newImageByteCount else { return }
        guard currentImageCount < maximumImageCount else {
            throw BookPageCapacityError.maximumImagesReached
        }
        guard newImageByteCount >= 0,
              currentStoredImageByteCount >= 0,
              newImageByteCount <= maximumStoredImageByteCount - currentStoredImageByteCount else {
            throw BookPageCapacityError.maximumStoredImageBytesReached
        }
        guard let newImagePixelCount else { return }
        guard newImagePixelCount >= 0,
              currentStoredImagePixelCount >= 0,
              newImagePixelCount <= maximumStoredImagePixelCount - currentStoredImagePixelCount else {
            throw BookPageCapacityError.maximumStoredImagePixelsReached
        }
    }
}

enum BookPageCollectionCapacityPolicy {
    static let maximumStoredImageByteCount = 46_000_000
    static let maximumStoredImagePixelCount = 48_000_000

    static func accepts(_ documents: some Sequence<BookPageDocument>) -> Bool {
        var byteCount = 0
        var pixelCount = 0
        for document in documents {
            let documentBytes = document.storedImageByteCount
            let documentPixels = document.storedImagePixelCount
            guard documentBytes <= maximumStoredImageByteCount - byteCount,
                  documentPixels <= maximumStoredImagePixelCount - pixelCount else {
                return false
            }
            byteCount += documentBytes
            pixelCount += documentPixels
        }
        return true
    }
}

enum BookPageDocumentDownloadPolicy {
    static func accepts(url: URL, statusCode: Int, fileByteCount: Int) -> Bool {
        url.scheme?.lowercased() == "https"
            && (200...299).contains(statusCode)
            && fileByteCount > 0
            && fileByteCount <= BookPageCapacityPolicy.maximumEncodedDocumentByteCount
    }
}

enum BookPageEditorPersistenceError: LocalizedError {
    case pageChanged
    case cloudLayoutUnavailable
    case documentTooLarge
    case bookTooLarge
    case arrangedPagesMustReset
    case editingUnavailable
    case textTooLong
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .pageChanged:
            return "That page changed while the editor was opening. Open it again and retry."
        case .cloudLayoutUnavailable:
            return "This page’s editable layout could not be downloaded. Check your connection and reopen the book before editing."
        case .documentTooLarge:
            return "This page is too large to save. Remove a photo or shorten a text box."
        case .bookTooLarge:
            return "This book has reached its photo limit. Remove a photo from another page before adding more."
        case .arrangedPagesMustReset:
            return "Reset this memory’s arranged pages before changing its flowing text."
        case .editingUnavailable:
            return "Wait for this book to finish loading or saving, then try the edit again."
        case .textTooLong:
            return "A memory can contain up to 40,000 characters. Shorten the text before saving."
        case .saveFailed:
            return "This edit could not be published. Check your connection and tap Save again."
        }
    }
}

enum BookPageEditingPolicy {
    static let maximumTextCharacterCount = 20_000
    static let minimumWidth = 0.08
    static let minimumHeight = 0.06
    static let minimumFontSize = 0.015
    static let maximumFontSize = 0.12
    static let defaultFontSize = 0.038

    static func staggeredDefaultTextFrame(existingElementCount: Int) -> NormalizedPageRect {
        staggered(.defaultText, index: existingElementCount)
    }

    static func staggeredDefaultImageFrame(existingImageCount: Int) -> NormalizedPageRect {
        staggered(.defaultImage, index: existingImageCount)
    }

    static func clamped(_ rect: NormalizedPageRect) -> NormalizedPageRect {
        let width = clamp(finite(rect.width, fallback: minimumWidth), minimumWidth, 1)
        let height = clamp(finite(rect.height, fallback: minimumHeight), minimumHeight, 1)
        let x = clamp(finite(rect.x, fallback: 0), 0, 1 - width)
        let y = clamp(finite(rect.y, fallback: 0), 0, 1 - height)
        return NormalizedPageRect(x: x, y: y, width: width, height: height)
    }

    static func moved(
        _ rect: NormalizedPageRect,
        normalizedTranslation: CGSize
    ) -> NormalizedPageRect {
        let source = clamped(rect)
        return clamped(
            NormalizedPageRect(
                x: source.x + finite(normalizedTranslation.width, fallback: 0),
                y: source.y + finite(normalizedTranslation.height, fallback: 0),
                width: source.width,
                height: source.height
            )
        )
    }

    static func resized(
        _ rect: NormalizedPageRect,
        handle: BookPageResizeHandle,
        normalizedTranslation: CGSize
    ) -> NormalizedPageRect {
        let source = clamped(rect)
        let dx = finite(normalizedTranslation.width, fallback: 0)
        let dy = finite(normalizedTranslation.height, fallback: 0)
        let left = source.x
        let top = source.y
        let right = source.x + source.width
        let bottom = source.y + source.height

        var newLeft = left
        var newTop = top
        var newRight = right
        var newBottom = bottom

        switch handle {
        case .topLeading:
            newLeft = clamp(left + dx, 0, right - minimumWidth)
            newTop = clamp(top + dy, 0, bottom - minimumHeight)
        case .topTrailing:
            newRight = clamp(right + dx, left + minimumWidth, 1)
            newTop = clamp(top + dy, 0, bottom - minimumHeight)
        case .bottomLeading:
            newLeft = clamp(left + dx, 0, right - minimumWidth)
            newBottom = clamp(bottom + dy, top + minimumHeight, 1)
        case .bottomTrailing:
            newRight = clamp(right + dx, left + minimumWidth, 1)
            newBottom = clamp(bottom + dy, top + minimumHeight, 1)
        }

        return NormalizedPageRect(
            x: newLeft,
            y: newTop,
            width: newRight - newLeft,
            height: newBottom - newTop
        )
    }

    static func clampedFontSize(_ fontSize: Double) -> Double {
        clamp(finite(fontSize, fallback: defaultFontSize), minimumFontSize, maximumFontSize)
    }

    static func acceptsText(_ text: String) -> Bool {
        text.count <= maximumTextCharacterCount
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    private static func finite(_ value: CGFloat, fallback: Double) -> Double {
        value.isFinite ? Double(value) : fallback
    }

    private static func clamp(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }

    private static func staggered(_ frame: NormalizedPageRect, index: Int) -> NormalizedPageRect {
        let safeIndex = max(index, 0) % 6
        let offset = Double(safeIndex) * 0.025
        return clamped(
            NormalizedPageRect(
                x: frame.x + offset,
                y: frame.y + offset,
                width: frame.width,
                height: frame.height
            )
        )
    }
}

enum BookPageImagePreparationError: LocalizedError {
    case invalidImage
    case couldNotCompress

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "That file is not a supported image."
        case .couldNotCompress:
            return "That photo could not be prepared without exceeding the page limit."
        }
    }
}

enum BookPageImagePreparation {
    static let maximumPixelDimension = 3_000
    static let maximumByteCount = 3_000_000
    static let minimumPixelDimension = 320
    static let maximumSourceFileByteCount = 100 * 1024 * 1024

    static func prepareForStorage(
        fileURL: URL,
        accessibilityDescription: String = "Photo",
        fit: BookPageImageFit = .fill,
        source: BookPageImageSource = .userPhoto
    ) throws -> BookPageStoredImage {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= maximumSourceFileByteCount,
              let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            throw BookPageImagePreparationError.invalidImage
        }
        return try prepareForStorage(
            imageSource: imageSource,
            accessibilityDescription: accessibilityDescription,
            fit: fit,
            source: source
        )
    }

    static func prepareForStorage(
        _ sourceData: Data,
        accessibilityDescription: String = "Photo",
        fit: BookPageImageFit = .fill,
        source: BookPageImageSource = .userPhoto
    ) throws -> BookPageStoredImage {
        guard let imageSource = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            throw BookPageImagePreparationError.invalidImage
        }
        return try prepareForStorage(
            imageSource: imageSource,
            accessibilityDescription: accessibilityDescription,
            fit: fit,
            source: source
        )
    }

    private static func prepareForStorage(
        imageSource: CGImageSource,
        accessibilityDescription: String,
        fit: BookPageImageFit,
        source: BookPageImageSource
    ) throws -> BookPageStoredImage {
        guard let sourceProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let sourceWidth = sourceProperties[kCGImagePropertyPixelWidth] as? Int,
              let sourceHeight = sourceProperties[kCGImagePropertyPixelHeight] as? Int,
              sourceWidth > 0,
              sourceHeight > 0 else {
            throw BookPageImagePreparationError.invalidImage
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw BookPageImagePreparationError.invalidImage
        }

        var image = UIImage(cgImage: thumbnail)
        let qualities: [CGFloat] = [0.88, 0.76, 0.64, 0.52, 0.40, 0.30]
        var lastEncodedByteCount = maximumByteCount + 1

        while true {
            for quality in qualities {
                guard let data = image.jpegData(compressionQuality: quality) else { continue }
                lastEncodedByteCount = data.count
                if data.count <= maximumByteCount {
                    return BookPageStoredImage(
                        jpegData: data,
                        pixelWidth: Int(image.size.width.rounded()),
                        pixelHeight: Int(image.size.height.rounded()),
                        accessibilityDescription: accessibilityDescription,
                        fit: fit,
                        source: source
                    )
                }
            }

            let longestSide = max(image.size.width, image.size.height)
            guard longestSide > CGFloat(minimumPixelDimension) else {
                throw BookPageImagePreparationError.couldNotCompress
            }

            let reduction = max(
                0.5,
                min(0.82, sqrt(CGFloat(maximumByteCount) / CGFloat(max(lastEncodedByteCount, 1))) * 0.9)
            )
            let targetLongestSide = max(CGFloat(minimumPixelDimension), longestSide * reduction)
            image = resized(image, maximumPixelDimension: targetLongestSide)
        }
    }

    private static func resized(_ image: UIImage, maximumPixelDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maximumPixelDimension, longestSide > 0 else { return image }

        let scale = maximumPixelDimension / longestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
