import XCTest

final class OnboardingEntryUITests: XCTestCase {
    @MainActor
    func testAccountPreparationFailureKeepsReconnectAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestResetMemoirMode", "-onboarding-replay", "-analytics-internal", "-UITestOnboardingAccountError"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Memoir couldn’t connect"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Reconnect"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Onboarding account recovery"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testTerminalPreviewErrorOffersAnExitInsteadOfAnImpossibleRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestResetMemoirMode", "-onboarding-replay", "-analytics-internal", "-UITestOnboardingPreviewError"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your preview isn’t ready"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Continue to my memories"].isHittable)
        XCTAssertFalse(app.buttons["Try again"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Onboarding terminal preview recovery"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testFirstStoryExplainsHowToContinueWithoutGenerating() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestResetMemoirMode", "-onboarding-replay", "-analytics-internal"]
        app.launch()
        let audience = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "My life story")).firstMatch
        if app.buttons["Continue story"].waitForExistence(timeout: 15) {
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["Continue saved story"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.textViews.firstMatch.isHittable, "A competing draft must not accept unsaved edits")
            let recovery = XCTAttachment(screenshot: app.screenshot())
            recovery.name = "Onboarding saved draft protection"
            recovery.lifetime = .keepAlways
            add(recovery)
            app.buttons["Continue saved story"].tap()
            XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
            let restored = XCTAttachment(screenshot: app.screenshot())
            restored.name = "Onboarding restored draft before navigation"
            restored.lifetime = .keepAlways
            add(restored)
            let back = app.buttons["Back"]
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: back)
            waitForExpectations(timeout: 5)
            back.tap()
            XCTAssertTrue(app.textFields["First name"].waitForExistence(timeout: 5))
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: back)
            waitForExpectations(timeout: 5)
            back.tap()
        }
        XCTAssertTrue(audience.waitForExistence(timeout: 30))
        let ready = NSPredicate(format: "hittable == true")
        expectation(for: ready, evaluatedWith: audience)
        waitForExpectations(timeout: 30)
        audience.tap()
        app.buttons["Continue"].tap()
        let name = app.textFields["First name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let oldName = name.value as? String ?? ""
        if oldName.isEmpty || oldName == "First name" {
            name.tap()
            name.typeText("Test")
        }
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Record or write your memory"].waitForExistence(timeout: 5))
        let empty = XCTAttachment(screenshot: app.screenshot())
        empty.name = "Onboarding first-story input"
        empty.lifetime = .keepAlways
        add(empty)
        let editor = app.textViews.firstMatch
        app.buttons["onboardingWriteInstead"].tap()
        let existingText = editor.value as? String ?? ""
        if !existingText.isEmpty {
            guard ["I remember", "We spent every summer afternoon beside the lake."].contains(existingText) else {
                XCTFail("Refusing to replace a story not created by this test suite")
                return
            }
            editor.press(forDuration: 1.2)
            let selectAll = app.buttons["Select All"].exists ? app.buttons["Select All"] : app.menuItems["Select All"]
            XCTAssertTrue(selectAll.waitForExistence(timeout: 3))
            selectAll.tap()
            editor.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        editor.typeText("I remember")
        let hint = app.staticTexts["Add a little more detail — at least six words — to make your first page."]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertTrue(editor.isHittable, "The story editor must stay visible while typing")
        XCTAssertTrue(editor.frame.maxY <= hint.frame.minY, "The editor must remain above its validation message")
        XCTAssertTrue(hint.isHittable, "The reason Continue is disabled must remain visible while typing")
        XCTAssertFalse(app.buttons["Use this memory"].isEnabled)
        let validation = XCTAttachment(screenshot: app.screenshot())
        validation.name = "Onboarding short-story guidance"
        validation.lifetime = .keepAlways
        add(validation)
    }
}
