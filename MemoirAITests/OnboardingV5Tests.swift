import XCTest
import AVFoundation
import UIKit
import FirebaseFunctions
@testable import MemoirAI

final class OnboardingV5Tests: XCTestCase {
    func testHTMLTypographyFacesExistOnDevice() {
        for name in ["IowanOldStyle-Roman", "AvenirNext-Regular", "AvenirNext-Medium", "AvenirNext-DemiBold", "AvenirNext-Bold"] {
            XCTAssertNotNil(UIFont(name: name, size: 16), "Missing HTML font face: \(name)")
        }
    }

    func testSessionStoreScopesStateByUser() {
        let suiteName = "OnboardingV5Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingSessionStore(defaults: defaults)
        var first = OnboardingSession()
        first.stage = 7
        first.audience = .myChildren
        first.narratorName = "Caleb"
        store.save(first, userID: "user-a")

        XCTAssertEqual(store.load(userID: "user-a"), first)
        XCTAssertEqual(store.load(userID: "user-b").stage, 0)
    }

    func testMemoryValidationRequiresAUsableStory() {
        XCTAssertNil(OnboardingMemoryValidation.normalizedTranscript("I remember it"))
        XCTAssertEqual(
            OnboardingMemoryValidation.normalizedTranscript("  We spent every summer afternoon beside the lake.  "),
            "We spent every summer afternoon beside the lake."
        )
    }

    func testPreviewStatusRejectsUnknownServerState() {
        XCTAssertEqual(OnboardingPreviewResponsePolicy.status(from: "imageReady"), .imageReady)
        XCTAssertNil(OnboardingPreviewResponsePolicy.status(from: "complete"))
        XCTAssertNil(OnboardingPreviewResponsePolicy.status(from: 1))
    }
    func testInternalPreviewFailureHasAReadableRecoveryMessage() {
        let error = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.internal.rawValue)
        let message = OnboardingPreviewErrorPolicy.message(for: error)
        XCTAssertFalse(message.contains("INTERNAL"))
        XCTAssertTrue(message.contains("memory is saved"))
        XCTAssertTrue(message.contains("Try again"))
    }

    func testPreviewQuotaUsedMessageIsSpecific() {
        let error = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.resourceExhausted.rawValue,
                            userInfo: [FunctionsErrorDetailsKey: ["reason": "preview-quota-used"]])
        XCTAssertTrue(OnboardingPreviewErrorPolicy.message(for: error).contains("free preview has already been used"))
    }

    func testPreviewAttemptsExhaustedDoesNotClaimPreviewWasUsed() {
        let error = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.resourceExhausted.rawValue,
                            userInfo: [FunctionsErrorDetailsKey: ["reason": "preview-attempts-exhausted"]])
        let message = OnboardingPreviewErrorPolicy.message(for: error)
        XCTAssertTrue(message.contains("after several attempts"))
        XCTAssertTrue(message.contains("saved memory"))
        XCTAssertFalse(message.contains("already been used"))
        XCTAssertFalse(message.contains("Try again"))
    }

    func testPreviewUnknownExhaustionDoesNotInventQuotaReason() {
        for details in [[:], ["reason": "unknown"]] {
            let error = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.resourceExhausted.rawValue,
                                userInfo: [FunctionsErrorDetailsKey: details])
            let message = OnboardingPreviewErrorPolicy.message(for: error)
            XCTAssertTrue(message.contains("saved memory"))
            XCTAssertFalse(message.contains("already been used"))
        }
    }

    func testBundledSampleNarrationDecodesCompletely() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "alex-sample", withExtension: "mp3"))
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertGreaterThan(player.duration, 15)
        XCTAssertLessThan(player.duration, 60)
        XCTAssertGreaterThan(player.numberOfChannels, 0)
        XCTAssertTrue(player.prepareToPlay())
    }

    func testSampleAudioProgressUsesActualElapsedTime() {
        let position = OnboardingAudioPosition(elapsed: 65.8, duration: 120)
        XCTAssertEqual(position.elapsedLabel, "1:05")
        XCTAssertEqual(position.durationLabel, "2:00")
        XCTAssertEqual(position.fraction, 65.8 / 120, accuracy: 0.0001)
        XCTAssertEqual(OnboardingAudioPosition(elapsed: 150, duration: 120).fraction, 1)
        XCTAssertEqual(OnboardingAudioPosition(elapsed: -5, duration: 120).fraction, 0)
    }

    func testSampleAudioProgressHandlesUnavailableMetadata() {
        let position = OnboardingAudioPosition(elapsed: .nan, duration: 0)
        XCTAssertEqual(position.fraction, 0)
        XCTAssertEqual(position.elapsedLabel, "0:00")
        XCTAssertEqual(position.durationLabel, "0:00")
    }

    @MainActor
    func testMissingSampleRecordingShowsErrorWithoutStartingPlayback() {
        let audio = OnboardingSampleAudioPlayer(recordingURL: nil)
        audio.toggle()
        XCTAssertFalse(audio.isPlaying)
        XCTAssertNotNil(audio.errorMessage)
        XCTAssertEqual(audio.position.fraction, 0)
        audio.stop()
        XCTAssertFalse(audio.isPlaying)
    }

    @MainActor
    func testInvalidSampleRecordingShowsRecoverableError() {
        let audio = OnboardingSampleAudioPlayer(recordingURL: URL(fileURLWithPath: "/missing-memoir-recording.mp3"))
        audio.toggle()
        XCTAssertFalse(audio.isPlaying)
        XCTAssertTrue(audio.errorMessage?.contains("try again") == true)
    }

}
