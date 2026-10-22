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
    func testLinenNavigationKeepsBothDestinationsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-linen-preview"]
        app.launch()

        let home = app.buttons["linenHomeTab"]
        let saved = app.buttons["linenSavedStoriesTab"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        XCTAssertTrue(saved.isHittable)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Only the custom Linen navigation should be visible")
        XCTAssertGreaterThanOrEqual(home.frame.height, 44)
        XCTAssertGreaterThanOrEqual(saved.frame.height, 44)

        saved.tap()
        let allFilter = app.buttons["memoirFilter_all"]
        XCTAssertTrue(allFilter.waitForExistence(timeout: 5))
        XCTAssertTrue(allFilter.isHittable)
        XCTAssertFalse(app.staticTexts["Memories"].exists)
        let sort = app.buttons["Sort memories"]
        XCTAssertTrue(sort.isHittable)
        XCTAssertLessThan(abs(allFilter.frame.midY - sort.frame.midY), 3)
        let create = app.buttons["createNewMemoryButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isHittable)
        XCTAssertLessThanOrEqual(create.frame.maxY, saved.frame.minY)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        home.tap()
        XCTAssertTrue(app.buttons["tutorialContinueYourMemoir"].waitForExistence(timeout: 5))
        let book = app.buttons["tutorialYourBook"]
        if !book.isHittable { app.swipeUp() }
        XCTAssertTrue(book.isHittable)
        XCTAssertLessThanOrEqual(book.frame.width, 512)
        XCTAssertGreaterThanOrEqual(book.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(book.frame.maxX, app.frame.maxX)
        XCTAssertTrue(app.buttons["Switch profiles"].isHittable)
        XCTAssertTrue(app.buttons["Your profile"].isHittable)
        snap(app, name: "linen-home-proportions")
    }

    @MainActor
    func testEmptyBookEntryAndRapidRepeatedNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-linen-preview"]
        app.launch()
        let home = app.buttons["linenHomeTab"]
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        home.tap()
        let book = app.buttons["tutorialYourBook"]
        for _ in 0..<4 {
            XCTAssertTrue(book.waitForExistence(timeout: 5))
            if !book.isHittable { app.swipeUp() }
            book.doubleTap()
            let back = app.buttons["Back"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["createStorybookButton"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Opening your book…"].exists)
            back.tap()
            XCTAssertTrue(book.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(book.isHittable)
        }
    }

    @MainActor
    func testYourBookRepeatedNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-linen-preview", "-UITestSeedStorybook"]
        app.launch()
        let home = app.buttons["linenHomeTab"]
        if home.waitForExistence(timeout: 5) { home.tap() }
        let yourBook = app.buttons["tutorialYourBook"]
        XCTAssertTrue(yourBook.waitForExistence(timeout: 10))
        app.swipeUp()

        for _ in 0..<5 {
            yourBook.tap()
            let edit = app.buttons["storybookEditCurrentPage"]
            XCTAssertTrue(edit.waitForExistence(timeout: 10))
            XCTAssertTrue(edit.isHittable)
            XCTAssertFalse(app.buttons["createStorybookButton"].exists)

            app.buttons["Back"].tap()
            XCTAssertTrue(yourBook.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(yourBook.isHittable)
        }
    }

    @MainActor
    func testAllNormalChapterPathMarkers() throws {
        for chapterNumber in 1...10 {
            let app = XCUIApplication()
            app.launchArguments = ["-UITest", "-UITestNormalChapter", "\(chapterNumber)"]
            app.launch()
            XCTAssertTrue(app.staticTexts["chapterJourneyTitle"].waitForExistence(timeout: 8))
            let nodes = app.descendants(matching: .any).matching(identifier: "chapterPromptNode")
            XCTAssertEqual(nodes.count, 4)
            for node in nodes.allElementsBoundByIndex {
                XCTAssertGreaterThanOrEqual(node.frame.width, 44)
                XCTAssertGreaterThanOrEqual(node.frame.minX, app.frame.minX)
                XCTAssertLessThanOrEqual(node.frame.maxX, app.frame.maxX)
            }
            snap(app, name: String(format: "normal-path-%02d", chapterNumber))
            app.terminate()
        }
    }

    @MainActor
    func testAllRelationshipJourneyBackgrounds() throws {
        for chapterNumber in 1...10 {
            let app = XCUIApplication()
            app.launchArguments = ["-UITest", "-UITestRelationshipChapter", "\(chapterNumber)"]
            app.launch()

            XCTAssertTrue(
                app.staticTexts["chapterJourneyTitle"].waitForExistence(timeout: 8),
                "Relationship chapter \(chapterNumber) should render its header"
            )
            let promptNodes = app.descendants(matching: .any).matching(identifier: "chapterPromptNode")
            XCTAssertEqual(promptNodes.count, 4)
            XCTAssertTrue(app.buttons["chapterJourneyBack"].exists)
            snap(app, name: String(format: "relationship-%02d", chapterNumber))
            app.terminate()
        }
    }

    @MainActor
    func testWalkthroughScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-linen-preview"]
        app.launch()

        sleep(3)
        dismissSystemDialogIfPresent()
        snap(app, name: "01-home")

        // Saved Stories tab
        let savedTab = app.buttons["Saved Stories"]
        if savedTab.waitForExistence(timeout: 5) {
            savedTab.tap()
            sleep(2)
            let createMemory = app.buttons["createNewMemoryButton"]
            XCTAssertTrue(createMemory.waitForExistence(timeout: 3))
            XCTAssertTrue(createMemory.isHittable)
            XCTAssertGreaterThanOrEqual(createMemory.frame.height, 44)
            snap(app, name: "02-saved-stories")
            app.buttons["Home"].tap()
            sleep(1)
        }

        // Storybook screen: scroll first so the card is clear of the floating tab bar.
        app.swipeUp()
        sleep(1)
        let yourBook = app.buttons["tutorialYourBook"]
        XCTAssertTrue(yourBook.waitForExistence(timeout: 5), "Your Book link should appear")
        yourBook.tap()
        sleep(3)
        snap(app, name: "03-storybook")

        let editCurrentPage = app.buttons["storybookEditCurrentPage"]
        if editCurrentPage.waitForExistence(timeout: 3) {
            editCurrentPage.tap()
            XCTAssertTrue(
                app.otherElements["freeformPageEditor"].waitForExistence(timeout: 8),
                "Editing the exterior cover should open the unified page editor"
            )
            XCTAssertTrue(app.buttons["Add Text"].isHittable)
            XCTAssertTrue(app.buttons["Add Photos"].isHittable)
            XCTAssertFalse(
                app.buttons["New Book"].isHittable,
                "Storybook controls must not remain interactive behind the page editor"
            )
            snap(app, name: "04-cover-editor-full-screen")
            app.buttons["Close page editor"].tap()
            XCTAssertTrue(editCurrentPage.waitForExistence(timeout: 5))
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).tap()
            XCTAssertTrue(app.otherElements["freeformPageEditor"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["Add Text"].isHittable)
            XCTAssertTrue(app.buttons["Add Photos"].isHittable)
            app.buttons["Close page editor"].tap()
        }

        // Generated-book actions added from TestFlight feedback.
        let newBook = app.buttons["New Book"]
        if newBook.waitForExistence(timeout: 3) {
            newBook.tap()
            XCTAssertTrue(
                app.staticTexts["Create a New Book?"].waitForExistence(timeout: 3),
                "New Book should explain that the current book remains in the Library"
            )
            snap(app, name: "04-new-book-confirmation")
            app.buttons["Cancel"].tap()
        }

        let order = app.buttons["Order"]
        if order.waitForExistence(timeout: 3) {
            order.tap()
            XCTAssertTrue(
                app.navigationBars["Order Print"].waitForExistence(timeout: 15),
                "Order Print should open from a generated book"
            )
            XCTAssertTrue(
                app.descendants(matching: .any).matching(identifier: "printUnavailableState").firstMatch.waitForExistence(timeout: 5),
                "A short book should show one focused print-availability state"
            )
            XCTAssertTrue(app.staticTexts["19 more pages needed to print"].exists)
            XCTAssertFalse(app.buttons["Print format"].exists)
            let returnToBook = app.buttons["returnToStorybookButton"]
            XCTAssertTrue(returnToBook.isHittable)
            snap(app, name: "05-order-print-availability")
            returnToBook.tap()
        }

        // Profile setup sheet (headshot prefill check)
        var create = app.buttons["Create My Storybook"]
        if !create.waitForExistence(timeout: 3) {
            create = app.staticTexts["Create My Storybook"]
        }
        if create.waitForExistence(timeout: 3) {
            create.tap()
            sleep(2)
            snap(app, name: "06-profile-setup")
            app.swipeDown(velocity: .fast)
            sleep(1)
        }

        // Storybook settings
        let settingsButton = app.buttons["storybookSettingsButton"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            sleep(3)
            snap(app, name: "07-settings")
        }
    }

    @MainActor
    func testMemoirPickerHeaderAndChapterCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-linen-preview", "-analytics-internal"]
        app.launch()

        sleep(3)
        dismissSystemDialogIfPresent()

        let continueMemories = app.buttons["tutorialContinueYourMemoir"]
        XCTAssertTrue(continueMemories.waitForExistence(timeout: 5))
        continueMemories.tap()
        selectDefaultMemoirIfNeeded(in: app)

        let title = app.staticTexts["memoirPickerTitle"]
        let change = app.buttons["memoirModeChangeButton"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(change.isHittable)
        XCTAssertEqual(title.frame.midY, change.frame.midY, accuracy: 8)

        change.tap()
        XCTAssertFalse(app.buttons["memoirModeOption_relationships"].exists)
        let lifeStoryRow = app.buttons["memoirModeOption_normal"]
        XCTAssertTrue(lifeStoryRow.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["memoirModeOption_parent"].exists)
        lifeStoryRow.tap()
        XCTAssertTrue(lifeStoryRow.waitForNonExistence(timeout: 2))

        let currentChapterCard = app.buttons["currentChapterCard"]
        XCTAssertTrue(currentChapterCard.isHittable)

        app.swipeUp()
        app.swipeUp()
        let firstTile = app.buttons["chapterTile1"]
        let secondTile = app.buttons["chapterTile2"]
        XCTAssertTrue(firstTile.waitForExistence(timeout: 5))
        XCTAssertTrue(secondTile.exists)
        XCTAssertGreaterThanOrEqual(firstTile.frame.height, 44)
        XCTAssertEqual(firstTile.frame.height, secondTile.frame.height, accuracy: 1)
    }

    @MainActor
    func testChapterRowsOpenFromTheirFullVisibleWidth() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-linen-preview", "-analytics-internal"]
        app.launch()

        let continueMemories = app.buttons["tutorialContinueYourMemoir"]
        XCTAssertTrue(continueMemories.waitForExistence(timeout: 10))
        continueMemories.tap()
        selectDefaultMemoirIfNeeded(in: app)

        let secondTile = app.buttons["chapterTile2"]
        for _ in 0..<4 where !secondTile.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(secondTile.waitForExistence(timeout: 5))
        XCTAssertTrue(secondTile.isHittable)

        secondTile.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.5)).tap()
        XCTAssertTrue(
            app.staticTexts["Chapter 2: Growing Up"].waitForExistence(timeout: 5),
            "The blank area inside a visible chapter row must open that chapter"
        )
    }

    @MainActor
    func testChapterJourneyScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-linen-preview"]
        app.launch()

        sleep(3)
        dismissSystemDialogIfPresent()

        let continueMemories = app.buttons["tutorialContinueYourMemoir"]
        XCTAssertTrue(continueMemories.waitForExistence(timeout: 5))
        continueMemories.tap()
        selectDefaultMemoirIfNeeded(in: app)

        let currentChapterCard = app.buttons["currentChapterCard"]
        XCTAssertTrue(currentChapterCard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["memoirPickerTitle"].exists)
        XCTAssertTrue(app.buttons["memoirModeChangeButton"].isHittable)
        currentChapterCard.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.25)).tap()

        XCTAssertTrue(
            app.staticTexts["Chapter 1: Beginnings"].waitForExistence(timeout: 5)
                && !app.staticTexts["Hold on to your story"].exists,
            "Chapter journey should open with its artwork and prompt trail"
        )
        XCTAssertTrue(app.buttons["chapterJourneyBack"].waitForExistence(timeout: 2))
        let back = app.buttons["chapterJourneyBack"]
        let title = app.staticTexts["chapterJourneyTitle"]
        let progress = app.staticTexts["chapterJourneyProgress"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(progress.exists)
        XCTAssertGreaterThanOrEqual(back.frame.midY, title.frame.minY)
        XCTAssertLessThanOrEqual(back.frame.midY, progress.frame.maxY)
        snap(app, name: "chapter-journey-responsive")
    }

    @MainActor
    func testRecordingWritingLayoutKeepsNavigationVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestNormalChapter", "1"]
        app.launch()

        let promptNode = app.descendants(matching: .any).matching(identifier: "chapterPromptNode").firstMatch
        XCTAssertTrue(promptNode.waitForExistence(timeout: 10))
        promptNode.tap()

        let editor = app.textViews["recordingTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let question = app.staticTexts["recordingQuestionText"]
        XCTAssertTrue(question.exists)
        let microphone = app.buttons["Tap to Record"]
        XCTAssertTrue(microphone.exists)
        XCTAssertEqual(question.frame.midX, app.frame.midX, accuracy: 2,
                       "The question's text block must center on the screen, not align to its card's leading edge")
        XCTAssertEqual(microphone.frame.midX, app.frame.midX, accuracy: 2)
        let save = app.buttons["Save Memory"]
        XCTAssertTrue(save.exists)
        XCTAssertEqual(save.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertLessThanOrEqual(save.frame.width, 712)
        XCTAssertTrue(app.staticTexts["Type your answer..."].exists)
        snap(app, name: "recording-centered-before-keyboard")
        editor.tap()
        editor.typeText("A short test memory")

        let backButton = app.buttons["recordingBackButton"]
        XCTAssertTrue(backButton.exists)
        snap(app, name: "recording-writing-keyboard-responsive")
        XCTAssertTrue(backButton.isHittable)
        XCTAssertGreaterThan(backButton.frame.minY, 40)
        XCTAssertLessThan(backButton.frame.minY, 120)
        XCTAssertFalse(app.staticTexts["Tap to Record"].exists)
    }

    @MainActor
    func testShortBookPrintAvailabilityScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-linen-preview", "-UITestSeedStorybook", "-UITestSeedPrintCart"]
        app.launch()

        sleep(3)
        dismissSystemDialogIfPresent()
        app.swipeUp()

        let yourBook = app.buttons["tutorialYourBook"]
        XCTAssertTrue(yourBook.waitForExistence(timeout: 5))
        yourBook.tap()

        let order = app.buttons["Order"]
        XCTAssertTrue(order.waitForExistence(timeout: 8))
        order.tap()

        XCTAssertTrue(app.navigationBars["Order Print"].waitForExistence(timeout: 10))
        let unavailableState = app.descendants(matching: .any)
            .matching(identifier: "printUnavailableState")
            .firstMatch
        XCTAssertTrue(unavailableState.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["19 more pages needed to print"].exists)
        XCTAssertFalse(app.buttons["Print format"].exists)

        let returnToBook = app.buttons["returnToStorybookButton"]
        XCTAssertTrue(returnToBook.isHittable)
        snap(app, name: "short-book-print-availability")
    }

    @MainActor
    func testInteriorPageEditorScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-linen-preview", "-UITestSeedStorybook"]
        app.launch()

        sleep(3)
        dismissSystemDialogIfPresent()
        app.swipeUp()

        let yourBook = app.buttons["tutorialYourBook"]
        XCTAssertTrue(yourBook.waitForExistence(timeout: 5))
        yourBook.tap()

        let nextPage = app.buttons["storybookNextPage"]
        XCTAssertTrue(nextPage.waitForExistence(timeout: 5))
        nextPage.tap()
        let edit = app.buttons["storybookEditCurrentPage"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))

        edit.tap()
        XCTAssertTrue(app.otherElements["freeformPageEditor"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Add Text"].isHittable)
        XCTAssertTrue(app.buttons["Add Photos"].isHittable)
        snap(app, name: "interior-title-page-editor-default-responsive")
        let originalTitle = try XCTUnwrap(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Text box, Memoir"))
                .allElementsBoundByIndex
                .first(where: { $0.isHittable }),
            "Opening-page copy must be a selectable text layer"
        )
        originalTitle.tap()
        let selectedText = app.textFields["Selected text"]
        XCTAssertTrue(selectedText.waitForExistence(timeout: 3))
        selectedText.tap()
        selectedText.typeText("Edited: ")
        let textSize = app.sliders["Text size"]
        XCTAssertTrue(textSize.isHittable)
        textSize.adjust(toNormalizedSliderPosition: 0.45)
        snap(app, name: "interior-title-page-editor-responsive")
        app.buttons["Save"].tap()

        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        let editedReaderTitle = app.staticTexts
            .matching(NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "Memoir",
                "Edited"
            ))
            .firstMatch
        XCTAssertTrue(editedReaderTitle.waitForExistence(timeout: 5))
        snap(app, name: "interior-title-page-reader-edited-responsive")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(app.otherElements["freeformPageEditor"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Add Text"].isHittable)
        XCTAssertTrue(app.buttons["Add Photos"].isHittable)
        app.buttons["Close page editor"].tap()

        XCTAssertTrue(nextPage.waitForExistence(timeout: 5))
        nextPage.tap()
        sleep(1)
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Blank book pages must remain editable")
        edit.tap()
        XCTAssertTrue(app.otherElements["freeformPageEditor"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Add Text"].isHittable)
        XCTAssertTrue(app.buttons["Add Photos"].isHittable)
        app.buttons["Close page editor"].tap()

        nextPage.tap()
        sleep(1)

        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        snap(app, name: "interior-page-reader-responsive")
        edit.tap()

        XCTAssertTrue(app.staticTexts["Edit page"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["pageEditorLaunchPlaceholder"].exists)
        XCTAssertTrue(app.buttons["Save"].isHittable)
        snap(app, name: "interior-page-editor-responsive")

        let close = app.buttons["Close page editor"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Opening page editor…"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).tap()
        XCTAssertTrue(app.staticTexts["Edit page"].waitForExistence(timeout: 5))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52)).tap()
        XCTAssertTrue(app.staticTexts["Drag to move · use corners to resize"].waitForExistence(timeout: 3))
        snap(app, name: "interior-page-editor-selection-responsive")

        close.tap()
        XCTAssertTrue(nextPage.waitForExistence(timeout: 5))
        nextPage.tap()
        sleep(1)
        snap(app, name: "interior-text-page-reader-responsive")
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit page"].waitForExistence(timeout: 5))
        snap(app, name: "interior-text-page-editor-responsive")
    }

    @MainActor
    func testClosingPageReaderAndEditorStayInSync() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-linen-preview", "-UITestSeedStorybook"]
        app.launch()

        sleep(3)
        dismissSystemDialogIfPresent()
        app.swipeUp()
        let yourBook = app.buttons["tutorialYourBook"]
        XCTAssertTrue(yourBook.waitForExistence(timeout: 5))
        yourBook.tap()

        let nextPage = app.buttons["storybookNextPage"]
        let closingHeading = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "Made with Memoir"))
            .firstMatch
        for _ in 0..<6 where !closingHeading.exists {
            XCTAssertTrue(nextPage.waitForExistence(timeout: 5))
            nextPage.tap()
            sleep(2)
        }

        let edit = app.buttons["storybookEditCurrentPage"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(closingHeading.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Download on the App Store"].exists)
        snap(app, name: "interior-closing-page-reader-responsive")

        edit.tap()
        XCTAssertTrue(app.otherElements["freeformPageEditor"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Add Text"].isHittable)
        XCTAssertTrue(app.buttons["Add Photos"].isHittable)
        XCTAssertTrue(app.staticTexts["Made with Memoir"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Download on the App Store"].exists)
        snap(app, name: "interior-closing-page-editor-responsive")

        let editableHeading = try XCTUnwrap(
            app.staticTexts
                .matching(NSPredicate(format: "label == %@", "Made with Memoir"))
                .allElementsBoundByIndex
                .first(where: { $0.isHittable }),
            "Closing-page heading must be a selectable text layer"
        )
        editableHeading.tap()
        let selectedText = app.textFields["Selected text"]
        XCTAssertTrue(selectedText.waitForExistence(timeout: 3))
        selectedText.tap()
        selectedText.typeText("Proudly ")
        app.buttons["Save"].tap()

        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Proudly Made with Memoir"].waitForExistence(timeout: 5))
        snap(app, name: "interior-closing-page-reader-edited-responsive")
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
    private func selectDefaultMemoirIfNeeded(in app: XCUIApplication) {
        let lifeStory = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "My Life Story")
        ).firstMatch
        if lifeStory.waitForExistence(timeout: 2) {
            lifeStory.tap()
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
