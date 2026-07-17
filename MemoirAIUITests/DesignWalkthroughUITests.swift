//
//  DesignWalkthroughUITests.swift
//  MemoirAIUITests
//
//  Drives the main screens and attaches full-screen screenshots for design review.
//  Not a behavioral assertion suite; failures should only mean navigation broke.
//

import XCTest

final class DesignWalkthroughUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWalkthroughScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        sleep(3)
        dismissSystemDialogIfPresent()
        snap(app, name: "01-home")

        // Saved Stories tab
        let savedTab = app.buttons["Saved Stories"]
        if savedTab.waitForExistence(timeout: 5) {
            savedTab.tap()
            sleep(2)
            snap(app, name: "02-saved-stories")
            app.buttons["Home"].tap()
            sleep(1)
        }

        // Storybook screen: scroll first so the card is clear of the floating tab bar.
        app.swipeUp()
        sleep(1)
        let yourBook = app.staticTexts["Your Book"]
        XCTAssertTrue(yourBook.waitForExistence(timeout: 5), "Your Book link should appear")
        yourBook.tap()
        sleep(3)
        snap(app, name: "03-storybook")

        // Profile setup sheet (headshot prefill check)
        var create = app.buttons["Create My Storybook"]
        if !create.waitForExistence(timeout: 3) {
            create = app.staticTexts["Create My Storybook"]
        }
        if create.waitForExistence(timeout: 3) {
            create.tap()
            sleep(2)
            snap(app, name: "04-profile-setup")
            app.swipeDown(velocity: .fast)
            sleep(1)
        }

        // Storybook settings
        let settingsButton = app.buttons["storybookSettingsButton"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            sleep(3)
            snap(app, name: "05-settings")
        }
    }

    /// Fresh simulators surface an iCloud sign in alert on first launch; dismiss it so
    /// screenshots show the app, not the system dialog.
    @MainActor
    private func dismissSystemDialogIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Not Now", "Cancel", "Later"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                sleep(1)
                return
            }
        }
    }

    @MainActor
    private func snap(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
