import SwiftUI

import XCTest
import UIKit
@testable import MemoirAI

final class LinenThemeTests: XCTestCase {
    func testEveryLinenFontIsBundledAndRegistered() {
        for name in ["Fraunces-Regular", "Fraunces-SemiBold", "DMSans-Regular", "DMSans-Medium", "DMSans-SemiBold", "DMSans-Bold"] {
            XCTAssertNotNil(UIFont(name: name, size: 16), "Missing font: \(name)")
        }
    }

    func testThemeSupportsAllInterfaceWeights() {
        _ = LinenTheme.heading()
        for weight: SwiftUI.Font.Weight in [.regular, .medium, .semibold, .bold, .heavy, .black] {
            _ = LinenTheme.body(16, weight: weight)
        }
    }
}
