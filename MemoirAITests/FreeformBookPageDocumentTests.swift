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

    @Test func movingLightlySnapsToPageAndNearbyElementAlignment() {
        let source = NormalizedPageRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
        let nearbyElement = NormalizedPageRect(x: 0.51, y: 0.61, width: 0.2, height: 0.2)
        let aligned = BookPageEditingPolicy.moved(
            source,
            normalizedTranslation: CGSize(width: 0.301, height: 0.409),
            snappingTo: [nearbyElement]
        )

        #expect(abs(aligned.x - nearbyElement.x) < 1e-12)
        #expect(abs(aligned.y - nearbyElement.y) < 1e-12)

        let outsideThreshold = BookPageEditingPolicy.moved(
            source,
            normalizedTranslation: CGSize(width: 0.28, height: 0.38),
            snappingTo: [nearbyElement]
        )

        #expect(abs(outsideThreshold.x - 0.48) < 1e-12)
        #expect(abs(outsideThreshold.y - 0.58) < 1e-12)
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

    @Test func canonicalPageLayoutsMatchTheReaderGeometry() {
        let landscapeIllustration = BookPageCanonicalLayout.illustration(
            isLandscape: true,
            isPrecomposed: false
        )
        #expect(landscapeIllustration.imageFrame == NormalizedPageRect(x: 0, y: 0.065, width: 1, height: 0.935))
        #expect(landscapeIllustration.imageFit == .fill)

        let landscapeText = BookPageCanonicalLayout.text(
            isLandscape: true,
            hasTitle: true,
            hasSubtitle: false
        )
        #expect(landscapeText.titleFrame?.y == 0.085)
        #expect(landscapeText.bodyFrame.y == 0.18)

        let portraitText = BookPageCanonicalLayout.text(
            isLandscape: false,
            hasTitle: true,
            hasSubtitle: true
        )
        #expect(portraitText.titleFrame?.x == 0.06)
        #expect(portraitText.subtitleFrame?.y == 0.125)
        #expect(portraitText.bodyFrame.y == 0.18)
        #expect(portraitText.bodyFrame.height == 0.74)
    }

    @Test func decodedTextClampsAnOutOfRangeFontSize() throws {
        let encoded = Data(#"{"text":"Hello","fontSize":4,"alignment":"center"}"#.utf8)
        let decoded = try JSONDecoder().decode(BookPageTextContent.self, from: encoded)

        #expect(decoded.fontSize == BookPageEditingPolicy.maximumFontSize)
        #expect(decoded.alignment == .center)
        #expect(decoded.role == .custom)
        #expect(decoded.typographyPreset == .custom)
    }

    @Test func textRoleAndTypographySurviveDocumentRoundTrip() throws {
        var document = BookPageDocument()
        _ = try document.addText(
            "A chapter title",
            role: .title,
            typographyPreset: .kidsBook
        )

        let decoded = try JSONDecoder().decode(
            BookPageDocument.self,
            from: JSONEncoder().encode(document)
        )
        guard case .text(let text) = decoded.elements.first?.content else {
            Issue.record("Expected the title text element")
            return
        }
        #expect(text.role == .title)
        #expect(text.typographyPreset == .kidsBook)
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
        let imageID = try document.addImage(storedImage)
        document.updateImageCaption(id: imageID, caption: "First day at the lake")
        document.updateImageCropTransform(
            id: imageID,
            transform: BookPageImageCropTransform(zoom: 2.25, offsetX: 0.2, offsetY: -0.1),
            viewportSize: CGSize(width: 240, height: 160)
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(BookPageDocument.self, from: encoded)

        #expect(decoded == document)
    }

    @Test func schemaOneImageDefaultsCaptionAndCropForBackwardCompatibility() throws {
        let storedImage = try BookPageImagePreparation.prepareForStorage(makeTestImageData())
        var document = BookPageDocument()
        _ = try document.addImage(storedImage)
        let encoded = try JSONEncoder().encode(document)
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        root["schemaVersion"] = 1
        var elements = try #require(root["elements"] as? [[String: Any]])
        var image = try #require(elements[0]["image"] as? [String: Any])
        image.removeValue(forKey: "caption")
        image.removeValue(forKey: "cropTransform")
        elements[0]["image"] = image
        root["elements"] = elements

        let legacyData = try JSONSerialization.data(withJSONObject: root)
        let decoded = try JSONDecoder().decode(BookPageDocument.self, from: legacyData)

        #expect(decoded.schemaVersion == BookPageDocument.currentSchemaVersion)
        if case .image(let decodedImage) = decoded.elements.first?.content {
            #expect(decodedImage.caption.isEmpty)
            #expect(decodedImage.cropTransform == .identity)
        } else {
            Issue.record("Expected a decoded image layer")
        }
    }

    @Test func imageCaptionIsBoundedAndCropStaysInsideItsViewport() throws {
        let storedImage = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 400, height: 200)
        )
        var document = BookPageDocument()
        let imageID = try document.addImage(storedImage)
        document.updateImageCaption(
            id: imageID,
            caption: String(repeating: "c", count: BookPageEditingPolicy.maximumCaptionCharacterCount + 20)
        )
        document.updateImageCropTransform(
            id: imageID,
            transform: BookPageImageCropTransform(zoom: 4, offsetX: 20, offsetY: -20),
            viewportSize: CGSize(width: 100, height: 100)
        )

        if case .image(let image) = document.elements.first?.content {
            #expect(image.caption.count == BookPageEditingPolicy.maximumCaptionCharacterCount)
            #expect(image.cropTransform == BookPageImageCropTransform(zoom: 4, offsetX: 3.5, offsetY: -1.5))
        } else {
            Issue.record("Expected an updated image layer")
        }
    }

    @Test func cropPolicyNormalizesInvalidGeometryAndBoundsZoom() {
        let invalidViewport = BookPageImageCropPolicy.clamped(
            BookPageImageCropTransform(zoom: 3, offsetX: 1, offsetY: 1),
            imageSize: CGSize(width: 400, height: 200),
            viewportSize: .zero
        )
        let boundedZoom = BookPageImageCropTransform(zoom: 20, offsetX: 0, offsetY: 0)

        #expect(invalidViewport == .identity)
        #expect(boundedZoom.zoom == BookPageImageCropPolicy.maximumZoom)
    }

    @Test func replacingGeneratedImagePreservesCaptionAndCrop() throws {
        let generated = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 120, height: 80),
            source: .aiGenerated
        )
        let replacement = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 80, height: 120),
            source: .aiGenerated
        )
        var document = BookPageDocument()
        let imageID = try document.addImage(generated)
        document.updateImageCaption(id: imageID, caption: "A summer afternoon")
        document.updateImageCropTransform(
            id: imageID,
            transform: BookPageImageCropTransform(zoom: 2, offsetX: 0.25, offsetY: 0),
            viewportSize: CGSize(width: 200, height: 100)
        )
        let originalCrop: BookPageImageCropTransform
        if case .image(let image) = document.elements.first?.content {
            originalCrop = image.cropTransform
        } else {
            Issue.record("Expected an image layer")
            return
        }

        try document.replaceFirstImage(from: .aiGenerated, with: replacement)

        if case .image(let image) = document.elements.first?.content {
            #expect(image.caption == "A summer afternoon")
            #expect(image.cropTransform == originalCrop)
            #expect(image.jpegData == replacement.jpegData)
        } else {
            Issue.record("Expected a replacement image layer")
        }
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
        #expect(result.fit == .fit)
    }

    @Test func imagePreparationRespectsRemainingDecodedPixelBudget() throws {
        let pixelBudget = 1_500_000
        let result = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 3_200, height: 2_400),
            maximumPixelCount: pixelBudget
        )

        #expect(result.pixelWidth * result.pixelHeight <= pixelBudget)
        #expect(UIImage(data: result.jpegData) != nil)
    }

    @Test func generatedImageAndBudgetedPhotoFitOnTheSamePage() throws {
        let generated = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 2_400, height: 1_800),
            source: .aiGenerated
        )
        var document = BookPageDocument()
        _ = try document.addImage(generated)
        let remainingPixels = BookPageCapacityPolicy.maximumStoredImagePixelCount
            - document.storedImagePixelCount
        let photo = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(width: 3_200, height: 2_400),
            maximumPixelCount: remainingPixels
        )

        _ = try document.addImage(photo)

        #expect(document.imageCount == 2)
        #expect(document.storedImagePixelCount <= BookPageCapacityPolicy.maximumStoredImagePixelCount)
    }

    @Test func editorHistoryCoalescesAContinuousGestureAndSupportsRedo() throws {
        var document = BookPageDocument()
        let elementID = try document.addText("Move me")
        let original = document
        var history = BookPageEditorHistory()

        history.beginMutation(from: document)
        document.moveElement(id: elementID, normalizedTranslation: CGSize(width: 0.05, height: 0))
        document.moveElement(id: elementID, normalizedTranslation: CGSize(width: 0.05, height: 0))
        history.commitMutation(to: document)
        let moved = document

        #expect(history.undoSnapshots.count == 1)
        history.undo(current: &document)
        #expect(document == original)
        #expect(history.canRedo)
        history.redo(current: &document)
        #expect(document == moved)
    }

    @Test func editorHistoryClearsRedoAfterANewMutation() throws {
        var document = BookPageDocument()
        _ = try document.addText("First")
        let first = document
        _ = try document.addText("Second")
        var history = BookPageEditorHistory()
        history.recordMutation(from: first, to: document)
        history.undo(current: &document)
        #expect(history.canRedo)

        let beforeNewMutation = document
        _ = try document.addText("Replacement")
        history.recordMutation(from: beforeNewMutation, to: document)

        #expect(!history.canRedo)
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

    @MainActor
    @Test func captionAndCropAffectSharedPrintRendering() throws {
        let storedImage = try BookPageImagePreparation.prepareForStorage(makeTestImageData())
        var document = BookPageDocument(pageAspectRatio: 1)
        let imageID = try document.addImage(
            storedImage,
            frame: NormalizedPageRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        )
        let original = BookPagePrintRenderer.render(
            document: document,
            pixelSize: CGSize(width: 400, height: 400)
        )?.pngData()

        document.updateImageCaption(id: imageID, caption: "Visible in print")
        document.updateImageCropTransform(
            id: imageID,
            transform: BookPageImageCropTransform(zoom: 2, offsetX: 0.2, offsetY: 0.1),
            viewportSize: CGSize(width: 320, height: 260)
        )
        let edited = BookPagePrintRenderer.render(
            document: document,
            pixelSize: CGSize(width: 400, height: 400)
        )?.pngData()

        #expect(original != nil)
        #expect(edited != nil)
        #expect(edited != original)
        #expect(BookPageImageLayout.captionHeight(
            caption: "Visible in print",
            containerSize: CGSize(width: 320, height: 320)
        ) > 0)
        #expect(BookPageImageLayout.captionHeight(
            caption: "   ",
            containerSize: CGSize(width: 320, height: 320)
        ) == 0)
    }

    @Test func snapshotBackgroundCannotBeSelectedOrMutatedByDocumentCommands() throws {
        let background = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(),
            fit: .fill,
            source: .pageBackground
        )
        var document = BookPageDocument(pageAspectRatio: 1)
        let backgroundID = try document.addImage(
            background,
            frame: NormalizedPageRect(x: 0, y: 0, width: 1, height: 1)
        )
        let original = document

        document.moveElement(id: backgroundID, normalizedTranslation: CGSize(width: 0.2, height: 0.2))
        document.resizeElement(
            id: backgroundID,
            handle: .bottomTrailing,
            normalizedTranslation: CGSize(width: -0.2, height: -0.2)
        )
        document.deleteElement(id: backgroundID)

        #expect(document == original)
        #expect(document.elements.first?.isLockedBackground == true)
        let decoded = try JSONDecoder().decode(BookPageDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded.elements.first?.isLockedBackground == true)
    }

    @Test func everyTextRoleUsesItsSavedFontSize() {
        for role in [BookPageTextRole.title, .subtitle, .body, .custom] {
            let content = BookPageTextContent(text: "Resizable", fontSize: 0.05, role: role)
            #expect(BookPageTextSizing.pointSize(for: content, pageHeight: 600) == 30)
        }

        let smallest = BookPageTextContent(
            text: "Small but proportional",
            fontSize: BookPageEditingPolicy.minimumFontSize
        )
        #expect(BookPageTextSizing.pointSize(for: smallest, pageHeight: 400) == 6)
        #expect(BookPageTextSizing.pointSize(for: smallest, pageHeight: 800) == 12)
    }

    @Test func titlePageFactoryMakesOriginalCopyEditableAndMigratesUserLayers() throws {
        let background = try BookPageImagePreparation.prepareForStorage(
            makeTestImageData(),
            fit: .fill,
            source: .pageBackground
        )
        var legacy = BookPageDocument(pageAspectRatio: 8.5 / 11)
        _ = try legacy.addImage(
            background,
            frame: NormalizedPageRect(x: 0, y: 0, width: 1, height: 1)
        )
        let noteID = try legacy.addText("Keep my note")

        #expect(BookInteriorPageDocumentFactory.requiresSemanticMigration(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            document: legacy
        ))

        let document = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            title: "Grandparent's Memoir",
            body: "A collection of memories.",
            subtitle: nil,
            pageAspectRatio: 8.5 / 11,
            typographyPreset: .realistic,
            isKidsBook: false,
            background: background,
            preservingEditableElementsFrom: legacy
        )
        let text = document.elements.compactMap { element -> BookPageTextContent? in
            guard case .text(let content) = element.content else { return nil }
            return content
        }

        #expect(document.elements.filter { $0.isLockedBackground }.count == 1)
        #expect(text.contains { $0.text == "Grandparent's Memoir" && $0.role == .title })
        #expect(text.contains { $0.text == "A collection of memories." && $0.role == .body })
        #expect(text.contains { $0.text == "Keep my note" })
        #expect(document.elements.contains { $0.id == noteID })
        #expect(document.semanticTemplate == .interiorTitle)
        #expect(document.semanticTemplateVersion == BookInteriorPageDocumentFactory.semanticTemplateVersion)
        #expect(!BookInteriorPageDocumentFactory.requiresSemanticMigration(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            document: document
        ))
    }

    @Test func semanticBookendLayoutsAreReadableAndOrientationAware() {
        let landscape = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: 11.0 / 8.5,
            isKidsBook: false
        )
        let portrait = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: 8.5 / 11.0,
            isKidsBook: false
        )
        let kidsLandscape = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: 11.0 / 8.5,
            isKidsBook: true
        )

        #expect(landscape.titleFontSize == 0.085)
        #expect(kidsLandscape.titleFontSize == 0.09)
        #expect(portrait.titleFontSize == 0.074)
        #expect(landscape.titleFrame == NormalizedPageRect(x: 0.11, y: 0.29, width: 0.78, height: 0.17))
        #expect(landscape.closingIconFrame.y + landscape.closingIconFrame.height < landscape.closingHeadingFrame.y)
        #expect(landscape.closingHeadingFrame.y + landscape.closingHeadingFrame.height < landscape.closingBadgeFrame.y)
        #expect(portrait.closingIconFrame.y + portrait.closingIconFrame.height < portrait.closingHeadingFrame.y)
        #expect(portrait.closingHeadingFrame.y + portrait.closingHeadingFrame.height < portrait.closingBadgeFrame.y)
        #expect(abs((landscape.closingHeadingFrame.y - (landscape.closingIconFrame.y + landscape.closingIconFrame.height)) - 0.035) < 0.0001)
        #expect(abs((landscape.closingBadgeFrame.y - (landscape.closingHeadingFrame.y + landscape.closingHeadingFrame.height)) - 0.035) < 0.0001)
        #expect(abs((portrait.closingHeadingFrame.y - (portrait.closingIconFrame.y + portrait.closingIconFrame.height)) - 0.035) < 0.0001)
        #expect(abs((portrait.closingBadgeFrame.y - (portrait.closingHeadingFrame.y + portrait.closingHeadingFrame.height)) - 0.035) < 0.0001)
    }

    @Test func semanticTitleTypographyMatchesTheBookStyle() {
        #expect(BookPageTypographyPreset.kidsBook.interiorTitleTypography == .rounded)
        #expect(BookPageTypographyPreset.realistic.interiorTitleTypography == .editorial)
        #expect(BookPageTypographyPreset.comic.interiorTitleTypography == .editorial)
        #expect(BookPageTypographyPreset.custom.interiorTitleTypography == .editorial)
    }

    @Test func semanticMigrationPreservesEditedCanonicalCopyWithoutDuplicates() throws {
        let editedTitleFrame = NormalizedPageRect(x: 0.18, y: 0.22, width: 0.64, height: 0.24)
        var legacy = BookPageDocument(
            pageAspectRatio: 11.0 / 8.5,
            semanticTemplate: .interiorTitle,
            semanticTemplateVersion: 1
        )
        let titleID = try legacy.addText(
            "Caleb's Edited Story",
            frame: editedTitleFrame,
            role: .title,
            typographyPreset: .comic,
            color: .brown
        )
        legacy.updateFontSize(id: titleID, fontSize: 0.068)
        legacy.updateTextAlignment(id: titleID, alignment: .trailing)
        _ = try legacy.addText("An edited subtitle.", role: .body, typographyPreset: .realistic)
        let noteID = try legacy.addText("Keep this note", role: .custom, typographyPreset: .custom)
        let originalTitle = try #require(legacy.elements.first { $0.id == titleID })

        let migrated = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            title: "Grandparent's Memoir",
            body: "A collection of memories.",
            subtitle: nil,
            pageAspectRatio: 11.0 / 8.5,
            typographyPreset: .realistic,
            isKidsBook: false,
            background: nil,
            preservingEditableElementsFrom: legacy
        )
        let text = migrated.elements.compactMap { element -> BookPageTextContent? in
            guard case .text(let content) = element.content else { return nil }
            return content
        }

        #expect(text.filter { $0.role == .title }.map(\.text) == ["Caleb's Edited Story"])
        #expect(text.filter { $0.role == .body }.map(\.text) == ["An edited subtitle."])
        #expect(migrated.elements.first { $0.id == titleID } == originalTitle)
        #expect(migrated.elements.contains { $0.id == noteID })
        #expect(migrated.semanticTemplateVersion == BookInteriorPageDocumentFactory.semanticTemplateVersion)
    }

    @Test func semanticMigrationUpdatesAnUneditedVersionTwoTitleLayout() throws {
        let oldTitleFrame = NormalizedPageRect(x: 0.09, y: 0.27, width: 0.82, height: 0.20)
        let oldBodyFrame = NormalizedPageRect(x: 0.16, y: 0.51, width: 0.68, height: 0.13)
        var legacy = BookPageDocument(
            pageAspectRatio: 11.0 / 8.5,
            semanticTemplate: .interiorTitle,
            semanticTemplateVersion: 2
        )
        let titleID = try legacy.addText(
            "Caleb's Edited Story",
            frame: oldTitleFrame,
            role: .title,
            typographyPreset: .realistic
        )
        legacy.updateFontSize(id: titleID, fontSize: 0.10)
        legacy.updateTextAlignment(id: titleID, alignment: .center)
        let bodyID = try legacy.addText(
            "An edited subtitle.",
            frame: oldBodyFrame,
            role: .body,
            typographyPreset: .realistic
        )
        legacy.updateFontSize(id: bodyID, fontSize: 0.043)
        legacy.updateTextAlignment(id: bodyID, alignment: .center)

        let migrated = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            title: "Grandparent's Memoir",
            body: "A collection of memories.",
            subtitle: nil,
            pageAspectRatio: 11.0 / 8.5,
            typographyPreset: .realistic,
            isKidsBook: false,
            background: nil,
            preservingEditableElementsFrom: legacy
        )
        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: 11.0 / 8.5,
            isKidsBook: false
        )
        let migratedTitle = try #require(migrated.elements.first { element in
            guard case .text(let text) = element.content else { return false }
            return text.role == .title
        })
        let migratedTitleText: BookPageTextContent? = {
            guard case .text(let text) = migratedTitle.content else { return nil }
            return text
        }()
        let resolvedTitleText = try #require(migratedTitleText)

        #expect(migratedTitle.frame == layout.titleFrame)
        #expect(resolvedTitleText.text == "Caleb's Edited Story")
        #expect(resolvedTitleText.fontSize == layout.titleFontSize)
        #expect(resolvedTitleText.alignment == .center)
        #expect(migrated.semanticTemplateVersion == BookInteriorPageDocumentFactory.semanticTemplateVersion)
    }

    @Test func semanticMigrationPreservesCustomizedVersionTwoTypography() throws {
        let oldTitleFrame = NormalizedPageRect(x: 0.09, y: 0.27, width: 0.82, height: 0.20)
        var legacy = BookPageDocument(
            pageAspectRatio: 11.0 / 8.5,
            semanticTemplate: .interiorTitle,
            semanticTemplateVersion: 2
        )
        let titleID = try legacy.addText(
            "A Different Typeface",
            frame: oldTitleFrame,
            role: .title,
            typographyPreset: .comic
        )
        legacy.updateFontSize(id: titleID, fontSize: 0.10)
        legacy.updateTextAlignment(id: titleID, alignment: .center)

        let migrated = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            title: "Grandparent's Memoir",
            body: "",
            subtitle: nil,
            pageAspectRatio: 11.0 / 8.5,
            typographyPreset: .realistic,
            isKidsBook: false,
            background: nil,
            preservingEditableElementsFrom: legacy
        )
        let migratedTitle = try #require(migrated.elements.first { $0.id == titleID })
        let migratedText: BookPageTextContent? = {
            guard case .text(let text) = migratedTitle.content else { return nil }
            return text
        }()

        #expect(migratedTitle.frame == oldTitleFrame)
        #expect(try #require(migratedText).typographyPreset == .comic)
    }

    @Test func partialSemanticTitleDocumentStillRequiresDeterministicMigration() throws {
        var partial = BookPageDocument(pageAspectRatio: 8.5 / 11)
        _ = try partial.addText("Grandparent's Memoir", role: .title, typographyPreset: .realistic)

        #expect(BookInteriorPageDocumentFactory.requiresSemanticMigration(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            document: partial
        ))

        let migrated = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            title: "Grandparent's Memoir",
            body: "A collection of memories.",
            subtitle: nil,
            pageAspectRatio: 8.5 / 11,
            typographyPreset: .realistic,
            isKidsBook: false,
            background: nil,
            preservingEditableElementsFrom: partial
        )
        let matchingTitles = migrated.elements.filter { element in
            guard case .text(let text) = element.content else { return false }
            return text.role == .title && text.text == "Grandparent's Memoir"
        }

        #expect(matchingTitles.count == 1)
        #expect(!BookInteriorPageDocumentFactory.requiresSemanticMigration(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            document: migrated
        ))
    }

    @Test func closingPageFactoryExposesBothVisiblePhrasesAsText() throws {
        let document = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.closingPageMemoryId,
            title: "Made with Memoir",
            body: "",
            subtitle: "Grandparent",
            pageAspectRatio: 8.5 / 11,
            typographyPreset: .realistic,
            isKidsBook: false,
            background: nil
        )
        let text = document.elements.compactMap { element -> BookPageTextContent? in
            guard case .text(let content) = element.content else { return nil }
            return content
        }

        #expect(text.contains { $0.text == "Made with Memoir" })
        #expect(text.contains { $0.text == "Download on the App Store" && $0.color == .white })
        #expect(!text.contains { $0.text == "Grandparent" })
        #expect(document.semanticTemplate == .interiorClosing)
        #expect(document.semanticTemplateVersion == BookInteriorPageDocumentFactory.semanticTemplateVersion)

        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: 8.5 / 11,
            isKidsBook: false
        )
        let heading = try #require(document.elements.first { element in
            guard case .text(let content) = element.content else { return false }
            return content.role == .title
        })
        let store = try #require(document.elements.first { element in
            guard case .text(let content) = element.content else { return false }
            return content.role == .body
        })
        #expect(heading.frame == layout.closingHeadingFrame)
        #expect(store.frame == layout.closingStoreTextFrame)
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
