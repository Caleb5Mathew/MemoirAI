import XCTest

final class ParenthoodPresentationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testChildNamesKeyboardLayoutAndCancelPreservesNames() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestResetMemoirMode", "-linen-preview", "-analytics-internal"]
        app.launch()
        let memoir = app.buttons["tutorialContinueYourMemoir"]
        XCTAssertTrue(memoir.waitForExistence(timeout: 10))
        memoir.tap()

        let change = app.buttons["memoirModeChangeButton"]
        if !change.waitForExistence(timeout: 3), !app.staticTexts["Who is this book for?"].exists {
            let parent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Parenthood")).firstMatch
            XCTAssertTrue(parent.waitForExistence(timeout: 3))
            parent.tap()
        }
        if !app.staticTexts["Who is this book for?"].exists {
            XCTAssertTrue(change.waitForExistence(timeout: 5))
            change.tap()
            let parent = app.buttons["memoirModeOption_parent"]
            XCTAssertTrue(parent.waitForExistence(timeout: 3))
            parent.tap()
        }
        openChildNamesIfNeeded(in: app)
        let fields = app.textFields
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 5))
        let originalValues = fields.allElementsBoundByIndex.map { $0.value as? String ?? "" }
        let originalCount = fields.count
        fields.firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Software keyboard must be visible to validate this layout")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardTutorialContinue = springboard.buttons["Continue"]
        if keyboardTutorialContinue.waitForExistence(timeout: 1) {
            keyboardTutorialContinue.tap()
        }
        let save = app.buttons["Save"]
        XCTAssertTrue(save.exists)
        XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        snapshot(app, "parenthood-child-names-keyboard")

        let add = app.buttons["Add another child"]
        if !add.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertEqual(fields.count, originalCount + 1)
        let remove = app.buttons["Remove child \(originalCount + 1)"]
        if !remove.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(remove.isHittable)
        XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
        remove.tap()
        XCTAssertEqual(fields.count, originalCount)

        if !add.isHittable { app.scrollViews.firstMatch.swipeUp() }
        add.tap()
        let addedField = fields.element(boundBy: originalCount)
        if !addedField.isHittable { app.scrollViews.firstMatch.swipeUp() }
        addedField.tap()
        addedField.typeText("Unsaved layout check")
        XCTAssertTrue(save.isEnabled)
        snapshot(app, "parenthood-child-names-unsaved-edit")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(change.waitForExistence(timeout: 3))
        openChildNamesIfNeeded(in: app)
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(fields.count, originalCount)
        XCTAssertEqual(fields.allElementsBoundByIndex.map { $0.value as? String ?? "" }, originalValues)
        snapshot(app, "parenthood-child-names-cancel-preserved")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testPaywallStatusBarScreenshotWithoutPurchasing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestResetMemoirMode", "-linen-preview", "-analytics-internal"]
        app.launch()
        let profile = app.buttons["Your profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        let settings = app.buttons["profileHubSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.staticTexts["settingsHeaderTitle"].waitForExistence(timeout: 5))
        let plans = app.buttons["View plans"]
        guard plans.waitForExistence(timeout: 5) else {
            throw XCTSkip("This account has subscription/developer access; the normal settings route does not offer View plans.")
        }
        if !plans.isHittable { app.swipeUp() }
        plans.tap()
        let restore = app.buttons["Restore Purchases"]
        let unavailable = app.staticTexts["Subscription unavailable"]
        let paywallLoaded = restore.waitForExistence(timeout: 30)
        if !paywallLoaded, unavailable.exists {
            throw XCTSkip("RevenueCat offerings are unavailable, so the real paywall cannot be reviewed")
        }
        XCTAssertTrue(paywallLoaded, "RevenueCat paywall should load before visual status-bar review")
        snapshot(app, "paywall-white-status-icons-review")
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(app.staticTexts["settingsHeaderTitle"].waitForExistence(timeout: 5))
        snapshot(app, "paywall-dismissed-status-icons-review")
    }

    @MainActor
    private func openChildNamesIfNeeded(in app: XCUIApplication) {
        if app.staticTexts["Who is this book for?"].waitForExistence(timeout: 1) { return }
        let change = app.buttons["memoirModeChangeButton"]
        XCTAssertTrue(change.waitForExistence(timeout: 3))
        change.tap()
        let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Add children", "Edit children")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()
        XCTAssertTrue(app.staticTexts["Who is this book for?"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
