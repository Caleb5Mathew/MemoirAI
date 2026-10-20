import SwiftUI

import XCTest
import UIKit
@testable import MemoirAI

final class LinenThemeTests: XCTestCase {
    func testGreetingUsesWelcomeForMissingOrRolePlaceholderNames() {
        for name in ["", "  \n", "Grandparent", " GRANDPARENT ", "Parent", "Grandpa", "Dad", "Memoir"] {
            XCTAssertEqual(HomeGreeting.text(for: name), "Welcome to Memoir")
        }
    }

    func testGreetingPreservesRealNamesAndTrimsOuterWhitespace() {
        XCTAssertEqual(HomeGreeting.text(for: "Alex"), "Hello, Alex.")
        XCTAssertEqual(HomeGreeting.text(for: "  Rose Marie  "), "Hello, Rose Marie.")
        XCTAssertEqual(HomeGreeting.text(for: "Grandparent Rose"), "Hello, Grandparent Rose.")
        XCTAssertEqual(HomeGreeting.text(for: "José"), "Hello, José.")
    }

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
