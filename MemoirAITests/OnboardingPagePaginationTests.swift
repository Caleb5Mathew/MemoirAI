import XCTest
@testable import MemoirAI

final class OnboardingPagePaginationTests: XCTestCase {
    func testBookPaginationUsesExportedLandscapeBodyFrame() {
        let story = String(repeating: "We spent the afternoon building a fort beneath the tree. ", count: 100)
        let layout = BookPageCanonicalLayout.text(isLandscape: true, hasTitle: true, hasSubtitle: false)
        let expected = OnboardingPagePagination.pages(
            story, width: 792 * layout.bodyFrame.width, height: 612 * layout.bodyFrame.height - 1
        )
        XCTAssertEqual(OnboardingPagePagination.bookPages(story), expected)
        XCTAssertEqual(expected.joined(), story)
    }

    func testTypicalNinetySecondMemoryFitsActualBookPage() {
        let story = String(repeating: "I remember the summer we built a fort beneath the old apple tree. ", count: 15)
        XCTAssertEqual(OnboardingPagePagination.bookPages(story), [story])
    }

    func testEmptyBookPageRemainsRenderable() {
        XCTAssertEqual(OnboardingPagePagination.bookPages(""), [""])
    }

    func testLongMemoryPreservesEveryCharacterAcrossPages() {
        let story = String(repeating: "When I was eight, we made a fort beneath the old tree.\n", count: 35)
        let pages = OnboardingPagePagination.pages(story, width: 300, height: 140)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.joined(), story)
        XCTAssertTrue(pages.allSatisfy { !$0.isEmpty })
    }

    func testShortMemoryFitsOnePage() {
        let story = "We built a fort beneath the old tree."
        XCTAssertEqual(OnboardingPagePagination.pages(story, width: 300, height: 140), [story])
    }

    func testMoreSpaceDoesNotCreateMorePages() {
        let story = String(repeating: "I remember the rain on the roof. ", count: 30)
        let smaller = OnboardingPagePagination.pages(story, width: 260, height: 100)
        let larger = OnboardingPagePagination.pages(story, width: 340, height: 180)
        XCTAssertLessThanOrEqual(larger.count, smaller.count)
        XCTAssertEqual(larger.joined(), story)
    }
}
