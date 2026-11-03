import XCTest
import AVFoundation
import UIKit
import FirebaseFunctions
import FirebaseStorage
@testable import MemoirAI

final class OnboardingV5Tests: XCTestCase {
    func testPreviewNavigationRequiresImageAndSavedInputs() {
        XCTAssertFalse(OnboardingPreviewNavigationPolicy.canOpenPreview(hasImage: false, inputReady: false))
        XCTAssertFalse(OnboardingPreviewNavigationPolicy.canOpenPreview(hasImage: true, inputReady: false))
        XCTAssertFalse(OnboardingPreviewNavigationPolicy.canOpenPreview(hasImage: false, inputReady: true))
        XCTAssertTrue(OnboardingPreviewNavigationPolicy.canOpenPreview(hasImage: true, inputReady: true))
    }

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

    func testAudienceChoicesUseShortStandaloneLabels() {
        XCTAssertEqual(OnboardingAudience.myself.title, "My life story")
        XCTAssertEqual(OnboardingAudience.someoneElse.title, "Someone I care about")
        XCTAssertEqual(OnboardingAudience.myChildren.title, "Stories for my children")
        XCTAssertEqual(OnboardingAudience.parentOrGrandparent.title, "My parent or grandparent")
        XCTAssertEqual(OnboardingAudience.notSure.title, "I’m just exploring")
    }

    func testRecordingCopyKeepsStorytellerChoiceOffTheNameStepForPersonalMemoirs() {
        XCTAssertFalse(OnboardingRecordingCopy.needsStorytellerChoice(for: .myself))
        XCTAssertFalse(OnboardingRecordingCopy.needsStorytellerChoice(for: .myChildren))
        XCTAssertEqual(
            OnboardingRecordingCopy.prompt(for: .myself, name: "Caleb"),
            "What’s one of your favorite childhood memories?"
        )
    }

    func testRecordingCopyOffersEitherSpeakerForSomeoneElsesMemoir() {
        for audience in [OnboardingAudience.someoneElse, .parentOrGrandparent] {
            XCTAssertTrue(OnboardingRecordingCopy.needsStorytellerChoice(for: audience))
            XCTAssertEqual(
                OnboardingRecordingCopy.prompt(for: audience, name: "  Alex  "),
                "Share one of Alex’s favorite childhood memories."
            )
            XCTAssertEqual(
                OnboardingRecordingCopy.guidance(for: audience, name: "  Alex  "),
                "You can tell it for Alex, or have Alex tell it in their own words."
            )
            XCTAssertEqual(OnboardingRecordingCopy.subjectChoiceTitle(name: "  Alex  "), "Let Alex tell it")
        }
    }

    func testMemoryValidationRequiresAUsableStory() {
        XCTAssertNil(OnboardingMemoryValidation.normalizedTranscript("I remember it"))
        XCTAssertEqual(
            OnboardingMemoryValidation.normalizedTranscript("  We spent every summer afternoon beside the lake.  "),
            "We spent every summer afternoon beside the lake."
        )
    }

    func testOnboardingRecordingCountdownUsesSixtySecondLimit() {
        XCTAssertEqual(OnboardingRecordingCountdown.maximumDuration, 60)
        XCTAssertEqual(OnboardingRecordingCountdown(elapsed: 0).remainingLabel, "1:00")
        XCTAssertEqual(OnboardingRecordingCountdown(elapsed: 30).remainingLabel, "0:30")
        XCTAssertEqual(OnboardingRecordingCountdown(elapsed: 59.2).remainingLabel, "0:01")
        XCTAssertEqual(OnboardingRecordingCountdown(elapsed: 60).remainingLabel, "0:00")
    }

    func testOnboardingRecordingCountdownClampsProgressAndUrgency() {
        XCTAssertEqual(OnboardingRecordingCountdown(elapsed: -4).remainingFraction, 1)
        XCTAssertEqual(OnboardingRecordingCountdown(elapsed: 15).remainingFraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(OnboardingRecordingCountdown(elapsed: 90).remainingFraction, 0)
        XCTAssertEqual(OnboardingRecordingCountdown(elapsed: .nan).remainingFraction, 1)
        XCTAssertFalse(OnboardingRecordingCountdown(elapsed: 49).isUrgent)
        XCTAssertTrue(OnboardingRecordingCountdown(elapsed: 50).isUrgent)
    }

    func testMemoryValidationRejectsStoriesBeyondPreviewLimit() {
        let words = "one two three four five six "
        let accepted = words + String(
            repeating: "a",
            count: OnboardingMemoryValidation.maximumCharacterCount - words.utf16.count
        )
        let rejected = accepted + "x"

        XCTAssertNotNil(OnboardingMemoryValidation.normalizedTranscript(accepted))
        XCTAssertNil(OnboardingMemoryValidation.normalizedTranscript(rejected))
        XCTAssertFalse(OnboardingMemoryValidation.exceedsMaximumLength(accepted))
        XCTAssertTrue(OnboardingMemoryValidation.exceedsMaximumLength(rejected))
        XCTAssertEqual(OnboardingMemoryValidation.excessCharacterCount(rejected), 1)
        XCTAssertTrue(MemoryCreationError.storyTooLong.localizedDescription.contains("12,000"))
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

extension OnboardingV5Tests {
    func testPreviewRecoveryDistinguishesTerminalQuotaAndIdentityFailures() {
        for reason in ["preview-quota-used", "preview-attempts-exhausted"] {
            let error = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.resourceExhausted.rawValue,
                                userInfo: [FunctionsErrorDetailsKey: ["reason": reason]])
            XCTAssertEqual(OnboardingPreviewErrorPolicy.recovery(for: error), .continueWithoutPreview)
            XCTAssertFalse(OnboardingPreviewErrorPolicy.isTransient(error))
        }
        for code in [FunctionsErrorCode.alreadyExists, .permissionDenied, .failedPrecondition] {
            let error = NSError(domain: FunctionsErrorDomain, code: code.rawValue)
            XCTAssertEqual(OnboardingPreviewErrorPolicy.recovery(for: error), .continueWithoutPreview)
            XCTAssertFalse(OnboardingPreviewErrorPolicy.isTransient(error))
        }
        XCTAssertEqual(OnboardingPreviewErrorPolicy.recovery(for: NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.unauthenticated.rawValue)), .reconnect)
        XCTAssertEqual(OnboardingPreviewErrorPolicy.recovery(for: CancellationError()), .cancelled)
        XCTAssertEqual(OnboardingPreviewErrorPolicy.recovery(for: URLError(.cancelled)), .cancelled)
    }

    func testPreviewDiagnosticsUseOnlyFixedReasons() {
        XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: URLError(.timedOut)), "network")
        XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: CancellationError()), "cancelled")
        XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: OnboardingPreviewServiceError.invalidResponse), "preview_response")
        XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: MemoryCreationError.cloudSyncFailed), "memory_preparation")
        XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: NSError(domain: "private-message", code: 123)), "unknown")
        XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.alreadyExists.rawValue)), "request_conflict")
        let error = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.resourceExhausted.rawValue,
                            userInfo: [FunctionsErrorDetailsKey: ["reason": "unexpected private value"]])
        XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: error), "rate_limited")
    }

    func testPreviewTransientRetryRecoversWithoutChangingRequestAndSharesBudgetAcrossPolls() async throws {
        var budget = OnboardingPreviewRetryBudget()
        let requestID = UUID().uuidString
        var requests: [String] = []
        var delays: [Double] = []
        let value = try await budget.perform(sleep: { delays.append($0) }) {
            requests.append(requestID)
            if requests.count < 3 { throw URLError(.networkConnectionLost) }
            return "ready"
        }
        XCTAssertEqual(value, "ready")
        XCTAssertEqual(requests, [requestID, requestID, requestID])
        XCTAssertEqual(delays, [1, 2])
        XCTAssertEqual(budget.retriesUsed, 2)
        var laterCalls = 0
        do {
            _ = try await budget.perform(sleep: { _ in XCTFail("Budget must not reset on another poll") }) { () throws -> String in
                laterCalls += 1
                throw URLError(.timedOut)
            }
            XCTFail("Expected exhausted retry budget")
        } catch {
            XCTAssertEqual(laterCalls, 1)
        }
    }

    func testPreviewRetryDoesNotSpendAttemptsOnTerminalErrors() async {
        let errors: [Error] = [
            CancellationError(), URLError(.cancelled),
            NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.resourceExhausted.rawValue,
                    userInfo: [FunctionsErrorDetailsKey: ["reason": "preview-quota-used"]]),
            NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.alreadyExists.rawValue)
        ]
        for error in errors {
            var budget = OnboardingPreviewRetryBudget()
            var calls = 0
            do {
                _ = try await budget.perform(sleep: { _ in XCTFail("Terminal failures must not sleep or retry") }) { () throws -> String in
                    calls += 1
                    throw error
                }
                XCTFail("Expected failure")
            } catch {
                XCTAssertEqual(calls, 1)
                XCTAssertEqual(budget.retriesUsed, 0)
            }
        }
    }

    func testPreviewRetryPropagatesCancellationDuringBackoff() async {
        var budget = OnboardingPreviewRetryBudget()
        var calls = 0
        do {
            _ = try await budget.perform(sleep: { _ in throw CancellationError() }) { () throws -> String in
                calls += 1
                throw URLError(.timedOut)
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(calls, 1)
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}

extension OnboardingV5Tests {
    func testFailedOfferDoesNotCountAsSuccessfulOnboarding() {
        let outcome = OnboardingCompletionPolicy.outcome(previewReady: true, offerPresented: false, entitlementActive: false)
        XCTAssertEqual(outcome, "offer_unavailable")
        XCTAssertFalse(OnboardingCompletionPolicy.isSuccessful(outcome))
    }

    func testMissingPreviewDoesNotCountAsSuccessfulOnboardingEvenWithOffer() {
        let outcome = OnboardingCompletionPolicy.outcome(previewReady: false, offerPresented: true, entitlementActive: true)
        XCTAssertEqual(outcome, "preview_unavailable")
        XCTAssertFalse(OnboardingCompletionPolicy.isSuccessful(outcome))
    }

    func testActualOfferAndVerifiedEntitlementAreDistinctSuccessfulOutcomes() {
        let offer = OnboardingCompletionPolicy.outcome(previewReady: true, offerPresented: true, entitlementActive: false)
        let entitled = OnboardingCompletionPolicy.outcome(previewReady: true, offerPresented: false, entitlementActive: true)
        XCTAssertEqual(offer, "offer_presented")
        XCTAssertEqual(entitled, "entitled")
        XCTAssertTrue(OnboardingCompletionPolicy.isSuccessful(offer))
        XCTAssertTrue(OnboardingCompletionPolicy.isSuccessful(entitled))
        XCTAssertTrue(OnboardingCompletionPolicy.shouldComplete(after: .paywallDismissed))
        XCTAssertFalse(OnboardingCompletionPolicy.shouldComplete(after: .finalContinueTapped))
    }

    func testPreviewRetryReplaysExactSubmittedTextForSameRequest() {
        XCTAssertEqual(OnboardingCompletionPolicy.replayStory(savedRequestID: "request-a", requestID: "request-a", savedStory: "Original canonical transcript", preparedStory: "New canonical transcript"), "Original canonical transcript")
        XCTAssertEqual(OnboardingCompletionPolicy.replayStory(savedRequestID: "request-a", requestID: "request-b", savedStory: "Original canonical transcript", preparedStory: "Edited story"), "Edited story")
        XCTAssertEqual(OnboardingCompletionPolicy.replayStory(savedRequestID: "request-a", requestID: "request-a", savedStory: nil, preparedStory: "First submission"), "First submission")
    }
}

extension OnboardingV5Tests {
    func testPreviewDeadlinePreventsAnotherRequestAfterSlowFailure() async {
        var clock: TimeInterval = 100
        var budget = OnboardingPreviewRetryBudget(deadline: 250, now: { clock })
        var calls = 0
        do {
            _ = try await budget.perform(sleep: { delay in clock += delay }) { () throws -> String in
                calls += 1
                clock = 250
                throw URLError(.timedOut)
            }
            XCTFail("Expected total deadline")
        } catch OnboardingPreviewServiceError.stillProcessing {
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(budget.retriesUsed, 0)
            XCTAssertEqual(budget.remainingTime, 0)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testPreviewDeadlineRejectsLateSuccess() async {
        var clock: TimeInterval = 100
        var budget = OnboardingPreviewRetryBudget(deadline: 101, now: { clock })
        do {
            _ = try await budget.perform {
                clock = 102
                return "late"
            }
            XCTFail("Expected total deadline")
        } catch OnboardingPreviewServiceError.stillProcessing {} catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreviewDoesNotReplayPreviousAccountPayloadAfterBackoff() async {
        var currentUser = "account-a"
        var budget = OnboardingPreviewRetryBudget()
        var requests = 0
        do {
            _ = try await budget.perform(validateOwnership: {
                guard currentUser == "account-a" else { throw OnboardingPreviewServiceError.accountChanged }
            }, sleep: { _ in currentUser = "account-b" }) { () throws -> String in
                requests += 1
                throw URLError(.networkConnectionLost)
            }
            XCTFail("Expected account change")
        } catch OnboardingPreviewServiceError.accountChanged {
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(OnboardingPreviewErrorPolicy.recovery(for: OnboardingPreviewServiceError.accountChanged), .reconnect)
            XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: OnboardingPreviewServiceError.accountChanged), "account_changed")
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testPreviewRejectsOldAccountResponseAfterAwait() async {
        var currentUser = "account-a"
        var budget = OnboardingPreviewRetryBudget()
        do {
            _ = try await budget.perform(validateOwnership: {
                guard currentUser == "account-a" else { throw OnboardingPreviewServiceError.accountChanged }
            }) {
                currentUser = "account-b"
                return "old account preview"
            }
            XCTFail("Expected account change")
        } catch OnboardingPreviewServiceError.accountChanged {} catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreviewDownloadSynchronousCompletionAndLateCallbackResolveOnce() async throws {
        var cancellations = 0
        let data = try await OnboardingPreviewDownload.run(timeout: 1) { completion in
            completion(.success(Data([1, 2, 3])))
            completion(.failure(URLError(.cancelled)))
            return { cancellations += 1 }
        }
        XCTAssertEqual(data, Data([1, 2, 3]))
        XCTAssertEqual(cancellations, 1)
    }

    func testPreviewDownloadDeadlineCancelsSDKAndIgnoresCancellationCallback() async {
        let cancelled = expectation(description: "Underlying download cancelled")
        do {
            _ = try await OnboardingPreviewDownload.run(timeout: 0.01) { completion in
                return {
                    cancelled.fulfill()
                    completion(.failure(URLError(.cancelled)))
                }
            }
            XCTFail("Expected timeout")
        } catch OnboardingPreviewServiceError.stillProcessing {} catch {
            XCTFail("Unexpected error: \(error)")
        }
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testPreviewDownloadTaskCancellationStopsUnderlyingDownload() async {
        let started = expectation(description: "Download started")
        let cancelled = expectation(description: "Underlying download cancelled")
        let task = Task {
            try await OnboardingPreviewDownload.run(timeout: 30) { completion in
                started.fulfill()
                return {
                    cancelled.fulfill()
                    completion(.success(Data([9])))
                }
            }
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        await fulfillment(of: [cancelled], timeout: 1)
    }
}

extension OnboardingV5Tests {
    func testPreviewCallableDeadlineReturnsBeforeUncooperativeLateCallback() async {
        let lateCallback = expectation(description: "Late callable result ignored")
        do {
            _ = try await OnboardingPreviewCallbackDeadline<String>.run(timeout: 0.01) { completion in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    completion(.success("server eventually completed"))
                    lateCallback.fulfill()
                }
                return {}
            }
            XCTFail("Expected independent callable deadline")
        } catch OnboardingPreviewServiceError.stillProcessing {} catch {
            XCTFail("Unexpected error: \(error)")
        }
        await fulfillment(of: [lateCallback], timeout: 1)
    }
}

extension OnboardingV5Tests {
    func testPreviewStorageFailuresUseSafeRecoveryAndDiagnostics() {
        let cases: [(StorageErrorCode, OnboardingPreviewRecovery, String)] = [
            (.objectNotFound, .continueWithoutPreview, "image_missing"),
            (.unauthenticated, .reconnect, "authentication"),
            (.unauthorized, .continueWithoutPreview, "permission_denied"),
            (.cancelled, .cancelled, "cancelled"),
            (.retryLimitExceeded, .retry, "network"),
            (.unknown, .retry, "image_download")
        ]
        for (code, recovery, reason) in cases {
            let error = NSError(domain: StorageErrorDomain, code: code.rawValue,
                                userInfo: [NSLocalizedDescriptionKey: "private storage object path"])
            XCTAssertEqual(OnboardingPreviewErrorPolicy.recovery(for: error), recovery)
            XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: error), reason)
            XCTAssertEqual(OnboardingPreviewErrorPolicy.stage(for: error), "image_download")
            XCTAssertFalse(OnboardingPreviewErrorPolicy.message(for: error).contains("private storage object path"))
            XCTAssertFalse(OnboardingPreviewErrorPolicy.isTransient(error))
        }
    }

    func testPreviewStageDistinguishesPreflightFromGeneration() {
        XCTAssertEqual(OnboardingPreviewErrorPolicy.recovery(for: CloudTranscriptionError.notAuthenticated), .reconnect)
        XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: CloudTranscriptionError.notAuthenticated), "authentication")
        XCTAssertEqual(OnboardingPreviewErrorPolicy.stage(for: CloudTranscriptionError.invalidResponse), "preflight")
        XCTAssertEqual(OnboardingPreviewErrorPolicy.reason(for: CloudTranscriptionError.invalidResponse), "memory_preparation")
        XCTAssertEqual(OnboardingPreviewErrorPolicy.stage(for: NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.unavailable.rawValue)), "generation")
        XCTAssertNil(OnboardingPreviewErrorPolicy.stage(for: URLError(.timedOut)))
    }
}
