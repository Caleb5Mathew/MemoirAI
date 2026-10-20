import XCTest
@testable import MemoirAI

final class OnboardingLayoutMetricsTests: XCTestCase {
    func testSmallPhoneReservesRoomForVoiceAndCTA() {
        let metrics = OnboardingLayoutMetrics(size: CGSize(width: 375, height: 667))
        XCTAssertEqual(metrics.setupWidth, 375)
        XCTAssertEqual(metrics.horizontalPadding, 20)
        XCTAssertEqual(metrics.recordHeadingSize, 28)
        XCTAssertEqual(metrics.textEditorHeight, 132)
        XCTAssertLessThanOrEqual(metrics.bookStageHeight + 390, 667)
        XCTAssertGreaterThanOrEqual(metrics.minimumHitTarget, 44)
        XCTAssertEqual(metrics.primaryButtonHeight, 56)
    }

    func testStandardPhoneKeepsTourStageAndReadableType() {
        let metrics = OnboardingLayoutMetrics(size: CGSize(width: 402, height: 874))
        XCTAssertEqual(metrics.setupWidth, 402)
        XCTAssertEqual(metrics.bookStageHeight, 310)
        XCTAssertEqual(metrics.recordHeadingSize, 30)
        XCTAssertEqual(metrics.revealHeadingSize, 28)
        XCTAssertEqual(metrics.textEditorHeight, 160)
    }

    func testTabletPortraitCapsColumnsAndPrintedPage() {
        let metrics = OnboardingLayoutMetrics(size: CGSize(width: 768, height: 1024))
        XCTAssertEqual(metrics.setupWidth, 520)
        XCTAssertEqual(metrics.tourWidth, 720)
        XCTAssertEqual(metrics.pageWidth, 640)
        XCTAssertEqual(metrics.bookStageHeight, 360)
        XCTAssertEqual(metrics.recordHeadingSize, 30)
    }

    func testTabletLandscapeDoesNotExpandTypeOrPage() {
        let portrait = OnboardingLayoutMetrics(size: CGSize(width: 768, height: 1024))
        let landscape = OnboardingLayoutMetrics(size: CGSize(width: 1024, height: 768))
        XCTAssertEqual(landscape.setupWidth, portrait.setupWidth)
        XCTAssertEqual(landscape.tourWidth, portrait.tourWidth)
        XCTAssertEqual(landscape.pageWidth, portrait.pageWidth)
        XCTAssertEqual(landscape.recordHeadingSize, portrait.recordHeadingSize)
        XCTAssertLessThan(landscape.bookStageHeight, portrait.bookStageHeight)
    }

    func testAccessibilityReservesMoreCaptionSpaceWithoutShrinkingType() {
        let standard = OnboardingLayoutMetrics(size: CGSize(width: 375, height: 667))
        let accessible = OnboardingLayoutMetrics(size: CGSize(width: 375, height: 667), accessibility: true)
        XCTAssertLessThan(accessible.bookStageHeight, standard.bookStageHeight)
        XCTAssertEqual(accessible.recordHeadingSize, standard.recordHeadingSize)
        XCTAssertEqual(accessible.minimumHitTarget, standard.minimumHitTarget)
    }

    func testKeyboardSizedViewportKeepsControlsUsable() {
        let metrics = OnboardingLayoutMetrics(size: CGSize(width: 375, height: 330))
        XCTAssertEqual(metrics.bookStageHeight, 120)
        XCTAssertEqual(metrics.textEditorHeight, 132)
        XCTAssertEqual(metrics.primaryButtonHeight, 56)
        XCTAssertGreaterThan(metrics.pageWidth, 0)
    }
}
