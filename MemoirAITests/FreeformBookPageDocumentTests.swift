import Foundation
import Testing
import UIKit
@testable import MemoirAI

struct FreeformBookPageDocumentTests {
    @Test func clampingKeepsElementsInsideThePage() {
        let result = BookPageEditingPolicy.clamped(
            NormalizedPageRect(x: -0.4, y: 0.95, width: 1.4, height: .nan)
        )

        #expect(result == NormalizedPageRect(x: 0, y: 0.94, width: 1, height: 0.06))
    }

    @Test func movingPreservesSizeAndStopsAtPageEdges() {
        let source = NormalizedPageRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4)
        let result = BookPageEditingPolicy.moved(
            source,
            normalizedTranslation: CGSize(width: 0.9, height: -0.9)
        )

        #expect(result == NormalizedPageRect(x: 0.7, y: 0, width: 0.3, height: 0.4))
    }

    @Test func everyResizeHandleHonorsMinimumSizeAndBounds() {
        let source = NormalizedPageRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)

        for handle in BookPageResizeHandle.allCases {
            let negative = BookPageEditingPolicy.resized(
                source,
                handle: handle,
                normalizedTranslation: CGSize(width: -2, height: -2)
            )
            let positive = BookPageEditingPolicy.resized(
                source,
                handle: handle,
                normalizedTranslation: CGSize(width: 2, height: 2)
            )

            for result in [negative, positive] {
                #expect(result.x >= 0)
                #expect(result.y >= 0)
                #expect(result.width + 1e-12 >= BookPageEditingPolicy.minimumWidth)
                #expect(result.height + 1e-12 >= BookPageEditingPolicy.minimumHeight)
                #expect(result.x + result.width <= 1 + 1e-12)
                #expect(result.y + result.height <= 1 + 1e-12)
            }
        }
    }

    @Test func fontSizeIsFiniteAndBounded() {
        #expect(BookPageEditingPolicy.clampedFontSize(.nan) == BookPageEditingPolicy.defaultFontSize)
        #expect(BookPageEditingPolicy.clampedFontSize(-1) == BookPageEditingPolicy.minimumFontSize)
        #expect(BookPageEditingPolicy.clampedFontSize(1) == BookPageEditingPolicy.maximumFontSize)
    }

    @Test func defaultFramesStaggerNewLayersWithoutLeavingThePage() {
        let firstText = BookPageEditingPolicy.staggeredDefaultTextFrame(existingElementCount: 0)
        let secondText = BookPageEditingPolicy.staggeredDefaultTextFrame(existingElementCount: 1)
        let firstImage = BookPageEditingPolicy.staggeredDefaultImageFrame(existingImageCount: 0)
        let secondImage = BookPageEditingPolicy.staggeredDefaultImageFrame(existingImageCount: 1)

        #expect(firstText != secondText)
        #expect(firstImage != secondImage)
        #expect(secondText.x + secondText.width <= 1)
        #expect(secondText.y + secondText.height <= 1)
        #expect(secondImage.x + secondImage.width <= 1)
        #expect(secondImage.y + secondImage.height <= 1)
    }

    @Test func decodedTextClampsAnOutOfRangeFontSize() throws {
        let encoded = Data(#"{"text":"Hello","fontSize":4,"alignment":"center"}"#.utf8)
        let decoded = try JSONDecoder().decode(BookPageTextContent.self, from: encoded)

        #expect(decoded.fontSize == BookPageEditingPolicy.maximumFontSize)
        #expect(decoded.alignment == .center)
    }

    @Test func documentMutationsPreserveZOrderAndDeleteExactlyOneElement() throws {
        var document = BookPageDocument()
        let first = try document.addText("First")
        let second = try document.addText("Second")
        let third = try document.addText("Third")

        document.bringToFront(id: first)
        #expect(document.elements.map(\.id) == [second, third, first])

        document.sendToBack(id: third)
        #expect(document.elements.map(\.id) == [third, second, first])

        document.deleteElement(id: second)
        #expect(document.elements.map(\.id) == [third, first])
    }

    @Test func documentMoveResizeAndTextUpdatesUseSharedPolicies() throws {
        var document = BookPageDocument()
        let initialFrame = NormalizedPageRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let id = try document.addText("Before", frame: initialFrame)

        document.moveElement(
            id: id,
            startingAt: initialFrame,
            normalizedTranslation: CGSize(width: 2, height: 2)
        )
        guard let movedFrame = document.elements.first?.frame else {
            Issue.record("Expected the inserted text element")
            return
        }
        document.resizeElement(
            id: id,
            startingAt: movedFrame,
            handle: .topLeading,
            normalizedTranslation: CGSize(width: 2, height: 2)
        )
        document.updateText(id: id, text: "After")
        document.updateFontSize(id: id, fontSize: 10)

        let element = document.elements.first
        #expect(element?.frame.x == 0.92)
        #expect(element?.frame.y == 0.94)
        #expect(abs((element?.frame.width ?? 0) - BookPageEditingPolicy.minimumWidth) < 1e-12)
        #expect(abs((element?.frame.height ?? 0) - BookPageEditingPolicy.minimumHeight) < 1e-12)
        if case .text(let text) = element?.content {
            #expect(text.text == "After")
            #expect(text.fontSize == BookPageEditingPolicy.maximumFontSize)
        } else {
            Issue.record("Expected a text element")
        }
    }

    @Test func codableRoundTripPreservesTextImageDataAndOrdering() throws {
        let storedImage = try BookPageImagePreparation.prepareForStorage(makeTestImageData())
        var document = BookPageDocument(pageAspectRatio: 1.25)
        _ = try document.addText("A memory")
        _ = try document.addImage(storedImage)

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(BookPageDocument.self, from: encoded)

        #expect(decoded == document)
    }

    @Test func replacingGeneratedImagePreservesFrameAndUserPhotos() throws {
        let generated = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(),
            source: .aiGenerated
        )
        let replacement = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 80, height: 60),
            source: .aiGenerated
        )
        let userPhoto = try BookPageImagePreparation.prepareForStorage(makeTestImageData())
        var document = BookPageDocument()
        let generatedID = try document.addImage(
            generated,
            frame: NormalizedPageRect(x: 0.1, y: 0.2, width: 0.7, height: 0.5)
        )
        let userPhotoID = try document.addImage(userPhoto)
        document.updateImageFit(id: generatedID, fit: .fit)
        document.updateImageAccessibilityDescription(id: generatedID, description: "Original description")

        try document.replaceFirstImage(from: .aiGenerated, with: replacement)

        let generatedElement = document.elements.first { $0.id == generatedID }
        let userElement = document.elements.first { $0.id == userPhotoID }
        #expect(generatedElement?.frame == NormalizedPageRect(x: 0.1, y: 0.2, width: 0.7, height: 0.5))
        if case .image(let image) = generatedElement?.content {
            #expect(image.jpegData == replacement.jpegData)
            #expect(image.source == .aiGenerated)
            #expect(image.fit == .fit)
            #expect(image.accessibilityDescription == "Original description")
        } else {
            Issue.record("Expected the generated image layer")
        }
        if case .image(let image) = userElement?.content {
            #expect(image.source == .userPhoto)
        } else {
            Issue.record("Expected the user photo layer")
        }
    }

    @Test func generatedImageLookupUsesSemanticSourceInsteadOfZOrder() throws {
        let generated = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 80, height: 60),
            source: .aiGenerated
        )
        let userPhoto = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 72, height: 54),
            source: .userPhoto
        )
        var document = BookPageDocument()
        _ = try document.addImage(generated)
        let userPhotoID = try document.addImage(userPhoto)
        document.sendToBack(id: userPhotoID)

        #expect(document.storedImageData(from: .aiGenerated) == generated.jpegData)
        #expect(document.storedImageData(from: .userPhoto) == userPhoto.jpegData)
    }

    @Test func replacingExactTextLeavesOtherLayersUntouched() throws {
        var document = BookPageDocument()
        _ = try document.addText("Original Title")
        _ = try document.addText("Original Title with a subtitle")
        _ = try document.addText("  Original Title  ")

        document.replaceText(matching: "Original Title", with: "Updated Title")

        let values = document.elements.compactMap { element -> String? in
            guard case .text(let content) = element.content else { return nil }
            return content.text
        }
        #expect(values == [
            "Updated Title",
            "Original Title with a subtitle",
            "Updated Title"
        ])
    }

    @Test func elementAppearanceUpdatesAffectOnlyMatchingContentType() throws {
        let image = try BookPageImagePreparation.prepareForStorage(makeTestImageData())
        var document = BookPageDocument()
        let textID = try document.addText("Aligned")
        let imageID = try document.addImage(image)

        document.updateTextAlignment(id: textID, alignment: .trailing)
        document.updateImageFit(id: imageID, fit: .fit)
        document.updateImageAccessibilityDescription(
            id: imageID,
            description: String(repeating: "a", count: 300)
        )

        if case .text(let text) = document.elements.first(where: { $0.id == textID })?.content {
            #expect(text.alignment == .trailing)
        } else {
            Issue.record("Expected a text layer")
        }
        if case .image(let updatedImage) = document.elements.first(where: { $0.id == imageID })?.content {
            #expect(updatedImage.fit == .fit)
            #expect(updatedImage.accessibilityDescription.count == 240)
        } else {
            Issue.record("Expected an image layer")
        }
    }

    @Test func imagePreparationRejectsInvalidInput() {
        #expect(throws: BookPageImagePreparationError.self) {
            try BookPageImagePreparation.prepareForStorage(Data("not an image".utf8))
        }
    }

    @Test func oversizedTextIsRejectedWithoutTruncation() throws {
        let oversized = String(repeating: "a", count: BookPageEditingPolicy.maximumTextCharacterCount + 500)
        var document = BookPageDocument()
        #expect(throws: BookPageCapacityError.maximumTextCharactersReached) {
            try document.addText(oversized)
        }
        let id = try document.addText("Original")
        let accepted = document.updateText(id: id, text: oversized)
        #expect(!accepted)

        if case .text(let text) = document.elements.first?.content {
            #expect(text.text == "Original")
        } else {
            Issue.record("Expected a text layer")
        }
    }

    @Test func oversizedDecodedTextIsRejected() throws {
        let oversized = String(repeating: "a", count: BookPageEditingPolicy.maximumTextCharacterCount + 1)
        let encoded = try JSONEncoder().encode([
            "text": oversized,
            "fontSize": String(BookPageEditingPolicy.defaultFontSize),
            "alignment": "leading"
        ])
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: String]
        let payload = try JSONSerialization.data(withJSONObject: [
            "text": object?["text"] ?? oversized,
            "fontSize": BookPageEditingPolicy.defaultFontSize,
            "alignment": "leading"
        ])

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BookPageTextContent.self, from: payload)
        }
    }

    @Test func fileBackedImagePreparationAvoidsLoadingTheOriginalPayload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("book-page-photo-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeTestImageData(width: 3_200, height: 900).write(to: url)

        let result = try BookPageImagePreparation.prepareForStorage(fileURL: url)

        #expect(max(result.pixelWidth, result.pixelHeight) <= BookPageImagePreparation.maximumPixelDimension)
        #expect(result.jpegData.count <= BookPageImagePreparation.maximumByteCount)
    }

    @Test func capacityPolicyRejectsDecodedPixelMemoryAboveThePageLimit() {
        #expect(throws: BookPageCapacityError.maximumStoredImagePixelsReached) {
            try BookPageCapacityPolicy.validateAddition(
                currentElementCount: 1,
                currentImageCount: 1,
                currentStoredImageByteCount: 100,
                newImageByteCount: 100,
                currentStoredImagePixelCount: BookPageCapacityPolicy.maximumStoredImagePixelCount,
                newImagePixelCount: 1
            )
        }
    }

    @Test func collectionCapacityRejectsAggregateImageMemory() throws {
        let image = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 3_000, height: 2_000)
        )
        var documents: [BookPageDocument] = []
        for _ in 0..<9 {
            var document = BookPageDocument()
            _ = try document.addImage(image)
            documents.append(document)
        }

        #expect(!BookPageCollectionCapacityPolicy.accepts(documents))
        #expect(BookPageCollectionCapacityPolicy.accepts(documents.prefix(8)))
    }

    @Test func imagePreparationCapsPixelDimensionsAndEncodedBytes() throws {
        let result = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 3_200, height: 900)
        )

        #expect(max(result.pixelWidth, result.pixelHeight) <= BookPageImagePreparation.maximumPixelDimension)
        #expect(result.jpegData.count <= BookPageImagePreparation.maximumByteCount)
        #expect(UIImage(data: result.jpegData) != nil)
    }

    @Test func documentDownloadPolicyRequiresSecureSuccessfulBoundedPayload() throws {
        let secureURL = try #require(URL(string: "https://storage.example/page.json"))
        let insecureURL = try #require(URL(string: "http://storage.example/page.json"))

        #expect(BookPageDocumentDownloadPolicy.accepts(url: secureURL, statusCode: 200, fileByteCount: 10))
        #expect(!BookPageDocumentDownloadPolicy.accepts(url: insecureURL, statusCode: 200, fileByteCount: 10))
        #expect(!BookPageDocumentDownloadPolicy.accepts(url: secureURL, statusCode: 404, fileByteCount: 10))
        #expect(!BookPageDocumentDownloadPolicy.accepts(url: secureURL, statusCode: 200, fileByteCount: 0))
        #expect(!BookPageDocumentDownloadPolicy.accepts(
            url: secureURL,
            statusCode: 200,
            fileByteCount: BookPageCapacityPolicy.maximumEncodedDocumentByteCount + 1
        ))
    }

    @Test func storedImageDecodeRejectsPayloadAboveByteLimit() throws {
        let payload: [String: Any] = [
            "jpegData": Data(count: BookPageImagePreparation.maximumByteCount + 1).base64EncodedString(),
            "pixelWidth": 10,
            "pixelHeight": 10,
            "accessibilityDescription": "Photo",
            "fit": "fill"
        ]
        let encoded = try JSONSerialization.data(withJSONObject: payload)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BookPageStoredImage.self, from: encoded)
        }
    }

    @Test func documentDecodeRejectsUnknownSchemaVersion() throws {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "schemaVersion": BookPageDocument.currentSchemaVersion + 1,
            "pageAspectRatio": 1.25,
            "elements": []
        ]
        let encoded = try JSONSerialization.data(withJSONObject: payload)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BookPageDocument.self, from: encoded)
        }
    }

    @Test func capacityPolicyRejectsEveryPageLimit() {
        #expect(throws: BookPageCapacityError.maximumElementsReached) {
            try BookPageCapacityPolicy.validateAddition(
                currentElementCount: BookPageCapacityPolicy.maximumElementCount,
                currentImageCount: 0,
                currentStoredImageByteCount: 0,
                newImageByteCount: nil
            )
        }

        #expect(throws: BookPageCapacityError.maximumImagesReached) {
            try BookPageCapacityPolicy.validateAddition(
                currentElementCount: BookPageCapacityPolicy.maximumImageCount,
                currentImageCount: BookPageCapacityPolicy.maximumImageCount,
                currentStoredImageByteCount: 0,
                newImageByteCount: 1
            )
        }

        #expect(throws: BookPageCapacityError.maximumStoredImageBytesReached) {
            try BookPageCapacityPolicy.validateAddition(
                currentElementCount: 1,
                currentImageCount: 1,
                currentStoredImageByteCount: BookPageCapacityPolicy.maximumStoredImageByteCount - 10,
                newImageByteCount: 11
            )
        }
    }

    @Test func documentEnforcesElementAndImageCounts() throws {
        var textDocument = BookPageDocument()
        for index in 0..<BookPageCapacityPolicy.maximumElementCount {
            _ = try textDocument.addText("Text \(index)")
        }
        #expect(throws: BookPageCapacityError.maximumElementsReached) {
            try textDocument.addText("One too many")
        }

        let storedImage = try BookPageImagePreparation.prepareForStorage(makeTestImageData())
        var imageDocument = BookPageDocument()
        for _ in 0..<BookPageCapacityPolicy.maximumImageCount {
            _ = try imageDocument.addImage(storedImage)
        }
        #expect(imageDocument.imageCount == BookPageCapacityPolicy.maximumImageCount)
        #expect(imageDocument.storedImageByteCount == storedImage.jpegData.count * BookPageCapacityPolicy.maximumImageCount)
        #expect(throws: BookPageCapacityError.maximumImagesReached) {
            try imageDocument.addImage(storedImage)
        }
    }

    @MainActor
    @Test func printRendererUsesRequestedPixelSize() throws {
        var document = BookPageDocument()
        _ = try document.addText("Print me")

        let image = BookPagePrintRenderer.render(
            document: document,
            pixelSize: CGSize(width: 600, height: 400)
        )

        #expect(image?.size == CGSize(width: 600, height: 400))
    }

    private func makeTestImageData(width: Int = 64, height: Int = 48) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        }
        return image.pngData() ?? Data()
    }
}
