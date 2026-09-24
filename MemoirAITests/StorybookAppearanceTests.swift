import Testing
import UIKit
@testable import MemoirAI

@MainActor
struct StorybookAppearanceTests {
    @Test func bookRestorationWaitsUntilPresentationFinishes() {
        let controller = StorybookAppearanceController()
        var starts = 0
        controller.onFirstAppearance = { starts += 1 }

        controller.loadViewIfNeeded()
        controller.viewWillAppear(true)
        controller.viewIsAppearing(true)
        #expect(starts == 0)

        controller.viewDidAppear(true)
        #expect(starts == 1)
    }

    @Test func returningFromAnEditorDoesNotRestoreTheBookAgain() {
        let controller = StorybookAppearanceController()
        var starts = 0
        controller.onFirstAppearance = { starts += 1 }
        controller.viewDidAppear(true)
        controller.viewWillDisappear(true)
        controller.viewDidDisappear(true)
        controller.onFirstAppearance = { starts += 10 }
        controller.viewWillAppear(true)
        controller.viewDidAppear(true)

        #expect(starts == 1)
    }

    @Test func cancelledPresentationDoesNotStartRestoration() {
        let controller = StorybookAppearanceController()
        var started = false
        controller.onFirstAppearance = { started = true }
        controller.viewWillAppear(true)
        controller.viewWillDisappear(true)
        controller.viewDidDisappear(true)

        #expect(!started)
    }
}
