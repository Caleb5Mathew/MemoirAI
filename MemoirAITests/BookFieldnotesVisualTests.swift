import CoreImage
import SwiftUI
import UIKit
import XCTest
@testable import MemoirAI

@MainActor
final class BookFieldnotesVisualTests: XCTestCase {
    func testInteriorPagesRenderAtPrintSizeWithScannableAppLink() throws {
        XCTAssertNotNil(UIFont(name: "GillSans", size: 20))
        XCTAssertNotNil(UIFont(name: "Georgia", size: 16))
        let size = CGSize(width: 792, height: 612)
        let opening = try render(MemoirCoverFrontPage(
            title: "Margaret’s Memoir",
            subtitle: "A collection of life stories",
            frameWidth: size.width,
            frameHeight: size.height,
            isKidsBook: true
        ), size: size, name: "fieldnotes-opening")
        let ciImage = try XCTUnwrap(CIImage(image: opening))
        let detector = try XCTUnwrap(CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ))
        let links = detector.features(in: ciImage).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertTrue(links.contains(MemoryLinks.appStoreURL.absoluteString), "The printed app QR must remain scannable")

        let background = try render(MemoirCoverFrontPage(
            title: "", subtitle: "", frameWidth: size.width,
            frameHeight: size.height, isKidsBook: true
        ), size: size, name: "fieldnotes-opening-background")
        let storedBackground = try BookPageImagePreparation.prepareForStorage(
            XCTUnwrap(background.pngData()), accessibilityDescription: "Opening background",
            fit: .fill, source: .pageBackground, maximumPixelCount: 2_000_000
        )
        let document = try BookInteriorPageDocumentFactory.make(
            memoryID: BookInteriorAnchor.titlePageMemoryId, title: "Margaret’s Memoir",
            body: "A collection of life stories", subtitle: nil,
            pageAspectRatio: Double(size.width / size.height), typographyPreset: .kidsBook,
            isKidsBook: true, background: storedBackground
        )
        let editable = try XCTUnwrap(BookPagePrintRenderer.render(
            document: document, pixelSize: CGSize(width: 1584, height: 1224),
            memoryID: BookInteriorAnchor.titlePageMemoryId, pageNumber: 1, isLandscape: true
        ))
        let editableAttachment = XCTAttachment(image: editable)
        editableAttachment.name = "fieldnotes-editable-opening-export"
        editableAttachment.lifetime = .keepAlways
        add(editableAttachment)
        let editableQR = detector.features(in: try XCTUnwrap(CIImage(image: editable)))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertTrue(editableQR.contains(MemoryLinks.appStoreURL.absoluteString))

        let illustration = try XCTUnwrap(UIImage(named: "grandparent-illustration"))
        let memoryID = UUID()
        _ = try render(KidsBookIllustrationPage(
            image: illustration,
            memoryID: memoryID,
            title: "The first star",
            frameWidth: size.width,
            frameHeight: size.height,
            pageNumber: 4
        ), size: size, name: "fieldnotes-illustration")
        _ = try render(KidsBookTextPage(
            index: 1,
            total: 1,
            text: "When I was little, Grandpa always saved me a place beside him on the porch. I would climb onto the wooden bench, my feet still too short to reach the ground.\n\nOne evening, the sky turned the color of peaches. He pointed to the first star and told me that he used to sit right there with his own father.\n\nWe stayed until the garden grew quiet. I don’t remember everything we talked about that night. But I remember how it felt to sit beside him.",
            title: "The first star",
            subtitle: "Childhood",
            memoryID: memoryID,
            fontStyle: .kidsBook,
            frameWidth: size.width,
            frameHeight: size.height,
            pageNumber: 5
        ), size: size, name: "fieldnotes-story")
        _ = try render(MemoirCoverFrontPage(
            title: "María Fernanda Rodríguez’s Memoir",
            subtitle: "A collection of life stories",
            frameWidth: size.width,
            frameHeight: size.height,
            isKidsBook: true
        ), size: size, name: "fieldnotes-long-name")
        _ = try render(MemoirCoverBackPage(
            subtitle: "Margaret",
            frameWidth: size.width,
            frameHeight: size.height
        ), size: size, name: "fieldnotes-closing")
    }

    func testLongMemoryRendersAcrossManyPagesAtNormalTypeSize() throws {
        let model = StoryPageViewModel()
        let memoryID = UUID()
        let original = (1...120).map { "That summer, memory \($0) began on the porch. We carried water into the garden and watched the sunflowers grow taller every day." }.joined(separator: " ")
        let pages = model.paginateText(original, title: "A summer in the garden", subtitle: nil,
            pageHeight: 612, pageWidth: 792, memoryID: memoryID)
        XCTAssertGreaterThanOrEqual(pages.count, 5)
        let layout = BookPageCanonicalLayout.text(isLandscape: true, hasTitle: true, hasSubtitle: false)
        for offset in [0, pages.count / 2, pages.count - 1] {
            guard case .textPage(let index, let total, let body, let title, let subtitle, _) = pages[offset] else {
                XCTFail("Expected text page"); continue
            }
            XCTAssertLessThanOrEqual(
                BookInteriorTextLayout.height(
                    of: body,
                    width: 792 * layout.bodyFrame.width,
                    fontSize: 612 * BookInteriorStyle.bodySize
                ),
                612 * layout.bodyFrame.height - 1
            )
            _ = try render(KidsBookTextPage(index: index, total: total, text: body,
                title: title, subtitle: subtitle, memoryID: memoryID, fontStyle: .kidsBook,
                frameWidth: 792, frameHeight: 612, pageNumber: offset + 3),
                size: CGSize(width: 792, height: 612), name: "long-memory-page-\(index)-of-\(total)")
        }
    }

    private func render<Content: View>(_ content: Content, size: CGSize, name: String) throws -> UIImage {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
        XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }
}
