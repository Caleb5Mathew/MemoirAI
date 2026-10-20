import XCTest

final class StorybookMemoirNameUITests: XCTestCase {
    @MainActor
    func testSampleBookShowsPersonalizedOpeningAndMemoryPages() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestMemoirName", "-UITestSeedStorybook", "-UITestFieldnotesPreview"]
        app.launch()
        let next = app.buttons["storybookNextPage"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Retry cover"].waitForExistence(timeout: 3))
        let coverScreenshot = XCTAttachment(screenshot: app.screenshot())
        coverScreenshot.name = "fieldnotes-sample-cover"
        coverScreenshot.lifetime = .keepAlways
        add(coverScreenshot)
        next.tap()
        XCTAssertTrue(app.staticTexts["A collection of life stories"].waitForExistence(timeout: 5))
        next.tap()
        next.tap()
        XCTAssertTrue(app.staticTexts["The first star"].waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "When I was little")).firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "fieldnotes-simulator-story"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMissingNameCanBeCancelledThenSavedAndReused() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestMemoirName", "-UITestSeedStorybook"]
        app.launch()

        let newBook = app.buttons["New Book"]
        XCTAssertTrue(newBook.waitForExistence(timeout: 20))
        newBook.tap()
        let confirmation = app.alerts["Create a New Book?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Create New Book"].tap()
        let prompt = app.alerts["Whose memoir is this?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertFalse(prompt.buttons["Save & Continue"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "memoir-name-prompt"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        prompt.buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["testSavedMemoirName"].label, "Grandparent")

        newBook.tap()
        confirmation.buttons["Create New Book"].tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.textFields.firstMatch.tap()
        prompt.textFields.firstMatch.typeText("Margaret")
        XCTAssertTrue(prompt.buttons["Save & Continue"].isEnabled)
        prompt.buttons["Save & Continue"].tap()
        XCTAssertTrue(app.buttons["reviewSettingsButton"].waitForExistence(timeout: 5))
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(newBook.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["testSavedMemoirName"].label, "Margaret")
        newBook.tap()
        confirmation.buttons["Create New Book"].tap()
        XCTAssertTrue(app.buttons["reviewSettingsButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(prompt.exists)
    }
}
