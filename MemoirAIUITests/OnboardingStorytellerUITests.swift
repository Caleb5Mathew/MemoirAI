import XCTest

final class OnboardingStorytellerUITests: XCTestCase {
    @MainActor
    func testTypingKeepsSpeakerRequirementVisibleAndEnablesValidStory() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestResetMemoirMode", "-onboarding-replay", "-analytics-internal"]
        app.launch()
        let audience = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "My parent or grandparent")).firstMatch
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
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: audience)
        waitForExpectations(timeout: 30)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "My life story")).firstMatch.tap()
        audience.tap()
        app.buttons["Continue"].tap()
        let name = app.textFields["First name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        if (name.value as? String ?? "").isEmpty || name.value as? String == "First name" {
            name.tap()
            name.typeText("Test")
        }
        app.buttons["Continue"].tap()

        let explanation = app.staticTexts["Choose who is telling this story to continue."]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertTrue(explanation.isHittable)
        XCTAssertFalse(app.buttons["Start recording"].isEnabled)
        XCTAssertFalse(app.buttons["Use this memory"].isEnabled)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Onboarding storyteller requirement"
        before.lifetime = .keepAlways
        add(before)

        app.buttons["onboardingWriteInstead"].tap()
        let editor = app.textViews.firstMatch
        let existingText = editor.value as? String ?? ""
        let knownTestStory = "We spent every summer afternoon beside the lake."
        guard existingText.isEmpty || existingText == "I remember" || existingText == knownTestStory else {
            XCTFail("Refusing to replace a story that was not created by this UI test suite")
            return
        }
        if !existingText.isEmpty {
            editor.press(forDuration: 1.2)
            let selectAll = app.buttons["Select All"].exists ? app.buttons["Select All"] : app.menuItems["Select All"]
            XCTAssertTrue(selectAll.waitForExistence(timeout: 3))
            selectAll.tap()
            editor.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        editor.typeText(knownTestStory)
        XCTAssertFalse(app.buttons["Use this memory"].isEnabled,
                       "Typing a valid story must not bypass narrator attribution")
        XCTAssertTrue(explanation.isHittable, "The reason Continue is disabled must remain visible while typing")
        let speaker = app.buttons["I’ll tell it"]
        XCTAssertTrue(speaker.exists)
        speaker.tap()
        XCTAssertTrue(app.buttons["Use this memory"].isEnabled)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "Onboarding typed story ready with speaker"
        after.lifetime = .keepAlways
        add(after)
    }
}
