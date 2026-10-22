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
        #expect(landscapeIllustration.imageFrame == NormalizedPageRect(x: 0, y: 0.10, width: 1, height: 0.90))
        #expect(landscapeIllustration.imageFit == .fill)

        let landscapeText = BookPageCanonicalLayout.text(
            isLandscape: true,
            hasTitle: true,
            hasSubtitle: false
        )
        #expect(landscapeText.titleFrame?.y == Double(BookInteriorStyle.memoryTitleY))
        #expect(landscapeText.bodyFrame.y == Double(BookInteriorStyle.memoryBodyY))
        #expect(landscapeText.bodyFrame.height == Double(BookInteriorStyle.memoryBodyHeight))

        let portraitText = BookPageCanonicalLayout.text(
            isLandscape: false,
            hasTitle: true,
            hasSubtitle: true
        )
        #expect(portraitText.titleFrame?.x == Double(BookInteriorStyle.memoryHorizontalInset))
        #expect(portraitText.subtitleFrame == nil)
        #expect(portraitText.bodyFrame.y == Double(BookInteriorStyle.memoryBodyY))
        #expect(portraitText.bodyFrame.height == Double(BookInteriorStyle.memoryBodyHeight))
        #expect(
            landscapeText.bodyFrame.y + landscapeText.bodyFrame.height
                < Double(BookInteriorStyle.memoryPageNumberY)
        )
    }

    @Test func canonicalTextDocumentDetectionProtectsUserEdits() throws {
        let title = "Sandfall at Silvestrom"
        let body = "The sand fell slowly while we listened to the ocean."
        var document = BookPageDocument(pageAspectRatio: 11.0 / 8.5)
        let titleID = try document.addText(
            title,
            frame: NormalizedPageRect(x: 0.10, y: 0.15, width: 0.80, height: 0.08),
            role: .title,
            typographyPreset: .kidsBook
        )
        document.updateFontSize(id: titleID, fontSize: 0.054)
        let bodyID = try document.addText(
            body,
            frame: NormalizedPageRect(x: 0.10, y: 0.31, width: 0.80, height: 0.57),
            role: .body,
            typographyPreset: .kidsBook
        )
        document.updateFontSize(id: bodyID, fontSize: 0.0265)

        #expect(BookPageCanonicalLayout.isUntouchedGeneratedTextDocument(
            document,
            body: body,
            title: title,
            typographyPreset: .kidsBook,
            isLandscape: true
        ))

        var tighterDocument = BookPageDocument(pageAspectRatio: 11.0 / 8.5)
        let tighterTitleID = try tighterDocument.addText(
            title,
            frame: NormalizedPageRect(x: 0.09, y: 0.115, width: 0.82, height: 0.075),
            role: .title,
            typographyPreset: .kidsBook
        )
        tighterDocument.updateFontSize(id: tighterTitleID, fontSize: 0.054)
        let tighterBodyID = try tighterDocument.addText(
            body,
            frame: NormalizedPageRect(x: 0.09, y: 0.265, width: 0.82, height: 0.66),
            role: .body,
            typographyPreset: .kidsBook
        )
        tighterDocument.updateFontSize(id: tighterBodyID, fontSize: 0.023)
        #expect(BookPageCanonicalLayout.isUntouchedGeneratedTextDocument(
            tighterDocument,
            body: body,
            title: title,
            typographyPreset: .kidsBook,
            isLandscape: true
        ))

        document.updateText(id: bodyID, text: body + " I added this myself.")
        #expect(!BookPageCanonicalLayout.isUntouchedGeneratedTextDocument(
            document,
            body: body,
            title: title,
            typographyPreset: .kidsBook,
            isLandscape: true
        ))
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

        #expect(landscape.titleFontSize == 0.099)
        #expect(kidsLandscape.titleFontSize == 0.099)
        #expect(portrait.titleFontSize == 0.070)
        #expect(landscape.titleFrame == NormalizedPageRect(x: 0.11, y: 0.24, width: 0.78, height: 0.27))
        #expect(landscape.closingIconFrame.y + landscape.closingIconFrame.height < landscape.closingHeadingFrame.y)
        #expect(landscape.closingHeadingFrame.y + landscape.closingHeadingFrame.height < landscape.closingStoreTextFrame.y)
        #expect(portrait.closingIconFrame.y + portrait.closingIconFrame.height < portrait.closingHeadingFrame.y)
        #expect(portrait.closingHeadingFrame.y + portrait.closingHeadingFrame.height < portrait.closingStoreTextFrame.y)
        #expect(landscape.closingBadgeFrame.width == 0.33)
        #expect(portrait.closingBadgeFrame.width == 0.49)
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
        #expect(resolvedTitleText.alignment == .leading)
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
        #expect(text.contains {
            $0.text == "Download on the App Store" && $0.color == .white && $0.alignment == .center
        })
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

    @Test func fieldnotesOpeningBreaksOnlyTheMemoirSuffix() {
        #expect(BookInteriorStyle.openingTitle("María’s Memoir") == "María’s\nMemoir")
        #expect(BookInteriorStyle.openingTitle("A Memoir About Home") == "A Memoir About Home")
        #expect(BookInteriorStyle.openingTitle("Memoir") == "Memoir")
    }

    @Test func fieldnotesBodyMeasurementDetectsOverflowAtTheCanonicalTypeSize() {
        let fontSize: CGFloat = 612 * BookInteriorStyle.bodySize
        let layout = BookPageCanonicalLayout.text(isLandscape: true, hasTitle: true, hasSubtitle: false)
        let width: CGFloat = 792 * layout.bodyFrame.width
        let height: CGFloat = 612 * layout.bodyFrame.height - 1
        #expect(BookInteriorTextLayout.height(of: "The first star.", width: width, fontSize: fontSize) < height)
        let text = Array(repeating: "I remember the orchard and every afternoon we spent there.", count: 65).joined(separator: " ")
        #expect(BookInteriorTextLayout.height(of: text, width: width, fontSize: fontSize) > height)
    }

    @Test func openingMigrationReplacesOnlyTheLegacyDefaultSubtitle() throws {
        for copy in ["A collection of memories from Alice’s life.", "My hand-written dedication"] {
            var legacy = BookPageDocument(pageAspectRatio: 11.0 / 8.5, semanticTemplate: .interiorTitle, semanticTemplateVersion: 3)
            let bodyID = try legacy.addText(copy, role: .body, typographyPreset: .kidsBook)
            let originalFrame = legacy.elements.first { $0.id == bodyID }?.frame
            let migrated = try BookInteriorPageDocumentFactory.make(
                memoryID: BookInteriorAnchor.titlePageMemoryId, title: "Alice’s Memoir", body: copy, subtitle: nil,
                pageAspectRatio: 11.0 / 8.5, typographyPreset: .kidsBook, isKidsBook: true,
                background: nil, preservingEditableElementsFrom: legacy
            )
            let element = try #require(migrated.elements.first { $0.id == bodyID })
            #expect(element.frame == originalFrame)
            guard case .text(let text) = element.content else { Issue.record("Missing opening text"); return }
            #expect(text.text == (copy.hasPrefix("A collection of memories from ") ? "A collection of life stories" : copy))

            let withoutDocument = try BookInteriorPageDocumentFactory.make(
                memoryID: BookInteriorAnchor.titlePageMemoryId, title: "Alice’s Memoir", body: copy, subtitle: nil,
                pageAspectRatio: 11.0 / 8.5, typographyPreset: .kidsBook, isKidsBook: true, background: nil
            )
            let bodyTexts = withoutDocument.elements.compactMap { element -> String? in
                guard case .text(let text) = element.content, text.role == .body else { return nil }
                return text.text
            }
            #expect(bodyTexts == [text.text])
        }
    }

    @Test func versionThreeOpeningMigrationPreservesCustomEditsAndUpdatesDefaults() throws {
        var old = BookPageDocument(pageAspectRatio: 11.0 / 8.5, semanticTemplate: .interiorTitle, semanticTemplateVersion: 3)
        let titleID = try old.addText("Alice’s Memoir", frame: NormalizedPageRect(x: 0.11, y: 0.29, width: 0.78, height: 0.17), role: .title, typographyPreset: .kidsBook)
        old.updateFontSize(id: titleID, fontSize: 0.09)
        old.updateTextAlignment(id: titleID, alignment: .center)
        let bodyID = try old.addText("My hand-written dedication", frame: NormalizedPageRect(x: 0.2, y: 0.65, width: 0.6, height: 0.12), role: .body, typographyPreset: .kidsBook)
        old.updateFontSize(id: bodyID, fontSize: 0.025)
        let savedBody = old.elements.first { $0.id == bodyID }
        let migrated = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.titlePageMemoryId, title: "Alice’s Memoir", body: "A collection of life stories", subtitle: nil,
            pageAspectRatio: 11.0 / 8.5, typographyPreset: .kidsBook, isKidsBook: true,
            background: nil, preservingEditableElementsFrom: old
        )
        #expect(migrated.elements.first { $0.id == bodyID } == savedBody)
        let title = try #require(migrated.elements.first { if case .text(let text) = $0.content { return text.role == .title }; return false })
        #expect(title.frame == BookInteriorPageDocumentFactory.layout(pageAspectRatio: 11.0 / 8.5, isKidsBook: true).titleFrame)
        if case .text(let text) = title.content {
            #expect(text.text == "Alice’s Memoir")
            #expect(text.alignment == .leading)
        }
    }

    @Test func versionFourClosingMigrationRestylesDefaultsAndPreservesCustomCopy() throws {
        let aspectRatio = 11.0 / 8.5
        let oldHeadingFrame = NormalizedPageRect(x: 0.20, y: 0.39, width: 0.60, height: 0.09)
        let oldStoreFrame = NormalizedPageRect(x: 0.39, y: 0.535, width: 0.25, height: 0.065)
        var old = BookPageDocument(
            pageAspectRatio: aspectRatio,
            semanticTemplate: .interiorClosing,
            semanticTemplateVersion: 4
        )
        let headingID = try old.addText(
            "Made with Memoir",
            frame: oldHeadingFrame,
            role: .title,
            typographyPreset: .kidsBook
        )
        old.updateFontSize(id: headingID, fontSize: 0.052)
        old.updateTextAlignment(id: headingID, alignment: .center)
        let storeID = try old.addText(
            "Download on the App Store",
            frame: oldStoreFrame,
            role: .body,
            typographyPreset: .kidsBook,
            color: .white
        )
        old.updateFontSize(id: storeID, fontSize: 0.024)
        old.updateTextAlignment(id: storeID, alignment: .center)

        let migrated = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.closingPageMemoryId,
            title: "Made with Memoir",
            body: "",
            subtitle: nil,
            pageAspectRatio: aspectRatio,
            typographyPreset: .kidsBook,
            isKidsBook: true,
            background: nil,
            preservingEditableElementsFrom: old
        )
        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: aspectRatio,
            isKidsBook: true
        )
        let text = migrated.elements.compactMap { element -> BookPageTextContent? in
            guard case .text(let content) = element.content else { return nil }
            return content
        }
        #expect(text.contains {
            $0.role == .title && $0.alignment == .center && $0.fontSize == layout.closingHeadingFontSize
        })
        #expect(text.contains {
            $0.role == .body && $0.alignment == .center && $0.color == .white
                && $0.fontSize == layout.closingStoreFontSize
        })

        var custom = old
        custom.updateText(id: headingID, text: "A hand-edited farewell")
        let customMigrated = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.closingPageMemoryId,
            title: "Made with Memoir",
            body: "",
            subtitle: nil,
            pageAspectRatio: aspectRatio,
            typographyPreset: .kidsBook,
            isKidsBook: true,
            background: nil,
            preservingEditableElementsFrom: custom
        )
        #expect(customMigrated.elements.contains { element in
            guard case .text(let content) = element.content else { return false }
            return content.role == .title && content.text == "A hand-edited farewell"
        })
    }

    @Test func versionFiveClosingMigrationRestoresFirebaseBookStyling() throws {
        let aspectRatio = 11.0 / 8.5
        var old = BookPageDocument(
            pageAspectRatio: aspectRatio,
            semanticTemplate: .interiorClosing,
            semanticTemplateVersion: 5
        )
        let headingID = try old.addText(
            "Made with Memoir",
            frame: NormalizedPageRect(x: 0.11, y: 0.42, width: 0.78, height: 0.16),
            role: .title,
            typographyPreset: .kidsBook
        )
        old.updateFontSize(id: headingID, fontSize: 0.075)
        old.updateTextAlignment(id: headingID, alignment: .leading)
        let storeID = try old.addText(
            "Download on the App Store",
            frame: NormalizedPageRect(x: 0.11, y: 0.63, width: 0.54, height: 0.07),
            role: .body,
            typographyPreset: .kidsBook,
            color: .ink
        )
        old.updateFontSize(id: storeID, fontSize: 0.028)
        old.updateTextAlignment(id: storeID, alignment: .leading)

        let migrated = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.closingPageMemoryId,
            title: "Made with Memoir",
            body: "",
            subtitle: nil,
            pageAspectRatio: aspectRatio,
            typographyPreset: .kidsBook,
            isKidsBook: true,
            background: nil,
            preservingEditableElementsFrom: old
        )
        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: aspectRatio,
            isKidsBook: true
        )
        let text = migrated.elements.compactMap { element -> (BookPageElement, BookPageTextContent)? in
            guard case .text(let content) = element.content else { return nil }
            return (element, content)
        }

        #expect(migrated.semanticTemplateVersion == 6)
        #expect(text.contains {
            $0.1.role == .title && $0.1.alignment == .center
                && $0.1.fontSize == layout.closingHeadingFontSize
                && $0.0.frame == layout.closingHeadingFrame
        })
        #expect(text.contains {
            $0.1.role == .body && $0.1.alignment == .center && $0.1.color == .white
                && $0.1.fontSize == layout.closingStoreFontSize
                && $0.0.frame == layout.closingStoreTextFrame
        })
    }

    @Test func versionFivePortraitClosingMigrationRestoresFirebaseBookStyling() throws {
        let aspectRatio = 8.5 / 11.0
        var old = BookPageDocument(
            pageAspectRatio: aspectRatio,
            semanticTemplate: .interiorClosing,
            semanticTemplateVersion: 5
        )
        let headingID = try old.addText(
            "Made with Memoir",
            frame: NormalizedPageRect(x: 0.11, y: 0.41, width: 0.78, height: 0.15),
            role: .title,
            typographyPreset: .kidsBook
        )
        old.updateFontSize(id: headingID, fontSize: 0.060)
        old.updateTextAlignment(id: headingID, alignment: .leading)
        let storeID = try old.addText(
            "Download on the App Store",
            frame: NormalizedPageRect(x: 0.11, y: 0.62, width: 0.68, height: 0.06),
            role: .body,
            typographyPreset: .kidsBook,
            color: .ink
        )
        old.updateFontSize(id: storeID, fontSize: 0.025)
        old.updateTextAlignment(id: storeID, alignment: .leading)

        let migrated = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.closingPageMemoryId,
            title: "Made with Memoir",
            body: "",
            subtitle: nil,
            pageAspectRatio: aspectRatio,
            typographyPreset: .kidsBook,
            isKidsBook: true,
            background: nil,
            preservingEditableElementsFrom: old
        )
        let layout = BookInteriorPageDocumentFactory.layout(
            pageAspectRatio: aspectRatio,
            isKidsBook: true
        )

        #expect(migrated.semanticTemplateVersion == 6)
        #expect(migrated.elements.contains { element in
            guard case .text(let content) = element.content else { return false }
            return content.role == .title && content.alignment == .center
                && content.fontSize == layout.closingHeadingFontSize
                && element.frame == layout.closingHeadingFrame
        })
        #expect(migrated.elements.contains { element in
            guard case .text(let content) = element.content else { return false }
            return content.role == .body && content.alignment == .center
                && content.color == .white && content.fontSize == layout.closingStoreFontSize
                && element.frame == layout.closingStoreTextFrame
        })
    }

    @MainActor @Test(arguments: [2, 5, 12])
    func longMemoriesAddPagesWithoutShrinkingOrLosingText(expectedPages: Int) {
        let model = StoryPageViewModel()
        let memoryID = UUID()
        for size in [CGSize(width: 792, height: 612), CGSize(width: 612, height: 792)] {
            let fontSize = size.height * BookInteriorStyle.bodySize
            let layout = BookPageCanonicalLayout.text(
                isLandscape: size.width > size.height,
                hasTitle: true,
                hasSubtitle: false
            )
            let bodyWidth = size.width * layout.bodyFrame.width
            let bodyHeight = size.height * layout.bodyFrame.height - 1
            let sentence = "On summer evenings we gathered beside the porch and watched the garden grow. "
            var paragraph = sentence
            while BookInteriorTextLayout.height(of: paragraph, width: bodyWidth, fontSize: fontSize) < bodyHeight * 0.65 {
                paragraph += sentence
            }
            let original = (1...expectedPages).map { "Memory detail \($0). " + paragraph }.joined(separator: "\n\n")
            let pages = model.paginateText(original, title: "The summer garden", subtitle: nil,
                pageHeight: size.height, pageWidth: size.width, memoryID: memoryID)
            #expect(pages.count == expectedPages)
            var bodies: [String] = []
            for (offset, page) in pages.enumerated() {
                guard case .textPage(let index, let total, let body, let title, _, let id) = page else {
                    Issue.record("Expected text page"); continue
                }
                #expect(index == offset + 1)
                #expect(total == expectedPages)
                #expect(id == memoryID)
                #expect(title == "The summer garden")
                #expect(BookInteriorTextLayout.height(of: body, width: bodyWidth, fontSize: fontSize) <= bodyHeight)
                bodies.append(body)
            }
            #expect(bodies.joined(separator: "\n\n") == original)
        }
    }

    @MainActor @Test func fieldnotesPaginationPreservesEveryWordAndFitsAllPages() {
        let model = StoryPageViewModel()
        let original = (0..<300).map { "Memory number \($0) holds a different detail about our childhood." }.joined(separator: " ")
        let pages = model.paginateText(original, title: "The first star", subtitle: nil, pageHeight: 612, pageWidth: 792, memoryID: UUID())
        let bodies = pages.compactMap { page -> String? in
            if case .textPage(_, _, let body, _, _, _) = page { return body }
            return nil
        }
        #expect(bodies.count > 1)
        #expect(bodies.joined(separator: " ").split(whereSeparator: { $0.isWhitespace }) == original.split(whereSeparator: { $0.isWhitespace }))
        for body in bodies {
            let layout = BookPageCanonicalLayout.text(isLandscape: true, hasTitle: true, hasSubtitle: false)
            #expect(BookInteriorTextLayout.height(
                of: body,
                width: 792 * layout.bodyFrame.width,
                fontSize: 612 * BookInteriorStyle.bodySize
            ) <= 612 * layout.bodyFrame.height - 1)
        }
    }

    @MainActor @Test func productionLengthMemoryPaginatesWithoutLosingText() {
        let original = """
        Chapter One. My earliest memory: the fall in sand. The world is very small when you are three years old, bounded by the edges of a mattress and the warm, heavy presence of your parents. It was 1972, and we were camping on the west coast of Cape Town at a place called Silvestrom. Home for those few days wasn't a tent, but a rondavel, a sturdy round house with thick walls and a high conical roof made of thatch grass. Inside, the night carried the trapped heat of the coastal summer day. It was thick, heavy, and restless. I lay trapped in that heat, sandwiched tightly between my mother and my father, while their breathing was slow and rhythmic, matching the distant dull roar of the Atlantic surf outside. Sleep wouldn't come to me. I tossed and turned, my small body sticky against the sheets, shifting in the narrow space between them. Looking up into the dark cone of the ceiling, I noticed something moving. From the gaps in the dried thatch overhead, fine grains of sand began to fall. They didn't drop all at once. They trickled down in quiet, delicate streams, like time slipping through an hourglass. And then the strange part happened. Even though the rondavel was dark, shrouded in the shadows of the night, the falling sand seemed to catch a light that shouldn't have been there. Each tiny grain shimmered as it cascaded towards us. Surrounded by a faint coastal glow, I watched it, mesmerized by the beautiful silent shower. But the wonder didn't last. As the glowing sand drifted down, a weight settled onto my ribs. The hot air in the room suddenly felt too thick to swallow. I tried to take a deep breath, but my chest locked up, tightening until it felt as though an invisible band was being cinched around my lungs. The comforting warmth of my parents' bodies suddenly felt suffocating. I couldn't draw enough air to call out. There, under the shimmering sand of the Silvestrom ceiling, my three-year-old self was experiencing the world narrowing down to a single, terrifying struggle to breathe. It was my first asthma attack.
        """
        let model = StoryPageViewModel()
        let pages = model.paginateText(
            original,
            title: "Sandfall at Silvestrom",
            subtitle: nil,
            pageHeight: 612,
            pageWidth: 792,
            memoryID: UUID()
        )

        let bodies = pages.compactMap { page -> String? in
            guard case .textPage(_, _, let body, _, _, _) = page else { return nil }
            return body
        }
        #expect(bodies.count == pages.count)
        #expect(
            bodies.joined(separator: " ").split(whereSeparator: { $0.isWhitespace })
                == original.split(whereSeparator: { $0.isWhitespace })
        )
        for body in bodies {
            #expect(BookInteriorTextLayout.height(
                of: body,
                width: 792 * BookInteriorStyle.memoryContentWidth,
                fontSize: 612 * BookInteriorStyle.bodySize
            ) <= 612 * BookInteriorStyle.memoryBodyHeight - 1)
        }
    }

    @MainActor @Test func legacyOverflowingTextPagesRepaginateWithoutLosingWords() {
        let model = StoryPageViewModel()
        let memoryID = UUID()
        let first = Array(repeating: "The sand fell slowly while we listened to the ocean.", count: 10).joined(separator: " ")
        let second = Array(repeating: "Then the room grew quiet and the story continued.", count: 10).joined(separator: " ")
        model.pageItems = [
            .textPage(index: 1, total: 2, body: first, title: "The fall in sand", subtitle: nil, memoryID: memoryID),
            .textPage(index: 2, total: 2, body: second, title: "The fall in sand", subtitle: nil, memoryID: memoryID)
        ]

        #expect(model.repaginateTextPagesForCurrentLayout())
        let pages = model.pageItems.compactMap { item -> String? in
            guard case .textPage(_, _, let body, _, _, _) = item else { return nil }
            return body
        }
        #expect(pages.count == 1)
        #expect(
            pages.joined(separator: " ").split(whereSeparator: { $0.isWhitespace })
                == [first, second].joined(separator: " ").split(whereSeparator: { $0.isWhitespace })
        )
        for body in pages {
            #expect(BookInteriorTextLayout.height(
                of: body,
                width: 792 * BookInteriorStyle.memoryContentWidth,
                fontSize: 612 * BookInteriorStyle.bodySize
            ) <= 612 * BookInteriorStyle.memoryBodyHeight - 1)
        }
    }

    @MainActor @Test func recoveredBookendsNeverGainMemoryChrome() throws {
        for anchor in [BookInteriorAnchor.titlePageMemoryId, BookInteriorAnchor.closingPageMemoryId] {
            let document = try BookInteriorPageDocumentFactory.make(
                memoryID: anchor, title: "Alice’s Memoir", body: "A collection of life stories", subtitle: nil,
                pageAspectRatio: 11.0 / 8.5, typographyPreset: .kidsBook, isKidsBook: true, background: nil
            )
            let baseline = try #require(BookPagePrintRenderer.render(document: document, pixelSize: CGSize(width: 792, height: 612)))
            let recovered = try #require(BookPagePrintRenderer.render(
                document: document, pixelSize: CGSize(width: 792, height: 612),
                memoryID: anchor, pageNumber: 2, isLandscape: true
            ))
            #expect(baseline.pngData() == recovered.pngData())
            #expect(!BookPageChromePolicy.showsChrome(document: document, memoryID: nil, isPrecomposed: false))
        }
        #expect(!BookPageChromePolicy.showsChrome(document: BookPageDocument(), memoryID: BookInteriorAnchor.blankPageMemoryId, isPrecomposed: false))
    }

    @MainActor @Test func recoveredIllustrationsUseHeaderInsteadOfStoryFooter() throws {
        let document = BookPageDocument(pageAspectRatio: 11.0 / 8.5)
        let size = CGSize(width: 792, height: 612)
        let baseline = try #require(BookPagePrintRenderer.render(document: document, pixelSize: size))
        let illustration = try #require(BookPagePrintRenderer.render(
            document: document, pixelSize: size, pageNumber: 4, isLandscape: true, isIllustration: true
        ))
        let story = try #require(BookPagePrintRenderer.render(document: document, pixelSize: size, pageNumber: 4, isLandscape: true))
        let bottom = CGRect(x: 0, y: 480, width: 792, height: 132)
        let baselineBottom = try #require(baseline.cgImage?.cropping(to: bottom))
        let illustrationBottom = try #require(illustration.cgImage?.cropping(to: bottom))
        let storyBottom = try #require(story.cgImage?.cropping(to: bottom))
        #expect(UIImage(cgImage: baselineBottom).pngData() == UIImage(cgImage: illustrationBottom).pngData())
        #expect(UIImage(cgImage: baselineBottom).pngData() != UIImage(cgImage: storyBottom).pngData())
        #expect(baseline.pngData() != illustration.pngData())
    }

    @Test func fullPageIllustrationDocumentsPreservePrecomposedArtwork() throws {
        let image = try BookPageImagePreparation.prepareForStorage(makeTestImageData())
        var document = BookPageDocument(pageAspectRatio: 11.0 / 8.5)
        _ = try document.addImage(image, frame: NormalizedPageRect(x: 0, y: 0, width: 1, height: 1))
        #expect(BookPageChromePolicy.isPrecomposedIllustration(document: document, isIllustration: true))
        #expect(!BookPageChromePolicy.isPrecomposedIllustration(document: document, isIllustration: false))
        #expect(!BookPageChromePolicy.showsChrome(document: document, memoryID: UUID(), isPrecomposed: true))
        _ = try document.addText("My title", role: .title)
        #expect(!BookPageChromePolicy.isPrecomposedIllustration(document: document, isIllustration: true))
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
