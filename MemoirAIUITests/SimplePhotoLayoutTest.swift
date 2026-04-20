//
//  SimplePhotoLayoutTest.swift
//  MemoirAIUITests
//
//  Simple test to verify photo layout placeholder text change
//

import XCTest

final class SimplePhotoLayoutTest: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = true // Continue to gather more info
        app = XCUIApplication()
        app.launch()
    }
    
    @MainActor
    func testFindTestText() throws {
        // Wait for app to load
        sleep(4)
        
        // Take screenshot of current state
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Current_Screen_State"
        add(attachment)
        
        // Print all available static texts for debugging
        print("\n=== Available Static Texts ===")
        for text in app.staticTexts.allElementsBoundByIndex.prefix(20) {
            if text.exists {
                print("  - '\(text.label)'")
            }
        }
        
        print("\n=== Available Buttons ===")
        for button in app.buttons.allElementsBoundByIndex.prefix(20) {
            if button.exists {
                print("  - '\(button.label)'")
            }
        }
        
        // Try to find the test text anywhere on screen
        let testText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'TEST'")).firstMatch
        if testText.waitForExistence(timeout: 1) {
            let successScreenshot = app.screenshot()
            let successAttachment = XCTAttachment(screenshot: successScreenshot)
            successAttachment.name = "SUCCESS_Test_Text_Found"
            add(successAttachment)
            XCTAssertTrue(true, "✅ Found text containing 'TEST'!")
        } else {
            // Try to find "Tap to add photo" text
            let tapText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Tap to add photo'")).firstMatch
            if tapText.waitForExistence(timeout: 1) {
                let partialScreenshot = app.screenshot()
                let partialAttachment = XCTAttachment(screenshot: partialScreenshot)
                partialAttachment.name = "Found_Tap_To_Add_But_No_TEST"
                add(partialAttachment)
                XCTFail("⚠️ Found 'Tap to add photo' but NOT 'TEST: Tap to add photo' - change may not be visible")
            } else {
                XCTFail("❌ Could not find placeholder text. Need to navigate to photo layout view first.")
            }
        }
    }
}










