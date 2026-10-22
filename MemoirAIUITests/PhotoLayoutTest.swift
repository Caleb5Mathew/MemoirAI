import XCTest

final class PhotoLayoutTest: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestResetMemoirMode", "-linen-preview", "-UITestSeedStorybook"]
        app.launch()
    }

    @MainActor
    func testBookPageEditorShowsPhotoImportControl() throws {
        let yourBook = app.buttons["tutorialYourBook"]
        XCTAssertTrue(yourBook.waitForExistence(timeout: 10))
        yourBook.tap()

        let nextPage = app.buttons["storybookNextPage"]
        XCTAssertTrue(nextPage.waitForExistence(timeout: 8))
        nextPage.tap()

        let edit = app.buttons["storybookEditCurrentPage"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        XCTAssertTrue(app.otherElements["freeformPageEditor"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Add Photos"].isHittable)
    }
}
