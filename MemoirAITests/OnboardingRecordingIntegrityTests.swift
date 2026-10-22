import XCTest
import AVFoundation
@testable import MemoirAI

final class OnboardingRecordingIntegrityTests: XCTestCase {
    func testRawTranscriptPreservesFillersCorrectionsAndRepetition() {
        let raw = "Um, I was seven, no, eight. Hello hello, Dad said, like he always did."
        XCTAssertEqual(OnboardingMemoryValidation.normalizedTranscript(raw), raw)
    }

    @MainActor
    func testFinishingAnIdleRecorderDoesNotInventTranscriptOrAudio() async {
        let recorder = OnboardingRecorder()
        let result = await recorder.finish()
        XCTAssertEqual(result, "")
        XCTAssertNil(recorder.audioURL)
        XCTAssertFalse(recorder.isFinalizing)
        XCTAssertFalse(recorder.liveCaptionEnded)
        XCTAssertFalse(recorder.isRecording)
    }

    @MainActor
    func testDiscardClearsAnIdleRecorderSafely() {
        let recorder = OnboardingRecorder()
        recorder.discard()
        XCTAssertEqual(recorder.liveTranscript, "")
        XCTAssertEqual(recorder.elapsed, 0)
        XCTAssertNil(recorder.audioURL)
    }

    func testSaveFailuresHaveActionableMessages() {
        XCTAssertTrue(MemoryCreationError.cloudSyncFailed.localizedDescription.contains("saved on this device"))
        XCTAssertTrue(MemoryCreationError.changedStory.localizedDescription.contains("keep both versions"))
    }

    func testOnboardingReplayRequiresExactExplicitLaunchArgument() {
        XCTAssertFalse(OnboardingDebugConfiguration.replayRequested(arguments: []))
        XCTAssertFalse(OnboardingDebugConfiguration.replayRequested(arguments: ["-onboarding-replay-disabled"]))
        XCTAssertTrue(OnboardingDebugConfiguration.replayRequested(arguments: ["MemoirAI", "-onboarding-replay"]))
    }

    #if DEBUG && targetEnvironment(simulator)
    func testAudioFixtureRequiresExactExplicitLaunchArgument() {
        XCTAssertFalse(OnboardingDebugConfiguration.audioFixtureRequested(arguments: []))
        XCTAssertFalse(OnboardingDebugConfiguration.audioFixtureRequested(arguments: ["-onboarding-audio-fixture-disabled"]))
        XCTAssertTrue(OnboardingDebugConfiguration.audioFixtureRequested(arguments: ["MemoirAI", "-onboarding-audio-fixture"]))
    }

    func testAudioFixtureExportsPlayableM4A() async throws {
        let fixture = try await OnboardingDebugConfiguration.loadAudioFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        XCTAssertEqual(fixture.url.pathExtension, "m4a")
        let duration = try await AVURLAsset(url: fixture.url).load(.duration)
        XCTAssertGreaterThan(duration.seconds, 1)
        XCTAssertNotNil(OnboardingMemoryValidation.normalizedTranscript(fixture.draftTranscript))
    }
    #endif

}
