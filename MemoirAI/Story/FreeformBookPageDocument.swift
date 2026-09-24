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

enum BookPageTextRole: String, Codable, Sendable {
    case custom
    case title
    case subtitle
    case body
}

enum BookPageTextColor: String, Codable, Sendable {
    case ink
    case brown
    case mutedBrown
    case white
}

enum BookPageTypographyPreset: String, Codable, Sendable {
    case kidsBook
    case comic
    case realistic
    case custom
}

enum BookInteriorTitleTypography: Equatable, Sendable {
    case rounded
    case editorial
}

extension BookPageTypographyPreset {
    var interiorTitleTypography: BookInteriorTitleTypography {
        self == .kidsBook ? .rounded : .editorial
    }
}

enum BookPageSemanticTemplate: String, Codable, Sendable {
    case interiorTitle
    case interiorClosing
}

enum BookPageImageFit: String, Codable, CaseIterable, Sendable {
    case fit
    case fill
}

struct BookPageCanonicalIllustrationLayout: Equatable, Sendable {
    let imageFrame: NormalizedPageRect
    let titleFrame: NormalizedPageRect?
    let imageFit: BookPageImageFit
}

struct BookPageCanonicalTextLayout: Equatable, Sendable {
    let titleFrame: NormalizedPageRect?
    let subtitleFrame: NormalizedPageRect?
    let bodyFrame: NormalizedPageRect
}

enum BookPageCanonicalLayout {
    static func illustration(isLandscape: Bool, isPrecomposed: Bool) -> BookPageCanonicalIllustrationLayout {
        if isPrecomposed {
            return BookPageCanonicalIllustrationLayout(
                imageFrame: NormalizedPageRect(x: 0, y: 0, width: 1, height: 1),
                titleFrame: nil,
                imageFit: .fill
            )
        }
        if isLandscape {
            return BookPageCanonicalIllustrationLayout(
                imageFrame: NormalizedPageRect(x: 0, y: 0.065, width: 1, height: 0.935),
                titleFrame: NormalizedPageRect(x: 0.08, y: 0, width: 0.72, height: 0.065),
                imageFit: .fill
            )
        }
        return BookPageCanonicalIllustrationLayout(
            imageFrame: NormalizedPageRect(x: 0.06, y: 0.10, width: 0.88, height: 0.78),
            titleFrame: NormalizedPageRect(x: 0.06, y: 0, width: 0.78, height: 0.065),
            imageFit: .fit
        )
    }

    static func text(isLandscape: Bool, hasTitle: Bool, hasSubtitle: Bool) -> BookPageCanonicalTextLayout {
        if isLandscape {
            return BookPageCanonicalTextLayout(
                titleFrame: hasTitle
                    ? NormalizedPageRect(x: 0.085, y: 0.085, width: 0.72, height: 0.07)
                    : nil,
                subtitleFrame: nil,
                bodyFrame: NormalizedPageRect(x: 0.085, y: 0.18, width: 0.81, height: 0.755)
            )
        }
        let titleFrame = hasTitle
            ? NormalizedPageRect(x: 0.06, y: 0.05, width: 0.84, height: 0.07)
            : nil
        let subtitleFrame = hasSubtitle
            ? NormalizedPageRect(x: 0.06, y: hasTitle ? 0.125 : 0.05, width: 0.84, height: 0.045)
            : nil
        let bodyTop = hasSubtitle ? (hasTitle ? 0.18 : 0.11) : (hasTitle ? 0.13 : 0.05)
        return BookPageCanonicalTextLayout(
            titleFrame: titleFrame,
            subtitleFrame: subtitleFrame,
            bodyFrame: NormalizedPageRect(x: 0.06, y: bodyTop, width: 0.84, height: min(0.75, 0.92 - bodyTop))
        )
    }
}

enum BookPageTextSizing {
    static func pointSize(for content: BookPageTextContent, pageHeight: CGFloat) -> CGFloat {
        pageHeight * CGFloat(content.fontSize)
    }
}

enum BookInteriorPageDocumentFactory {
    static let semanticTemplateVersion = 3

    struct Layout: Equatable, Sendable {
        let titleFrame: NormalizedPageRect
        let titleBodyFrame: NormalizedPageRect
        let titleFontSize: Double
        let titleBodyFontSize: Double
        let closingIconFrame: NormalizedPageRect
        let closingHeadingFrame: NormalizedPageRect
        let closingBadgeFrame: NormalizedPageRect
        let closingStoreTextFrame: NormalizedPageRect
        let closingHeadingFontSize: Double
        let closingStoreFontSize: Double
    }

    static func layout(pageAspectRatio: Double, isKidsBook: Bool) -> Layout {
        let isLandscape = pageAspectRatio > 1
        if isLandscape {
            return Layout(
                titleFrame: NormalizedPageRect(x: 0.11, y: 0.29, width: 0.78, height: 0.17),
                titleBodyFrame: NormalizedPageRect(x: 0.19, y: 0.52, width: 0.62, height: 0.09),
                titleFontSize: isKidsBook ? 0.09 : 0.085,
                titleBodyFontSize: 0.036,
                closingIconFrame: NormalizedPageRect(x: 0.455, y: 0.235, width: 0.09, height: 0.12),
                closingHeadingFrame: NormalizedPageRect(x: 0.20, y: 0.39, width: 0.60, height: 0.09),
                closingBadgeFrame: NormalizedPageRect(x: 0.335, y: 0.515, width: 0.33, height: 0.105),
                closingStoreTextFrame: NormalizedPageRect(x: 0.39, y: 0.535, width: 0.25, height: 0.065),
                closingHeadingFontSize: 0.052,
                closingStoreFontSize: 0.024
            )
        }
        return Layout(
            titleFrame: NormalizedPageRect(x: 0.10, y: 0.30, width: 0.80, height: 0.18),
            titleBodyFrame: NormalizedPageRect(x: 0.16, y: 0.53, width: 0.68, height: 0.10),
            titleFontSize: isKidsBook ? 0.078 : 0.074,
            titleBodyFontSize: 0.032,
            closingIconFrame: NormalizedPageRect(x: 0.43, y: 0.235, width: 0.14, height: 0.11),
            closingHeadingFrame: NormalizedPageRect(x: 0.15, y: 0.38, width: 0.70, height: 0.08),
            closingBadgeFrame: NormalizedPageRect(x: 0.255, y: 0.495, width: 0.49, height: 0.085),
            closingStoreTextFrame: NormalizedPageRect(x: 0.34, y: 0.507, width: 0.36, height: 0.06),
            closingHeadingFontSize: 0.044,
            closingStoreFontSize: 0.021
        )
    }

    static func requiresSemanticMigration(memoryID: UUID, document: BookPageDocument) -> Bool {
        let expectedTemplate: BookPageSemanticTemplate
        let requiredRoles: Set<BookPageTextRole>
        if memoryID == BookInteriorAnchor.titlePageMemoryId {
            expectedTemplate = .interiorTitle
            requiredRoles = [.title, .body]
        } else if memoryID == BookInteriorAnchor.closingPageMemoryId {
            expectedTemplate = .interiorClosing
            requiredRoles = [.title, .body]
        } else {
            return false
        }

        let roles = Set(document.elements.compactMap { element -> BookPageTextRole? in
            guard case .text(let text) = element.content else { return nil }
            return text.role
        })
        return document.semanticTemplate != expectedTemplate ||
            document.semanticTemplateVersion != semanticTemplateVersion ||
            !requiredRoles.isSubset(of: roles)
    }

    static func expectedTemplate(for memoryID: UUID) -> BookPageSemanticTemplate? {
        if memoryID == BookInteriorAnchor.titlePageMemoryId {
            return .interiorTitle
        }
        if memoryID == BookInteriorAnchor.closingPageMemoryId {
            return .interiorClosing
        }
        return nil
    }

    static func make(
        memoryID: UUID,
        title: String?,
        body: String,
        subtitle: String?,
        pageAspectRatio: Double,
        typographyPreset: BookPageTypographyPreset,
        isKidsBook: Bool,
        background: BookPageStoredImage?,
        preservingEditableElementsFrom legacyDocument: BookPageDocument? = nil
    ) throws -> BookPageDocument {
        let layout = layout(pageAspectRatio: pageAspectRatio, isKidsBook: isKidsBook)
        var document = BookPageDocument(
            pageAspectRatio: pageAspectRatio,
            semanticTemplate: expectedTemplate(for: memoryID),
            semanticTemplateVersion: expectedTemplate(for: memoryID) == nil ? nil : semanticTemplateVersion
        )
        if let background {
            _ = try document.addImage(
                background,
                frame: NormalizedPageRect(x: 0, y: 0, width: 1, height: 1)
            )
        }

        if memoryID == BookInteriorAnchor.titlePageMemoryId {
            if let preservedTitle = canonicalElementToPreserve(
                in: legacyDocument,
                role: .title,
                pageAspectRatio: pageAspectRatio,
                isKidsBook: isKidsBook,
                typographyPreset: typographyPreset
            ) {
                try document.appendPreservingIdentity(preservedTitle)
            } else {
                let titleID = try document.addText(
                    canonicalText(in: legacyDocument, role: .title)
                        ?? nonempty(title, fallback: "Memoir"),
                    frame: layout.titleFrame,
                    role: .title,
                    typographyPreset: typographyPreset
                )
                document.updateFontSize(id: titleID, fontSize: layout.titleFontSize)
                document.updateTextAlignment(id: titleID, alignment: .center)
            }

            let trimmedBody = (canonicalText(in: legacyDocument, role: .body) ?? body)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBody.isEmpty {
                if let preservedBody = canonicalElementToPreserve(
                    in: legacyDocument,
                    role: .body,
                    pageAspectRatio: pageAspectRatio,
                    isKidsBook: isKidsBook,
                    typographyPreset: typographyPreset
                ) {
                    try document.appendPreservingIdentity(preservedBody)
                } else {
                    let bodyID = try document.addText(
                        trimmedBody,
                        frame: layout.titleBodyFrame,
                        role: .body,
                        typographyPreset: typographyPreset
                    )
                    document.updateFontSize(id: bodyID, fontSize: layout.titleBodyFontSize)
                    document.updateTextAlignment(id: bodyID, alignment: .center)
                }
            }
        } else if memoryID == BookInteriorAnchor.closingPageMemoryId {
            if let preservedHeading = canonicalElementToPreserve(
                in: legacyDocument,
                role: .title,
                pageAspectRatio: pageAspectRatio,
                isKidsBook: isKidsBook,
                typographyPreset: typographyPreset
            ) {
                try document.appendPreservingIdentity(preservedHeading)
            } else {
                let headingID = try document.addText(
                    canonicalText(in: legacyDocument, role: .title)
                        ?? nonempty(title, fallback: "Made with Memoir"),
                    frame: layout.closingHeadingFrame,
                    role: .title,
                    typographyPreset: typographyPreset
                )
                document.updateFontSize(id: headingID, fontSize: layout.closingHeadingFontSize)
                document.updateTextAlignment(id: headingID, alignment: .center)
            }

            if let preservedStoreText = canonicalElementToPreserve(
                in: legacyDocument,
                role: .body,
                pageAspectRatio: pageAspectRatio,
                isKidsBook: isKidsBook,
                typographyPreset: typographyPreset
            ) {
                try document.appendPreservingIdentity(preservedStoreText)
            } else {
                let storeID = try document.addText(
                    canonicalText(in: legacyDocument, role: .body)
                        ?? "Download on the App Store",
                    frame: layout.closingStoreTextFrame,
                    role: .body,
                    typographyPreset: typographyPreset,
                    color: .white
                )
                document.updateFontSize(id: storeID, fontSize: layout.closingStoreFontSize)
                document.updateTextAlignment(id: storeID, alignment: .center)
            }

        }

        if let legacyDocument {
            try appendEditableElements(from: legacyDocument, to: &document)
        }
        return document
    }

    private static func nonempty(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func canonicalText(
        in document: BookPageDocument?,
        role: BookPageTextRole
    ) -> String? {
        guard let document,
              document.semanticTemplate != nil else { return nil }
        return document.elements.lazy.compactMap { element -> String? in
            guard case .text(let text) = element.content,
                  text.role == role else { return nil }
            let trimmed = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : text.text
        }.first
    }

    private static func canonicalElementToPreserve(
        in document: BookPageDocument?,
        role: BookPageTextRole,
        pageAspectRatio: Double,
        isKidsBook: Bool,
        typographyPreset: BookPageTypographyPreset
    ) -> BookPageElement? {
        guard let document,
              let semanticTemplate = document.semanticTemplate,
              let element = document.elements.first(where: { element in
                  guard case .text(let text) = element.content else { return false }
                  return text.role == role
              }),
              case .text(let text) = element.content else {
            return nil
        }
        guard document.semanticTemplateVersion == 2 else { return element }

        let oldLayout = legacyVersionTwoLayout(
            pageAspectRatio: pageAspectRatio,
            isKidsBook: isKidsBook
        )
        let expectedFrame: NormalizedPageRect
        let expectedFontSize: Double
        let expectedColor: BookPageTextColor?
        switch (semanticTemplate, role) {
        case (.interiorTitle, .title):
            expectedFrame = oldLayout.titleFrame
            expectedFontSize = oldLayout.titleFontSize
            expectedColor = nil
        case (.interiorTitle, .body):
            expectedFrame = oldLayout.titleBodyFrame
            expectedFontSize = oldLayout.titleBodyFontSize
            expectedColor = nil
        case (.interiorClosing, .title):
            expectedFrame = oldLayout.closingHeadingFrame
            expectedFontSize = oldLayout.closingHeadingFontSize
            expectedColor = nil
        case (.interiorClosing, .body):
            expectedFrame = oldLayout.closingStoreTextFrame
            expectedFontSize = oldLayout.closingStoreFontSize
            expectedColor = .white
        default:
            return element
        }

        let matchesOldDefault = element.frame == expectedFrame
            && text.fontSize == expectedFontSize
            && text.alignment == .center
            && text.color == expectedColor
            && text.typographyPreset == typographyPreset
        return matchesOldDefault ? nil : element
    }

    private static func legacyVersionTwoLayout(
        pageAspectRatio: Double,
        isKidsBook: Bool
    ) -> Layout {
        if pageAspectRatio > 1 {
            return Layout(
                titleFrame: NormalizedPageRect(x: 0.09, y: 0.27, width: 0.82, height: 0.20),
                titleBodyFrame: NormalizedPageRect(x: 0.16, y: 0.51, width: 0.68, height: 0.13),
                titleFontSize: isKidsBook ? 0.115 : 0.10,
                titleBodyFontSize: 0.043,
                closingIconFrame: NormalizedPageRect(x: 0.45, y: 0.22, width: 0.10, height: 0.13),
                closingHeadingFrame: NormalizedPageRect(x: 0.20, y: 0.405, width: 0.60, height: 0.12),
                closingBadgeFrame: NormalizedPageRect(x: 0.325, y: 0.585, width: 0.35, height: 0.105),
                closingStoreTextFrame: NormalizedPageRect(x: 0.385, y: 0.602, width: 0.255, height: 0.07),
                closingHeadingFontSize: 0.058,
                closingStoreFontSize: 0.027
            )
        }
        return Layout(
            titleFrame: NormalizedPageRect(x: 0.09, y: 0.30, width: 0.82, height: 0.20),
            titleBodyFrame: NormalizedPageRect(x: 0.14, y: 0.53, width: 0.72, height: 0.13),
            titleFontSize: isKidsBook ? 0.10 : 0.085,
            titleBodyFontSize: 0.036,
            closingIconFrame: NormalizedPageRect(x: 0.425, y: 0.22, width: 0.15, height: 0.115),
            closingHeadingFrame: NormalizedPageRect(x: 0.15, y: 0.39, width: 0.70, height: 0.11),
            closingBadgeFrame: NormalizedPageRect(x: 0.245, y: 0.57, width: 0.51, height: 0.085),
            closingStoreTextFrame: NormalizedPageRect(x: 0.335, y: 0.582, width: 0.37, height: 0.06),
            closingHeadingFontSize: 0.048,
            closingStoreFontSize: 0.023
        )
    }

    private static func appendEditableElements(
        from legacyDocument: BookPageDocument,
        to document: inout BookPageDocument
    ) throws {
        for element in legacyDocument.elements where !element.isLockedBackground {
            if legacyDocument.semanticTemplate == document.semanticTemplate,
               case .text(let text) = element.content,
               text.role != .custom {
                continue
            }
            guard !document.containsCanonicalTextEquivalent(to: element) else { continue }
            try document.appendPreservingIdentity(element)
        }
    }
}

struct BookPageImageCropTransform: Codable, Equatable, Sendable {
    var zoom: Double
    var offsetX: Double
    var offsetY: Double

    static let identity = BookPageImageCropTransform(zoom: 1, offsetX: 0, offsetY: 0)

    init(zoom: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.zoom = min(max(zoom.isFinite ? zoom : 1, 1), 4)
        self.offsetX = offsetX.isFinite ? offsetX : 0
        self.offsetY = offsetY.isFinite ? offsetY : 0
    }

    private enum CodingKeys: String, CodingKey {
        case zoom
        case offsetX
        case offsetY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            zoom: try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 1,
            offsetX: try container.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0,
            offsetY: try container.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(zoom, forKey: .zoom)
        try container.encode(offsetX, forKey: .offsetX)
        try container.encode(offsetY, forKey: .offsetY)
    }
}

enum BookPageImageCropPolicy {
    static let minimumZoom = 1.0
    static let maximumZoom = 4.0

    static func clamped(
        _ transform: BookPageImageCropTransform,
        imageSize: CGSize,
        viewportSize: CGSize
    ) -> BookPageImageCropTransform {
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return .identity
        }

        let zoom = min(max(transform.zoom.isFinite ? transform.zoom : 1, minimumZoom), maximumZoom)
        let imageAspectRatio = imageSize.width / imageSize.height
        let viewportAspectRatio = viewportSize.width / viewportSize.height
        let baseWidth: CGFloat
        let baseHeight: CGFloat
        if imageAspectRatio > viewportAspectRatio {
            baseHeight = viewportSize.height
            baseWidth = baseHeight * imageAspectRatio
        } else {
            baseWidth = viewportSize.width
            baseHeight = baseWidth / imageAspectRatio
        }

        let maximumOffsetX = max(0, ((baseWidth * CGFloat(zoom)) - viewportSize.width) / 2 / viewportSize.width)
        let maximumOffsetY = max(0, ((baseHeight * CGFloat(zoom)) - viewportSize.height) / 2 / viewportSize.height)
        let offsetX = transform.offsetX.isFinite ? transform.offsetX : 0
        let offsetY = transform.offsetY.isFinite ? transform.offsetY : 0
        return BookPageImageCropTransform(
            zoom: zoom,
            offsetX: min(max(offsetX, -Double(maximumOffsetX)), Double(maximumOffsetX)),
            offsetY: min(max(offsetY, -Double(maximumOffsetY)), Double(maximumOffsetY))
        )
    }
}

enum BookPageImageSource: String, Codable, Sendable {
    case aiGenerated
    case userPhoto
    case pageBackground
}

struct BookPageTextContent: Codable, Equatable, Sendable {
    var text: String
    var fontSize: Double
    var alignment: BookPageTextAlignment
    var role: BookPageTextRole
    var typographyPreset: BookPageTypographyPreset
    var color: BookPageTextColor?

    init(
        text: String,
        fontSize: Double = BookPageEditingPolicy.defaultFontSize,
        alignment: BookPageTextAlignment = .leading,
        role: BookPageTextRole = .custom,
        typographyPreset: BookPageTypographyPreset = .custom,
        color: BookPageTextColor? = nil
    ) {
        self.text = text
        self.fontSize = BookPageEditingPolicy.clampedFontSize(fontSize)
        self.alignment = alignment
        self.role = role
        self.typographyPreset = typographyPreset
        self.color = color
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case fontSize
        case alignment
        case role
        case typographyPreset
        case color
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
        role = try container.decodeIfPresent(BookPageTextRole.self, forKey: .role) ?? .custom
        typographyPreset = try container.decodeIfPresent(BookPageTypographyPreset.self, forKey: .typographyPreset) ?? .custom
        color = try container.decodeIfPresent(BookPageTextColor.self, forKey: .color)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(alignment, forKey: .alignment)
        try container.encode(role, forKey: .role)
        try container.encode(typographyPreset, forKey: .typographyPreset)
        try container.encodeIfPresent(color, forKey: .color)
    }
}

struct BookPageStoredImage: Codable, Equatable, Sendable {
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    var accessibilityDescription: String
    var fit: BookPageImageFit
    var source: BookPageImageSource
    var caption: String
    var cropTransform: BookPageImageCropTransform

    fileprivate init(
        jpegData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        accessibilityDescription: String = "Photo",
        fit: BookPageImageFit = .fit,
        source: BookPageImageSource = .userPhoto,
        caption: String = "",
        cropTransform: BookPageImageCropTransform = .identity
    ) {
        self.jpegData = jpegData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.accessibilityDescription = accessibilityDescription
        self.fit = fit
        self.source = source
        self.caption = String(caption.prefix(BookPageEditingPolicy.maximumCaptionCharacterCount))
        self.cropTransform = cropTransform
    }

    private enum CodingKeys: String, CodingKey {
        case jpegData
        case pixelWidth
        case pixelHeight
        case accessibilityDescription
        case fit
        case source
        case caption
        case cropTransform
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
        caption = String(
            (try container.decodeIfPresent(String.self, forKey: .caption) ?? "")
                .prefix(BookPageEditingPolicy.maximumCaptionCharacterCount)
        )
        cropTransform = try container.decodeIfPresent(
            BookPageImageCropTransform.self,
            forKey: .cropTransform
        ) ?? .identity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jpegData, forKey: .jpegData)
        try container.encode(pixelWidth, forKey: .pixelWidth)
        try container.encode(pixelHeight, forKey: .pixelHeight)
        try container.encode(accessibilityDescription, forKey: .accessibilityDescription)
        try container.encode(fit, forKey: .fit)
        try container.encode(source, forKey: .source)
        try container.encode(caption, forKey: .caption)
        try container.encode(cropTransform, forKey: .cropTransform)
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

    var isLockedBackground: Bool {
        guard case .image(let image) = content else { return false }
        return image.source == .pageBackground
    }

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
    static let currentSchemaVersion = 2

    let id: UUID
    private(set) var schemaVersion: Int
    var pageAspectRatio: Double
    private(set) var semanticTemplate: BookPageSemanticTemplate?
    private(set) var semanticTemplateVersion: Int?
    private(set) var elements: [BookPageElement]

    init(
        id: UUID = UUID(),
        pageAspectRatio: Double = 11.0 / 8.5,
        semanticTemplate: BookPageSemanticTemplate? = nil,
        semanticTemplateVersion: Int? = nil
    ) {
        self.id = id
        schemaVersion = Self.currentSchemaVersion
        self.pageAspectRatio = pageAspectRatio.isFinite && pageAspectRatio > 0 ? pageAspectRatio : 11.0 / 8.5
        self.semanticTemplate = semanticTemplate
        self.semanticTemplateVersion = semanticTemplateVersion
        elements = []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case pageAspectRatio
        case semanticTemplate
        case semanticTemplateVersion
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
        schemaVersion = Self.currentSchemaVersion
        pageAspectRatio = decodedAspectRatio
        semanticTemplate = try container.decodeIfPresent(BookPageSemanticTemplate.self, forKey: .semanticTemplate)
        semanticTemplateVersion = try container.decodeIfPresent(Int.self, forKey: .semanticTemplateVersion)
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
        try container.encodeIfPresent(semanticTemplate, forKey: .semanticTemplate)
        try container.encodeIfPresent(semanticTemplateVersion, forKey: .semanticTemplateVersion)
        try container.encode(elements, forKey: .elements)
    }

    mutating func appendPreservingIdentity(_ element: BookPageElement) throws {
        guard !elements.contains(where: { $0.id == element.id }) else { return }
        let image: BookPageStoredImage? = {
            guard case .image(let image) = element.content else { return nil }
            return image
        }()
        try BookPageCapacityPolicy.validateAddition(
            currentElementCount: elements.count,
            currentImageCount: imageCount,
            currentStoredImageByteCount: storedImageByteCount,
            newImageByteCount: image?.jpegData.count,
            currentStoredImagePixelCount: storedImagePixelCount,
            newImagePixelCount: image?.pixelCount
        )
        elements.append(element)
    }

    func containsCanonicalTextEquivalent(to element: BookPageElement) -> Bool {
        guard case .text(let candidate) = element.content,
              candidate.role != .custom else { return false }
        return elements.contains { existing in
            guard case .text(let text) = existing.content else { return false }
            return text.role == candidate.role &&
                text.text.trimmingCharacters(in: .whitespacesAndNewlines) ==
                    candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @discardableResult
    mutating func addText(
        _ text: String = "Add your story",
        frame: NormalizedPageRect? = nil,
        role: BookPageTextRole = .custom,
        typographyPreset: BookPageTypographyPreset = .custom,
        color: BookPageTextColor? = nil
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
            content: .text(BookPageTextContent(
                text: text,
                role: role,
                typographyPreset: typographyPreset,
                color: color
            ))
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
        elements.removeAll { $0.id == id && !$0.isLockedBackground }
    }

    mutating func bringToFront(id: UUID) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              !elements[index].isLockedBackground else { return }
        elements.append(elements.remove(at: index))
    }

    mutating func sendToBack(id: UUID) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              !elements[index].isLockedBackground else { return }
        let backgroundCount = elements.prefix { $0.isLockedBackground }.count
        elements.insert(elements.remove(at: index), at: min(backgroundCount, elements.count - 1))
    }

    mutating func moveElement(
        id: UUID,
        startingAt startingFrame: NormalizedPageRect? = nil,
        normalizedTranslation: CGSize
    ) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              !elements[index].isLockedBackground else { return }
        elements[index].frame = BookPageEditingPolicy.moved(
            startingFrame ?? elements[index].frame,
            normalizedTranslation: normalizedTranslation,
            snappingTo: elements.enumerated().compactMap { elementIndex, element in
                elementIndex == index ? nil : element.frame
            }
        )
    }

    mutating func resizeElement(
        id: UUID,
        startingAt startingFrame: NormalizedPageRect? = nil,
        handle: BookPageResizeHandle,
        normalizedTranslation: CGSize
    ) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              !elements[index].isLockedBackground else { return }
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
              !elements[index].isLockedBackground,
              case .image(var content) = elements[index].content else { return }
        content.fit = fit
        elements[index].content = .image(content)
    }

    mutating func updateImageAccessibilityDescription(id: UUID, description: String) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              !elements[index].isLockedBackground,
              case .image(var content) = elements[index].content else { return }
        content.accessibilityDescription = String(description.prefix(240))
        elements[index].content = .image(content)
    }

    mutating func updateImageCaption(id: UUID, caption: String) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              !elements[index].isLockedBackground,
              case .image(var content) = elements[index].content else { return }
        content.caption = String(caption.prefix(BookPageEditingPolicy.maximumCaptionCharacterCount))
        elements[index].content = .image(content)
    }

    mutating func updateImageCropTransform(
        id: UUID,
        transform: BookPageImageCropTransform,
        viewportSize: CGSize
    ) {
        guard let index = elements.firstIndex(where: { $0.id == id }),
              !elements[index].isLockedBackground,
              case .image(var content) = elements[index].content else { return }
        content.cropTransform = BookPageImageCropPolicy.clamped(
            transform,
            imageSize: CGSize(width: CGFloat(content.pixelWidth), height: CGFloat(content.pixelHeight)),
            viewportSize: viewportSize
        )
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
        preserved.caption = existing.caption
        preserved.cropTransform = existing.cropTransform
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

struct BookPageEditorHistory {
    private(set) var undoSnapshots: [BookPageDocument] = []
    private(set) var redoSnapshots: [BookPageDocument] = []
    private var pendingSnapshot: BookPageDocument?

    var canUndo: Bool { !undoSnapshots.isEmpty }
    var canRedo: Bool { !redoSnapshots.isEmpty }

    mutating func beginMutation(from document: BookPageDocument) {
        guard pendingSnapshot == nil else { return }
        pendingSnapshot = document
    }

    mutating func commitMutation(to document: BookPageDocument) {
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        record(snapshot: snapshot, changedDocument: document)
    }

    mutating func recordMutation(from previous: BookPageDocument, to document: BookPageDocument) {
        record(snapshot: previous, changedDocument: document)
    }

    mutating func undo(current document: inout BookPageDocument) {
        pendingSnapshot = nil
        guard let snapshot = undoSnapshots.popLast() else { return }
        redoSnapshots.append(document)
        document = snapshot
    }

    mutating func redo(current document: inout BookPageDocument) {
        pendingSnapshot = nil
        guard let snapshot = redoSnapshots.popLast() else { return }
        undoSnapshots.append(document)
        document = snapshot
    }

    private mutating func record(snapshot: BookPageDocument, changedDocument: BookPageDocument) {
        guard snapshot != changedDocument else { return }
        undoSnapshots.append(snapshot)
        redoSnapshots.removeAll()
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
    static let maximumCaptionCharacterCount = 240
    static let minimumWidth = 0.08
    static let minimumHeight = 0.06
    static let minimumFontSize = 0.015
    static let maximumFontSize = 0.12
    static let defaultFontSize = 0.038
    static let alignmentSnapThreshold = 0.012

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
        normalizedTranslation: CGSize,
        snappingTo otherFrames: [NormalizedPageRect] = []
    ) -> NormalizedPageRect {
        let source = clamped(rect)
        let moved = clamped(
            NormalizedPageRect(
                x: source.x + finite(normalizedTranslation.width, fallback: 0),
                y: source.y + finite(normalizedTranslation.height, fallback: 0),
                width: source.width,
                height: source.height
            )
        )
        return aligned(moved, to: otherFrames)
    }

    private static func aligned(
        _ rect: NormalizedPageRect,
        to otherFrames: [NormalizedPageRect]
    ) -> NormalizedPageRect {
        let horizontal = horizontalAnchors(rect)
        let vertical = verticalAnchors(rect)
        let horizontalDeltas = [
            0 - horizontal[0],
            0.5 - horizontal[1],
            1 - horizontal[2]
        ] + otherFrames.flatMap { frame in
            zip(horizontalAnchors(frame), horizontal).map { pair in pair.0 - pair.1 }
        }
        let verticalDeltas = [
            0 - vertical[0],
            0.5 - vertical[1],
            1 - vertical[2]
        ] + otherFrames.flatMap { frame in
            zip(verticalAnchors(frame), vertical).map { pair in pair.0 - pair.1 }
        }
        let horizontalDelta = nearestSnapDelta(horizontalDeltas)
        let verticalDelta = nearestSnapDelta(verticalDeltas)

        return clamped(
            NormalizedPageRect(
                x: rect.x + horizontalDelta,
                y: rect.y + verticalDelta,
                width: rect.width,
                height: rect.height
            )
        )
    }

    private static func horizontalAnchors(_ rect: NormalizedPageRect) -> [Double] {
        [rect.x, rect.x + rect.width / 2, rect.x + rect.width]
    }

    private static func verticalAnchors(_ rect: NormalizedPageRect) -> [Double] {
        [rect.y, rect.y + rect.height / 2, rect.y + rect.height]
    }

    private static func nearestSnapDelta(_ deltas: [Double]) -> Double {
        deltas
            .filter { abs($0) <= alignmentSnapThreshold }
            .min(by: { abs($0) < abs($1) }) ?? 0
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
        fit: BookPageImageFit = .fit,
        source: BookPageImageSource = .userPhoto,
        maximumPixelCount: Int? = nil
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
            source: source,
            maximumPixelCount: maximumPixelCount
        )
    }

    static func prepareForStorage(
        _ sourceData: Data,
        accessibilityDescription: String = "Photo",
        fit: BookPageImageFit = .fit,
        source: BookPageImageSource = .userPhoto,
        maximumPixelCount: Int? = nil
    ) throws -> BookPageStoredImage {
        guard let imageSource = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            throw BookPageImagePreparationError.invalidImage
        }
        return try prepareForStorage(
            imageSource: imageSource,
            accessibilityDescription: accessibilityDescription,
            fit: fit,
            source: source,
            maximumPixelCount: maximumPixelCount
        )
    }

    private static func prepareForStorage(
        imageSource: CGImageSource,
        accessibilityDescription: String,
        fit: BookPageImageFit,
        source: BookPageImageSource,
        maximumPixelCount: Int?
    ) throws -> BookPageStoredImage {
        guard let sourceProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let sourceWidth = sourceProperties[kCGImagePropertyPixelWidth] as? Int,
              let sourceHeight = sourceProperties[kCGImagePropertyPixelHeight] as? Int,
              sourceWidth > 0,
              sourceHeight > 0 else {
            throw BookPageImagePreparationError.invalidImage
        }

        let pixelBudget = min(
            maximumPixelCount ?? BookPageCapacityPolicy.maximumStoredImagePixelCount,
            BookPageCapacityPolicy.maximumStoredImagePixelCount
        )
        guard pixelBudget > 0 else {
            throw BookPageCapacityError.maximumStoredImagePixelsReached
        }
        let sourcePixelCount = Double(sourceWidth) * Double(sourceHeight)
        let pixelScale = min(1, sqrt(Double(pixelBudget) / sourcePixelCount))
        let budgetedLongestSide = max(
            1,
            Int((Double(max(sourceWidth, sourceHeight)) * pixelScale).rounded(.down))
        )
        let thumbnailMaximumDimension = min(maximumPixelDimension, budgetedLongestSide)

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaximumDimension,
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
        if Int(image.size.width.rounded(.up)) * Int(image.size.height.rounded(.up)) > pixelBudget {
            image = resized(image, maximumPixelCount: pixelBudget)
        }
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

    private static func resized(_ image: UIImage, maximumPixelCount: Int) -> UIImage {
        let currentPixelCount = image.size.width * image.size.height
        guard currentPixelCount > CGFloat(maximumPixelCount), currentPixelCount > 0 else { return image }
        let scale = sqrt(CGFloat(maximumPixelCount) / currentPixelCount) * 0.999
        let targetSize = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
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
