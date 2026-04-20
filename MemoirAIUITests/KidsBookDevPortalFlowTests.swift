//
//  KidsBookDevPortalFlowTests.swift
//  MemoirAIUITests
//
//  Tests the Kids Book flow with developer portal: unlock dev mode, set Kid's Book,
//  Normal style reference, and Indian ethnicity. Run in Debug build so dev portal is available.
//

import XCTest

final class KidsBookDevPortalFlowTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Full flow: Home → Your Book → Settings → Dev portal unlock → Kid's Book + Normal → Create My Storybook → ProfileSetup (ethnicity Indian)
    @MainActor
    func testKidsBookDevPortalFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()

        // 1. Navigate to Your Book (StoryPage) - may need to scroll
        var yourBook = app.staticTexts["Your Book"]
        if !yourBook.waitForExistence(timeout: 5) {
            app.swipeUp() // Scroll down to reveal Your Book
            yourBook = app.staticTexts["Your Book"]
        }
        XCTAssertTrue(yourBook.waitForExistence(timeout: 5), "Your Book link should appear")
        yourBook.tap()

        // 2. Wait for StoryPage and tap Settings gear
        let settingsButton = app.buttons["storybookSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 8), "Settings gear should appear")
        settingsButton.tap()

        // 3. With -uitesting, dev sheet auto-shows; otherwise would tap Settings header 5+ times
        // Wait for Settings to fully load — the sheet is triggered from onAppear
        let settingsTitle = app.staticTexts["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 8), "Settings screen should appear")
        Thread.sleep(forTimeInterval: 2.5)

        // 4. Dev sheet should appear - enter password and unlock
        // Try identifier first, then placeholder, then first secure field
        var passwordField: XCUIElement = app.secureTextFields["devPasswordField"]
        if !passwordField.waitForExistence(timeout: 10) {
            passwordField = app.secureTextFields["Enter key"]
        }
        if !passwordField.waitForExistence(timeout: 3) {
            passwordField = app.secureTextFields.firstMatch
        }
        XCTAssertTrue(passwordField.waitForExistence(timeout: 3), "Dev password field should appear. Tap Settings header 5-7 times to open dev portal.")
        passwordField.tap()
        passwordField.typeText("Apologist123!")

        let unlockButton = app.buttons["devUnlockButton"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 2))
        unlockButton.tap()

        // 5. Wait for dev sheet to dismiss (success message, then sheet closes ~1s)
        sleep(2)

        // 6. Select Kid's Book art style (tap to ensure selected)
        let kidsBookButton = app.buttons["artStyle_Kid's Book"]
        XCTAssertTrue(kidsBookButton.waitForExistence(timeout: 3), "Kid's Book option should exist")
        kidsBookButton.tap()

        // 7. Select Normal in Style Reference (segmented control)
        let normalButton = app.buttons["Normal"]
        if normalButton.waitForExistence(timeout: 2) {
            normalButton.tap()
        }

        // 8. Dismiss Settings (tap back)
        let settingsBack = app.buttons["settingsBack"]
        XCTAssertTrue(settingsBack.waitForExistence(timeout: 2), "Settings back button should exist")
        settingsBack.tap()

        // 9. Tap Create My Storybook
        let createButton = app.buttons["createStorybookButton"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5), "Create My Storybook button should appear")
        createButton.tap()

        // 10. ProfileSetupView should appear - set ethnicity to Indian (headshot pre-filled via "old" asset)
        let ethnicityField = app.textFields["ethnicityRaceField"]
        XCTAssertTrue(ethnicityField.waitForExistence(timeout: 5), "ProfileSetup with ethnicity field should appear")
        ethnicityField.tap()
        ethnicityField.typeText("Indian")

        // 11. Tap Review Settings (opens SettingsViewWithGenerate)
        let reviewButton = app.buttons["reviewSettingsButton"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 3), "Review Settings button should appear")
        reviewButton.tap()

        // 12. Tap Save & Generate (triggers full book generation)
        let saveGenerateButton = app.buttons["saveAndGenerateButton"]
        XCTAssertTrue(saveGenerateButton.waitForExistence(timeout: 5), "Save & Generate button should appear")
        saveGenerateButton.tap()

        // 13. Validate generation flow started.
        // End-to-end completion can be backend/network dependent and flaky in UI test runs.
        let generationStartedText = app.staticTexts["Please keep the app open while we generate your storybook."].firstMatch
        let finalizingText = app.staticTexts["Finalizing cover and print assets..."].firstMatch
        let downloadButton = app.buttons["downloadStorybookButton"]
        let generationStarted = generationStartedText.waitForExistence(timeout: 30)
            || finalizingText.waitForExistence(timeout: 30)
            || downloadButton.waitForExistence(timeout: 30)
        
        XCTAssertTrue(
            generationStarted,
            "Expected generation to start (loading/finalizing) or complete (download button visible)."
        )
    }
}
