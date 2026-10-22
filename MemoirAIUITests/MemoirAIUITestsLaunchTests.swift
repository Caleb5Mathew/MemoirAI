//
//  MemoirAIUITestsLaunchTests.swift
//  MemoirAIUITests
//
//  Created by user941803 on 4/6/25.
//

import XCTest

final class MemoirAIUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestResetMemoirMode", "-onboarding-replay"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["What are you hoping to make?"].waitForExistence(timeout: 15),
            "A production-style cold launch should route into onboarding"
        )
        let exploring = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "I’m just exploring")
        ).firstMatch
        XCTAssertTrue(exploring.waitForExistence(timeout: 5))
        XCTAssertTrue(exploring.isHittable, "Account preparation must not cover onboarding with an error alert")

        let accountPreparationWindow = expectation(description: "Account preparation remains healthy")
        accountPreparationWindow.isInverted = true
        wait(for: [accountPreparationWindow], timeout: 3)

        XCTAssertFalse(app.alerts["Memoir needs a moment"].exists)
        XCTAssertTrue(exploring.isHittable, "Account preparation must finish without covering onboarding")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
