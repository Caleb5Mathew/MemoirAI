import XCTest
import SwiftUI
@testable import MemoirAI

final class OnboardingMeetAlexTests: XCTestCase {
    func testPhoneUsesFullWidthPortraitWithReadableCopy() {
        let layout = MeetAlexComposition(size: CGSize(width: 390, height: 760), accessibility: false)
        XCTAssertFalse(layout.isLandscape)
        XCTAssertEqual(layout.contentWidth, 390)
        XCTAssertGreaterThanOrEqual(layout.minimumPortraitSpace, 150)
        XCTAssertEqual(layout.headingSize, 85.8, accuracy: 0.01)
    }

    func testCompactPhoneLeavesRoomForNavigationAndAction() {
        let layout = MeetAlexComposition(size: CGSize(width: 320, height: 548), accessibility: false)
        XCTAssertEqual(layout.headingSize, 70.4, accuracy: 0.01)
        XCTAssertLessThanOrEqual(layout.minimumPortraitSpace + layout.copyHeight + 44 + 100, 548)
        XCTAssertEqual(layout.horizontalPadding, 22)
    }

    func testLandscapeKeepsCopyInRightColumn() {
        let layout = MeetAlexComposition(size: CGSize(width: 844, height: 390), accessibility: false)
        XCTAssertTrue(layout.isLandscape)
        XCTAssertLessThanOrEqual(layout.contentWidth, 460)
        XCTAssertEqual(layout.minimumPortraitSpace, 12)
        XCTAssertEqual(layout.copyHeight, 180)
    }

    func testTabletCapsReadingWidthWithoutCappingPortrait() {
        let layout = MeetAlexComposition(size: CGSize(width: 834, height: 1100), accessibility: false)
        XCTAssertEqual(layout.contentWidth, 560)
        XCTAssertFalse(layout.isLandscape)
    }

    func testAccessibilityGivesScrollableCopyMoreRoom() {
        let size = CGSize(width: 390, height: 760)
        let regular = MeetAlexComposition(size: size, accessibility: false)
        let accessible = MeetAlexComposition(size: size, accessibility: true)
        XCTAssertLessThan(accessible.minimumPortraitSpace, regular.minimumPortraitSpace)
        XCTAssertGreaterThan(accessible.copyHeight, regular.copyHeight)
        XCTAssertEqual(accessible.headingSize, 48)
    }
}
