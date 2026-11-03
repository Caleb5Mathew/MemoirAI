import Foundation
import Testing
@testable import MemoirAI

@MainActor
struct PaywallPreparationTests {
    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        private var started = false
        private var startedWaiter: CheckedContinuation<Bool, Never>?
        private var startDeadline: Task<Void, Never>?
        func waitUntilStarted() async -> Bool {
            if started { return true }
            return await withCheckedContinuation { continuation in
                startedWaiter = continuation
                startDeadline = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                    catch { return }
                    startedWaiter?.resume(returning: false)
                    startedWaiter = nil
                }
            }
        }
        func wait() async {
            started = true
            startDeadline?.cancel()
            startedWaiter?.resume(returning: true)
            startedWaiter = nil
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }

    @Test func concurrentPreparationDoesNotStartAnotherOperation() async {
        let preparation = PaywallPreparation()
        let gate = Gate()
        var calls = 0
        var completions = 0
        let accepted = preparation.start(operation: { calls += 1; await gate.wait() }, completion: { _ in completions += 1 })
        #expect(accepted)
        let duplicate = preparation.start(operation: { calls += 1 }, completion: { _ in completions += 1 })
        #expect(!duplicate)
        let started = await gate.waitUntilStarted()
        #expect(started)
        #expect(calls == 1)
        preparation.cancel()
        gate.release()
        await Task.yield()
        #expect(completions == 1)
    }

    @Test func timeoutDoesNotWaitForUncooperativeSDKCallback() async {
        let preparation = PaywallPreparation()
        let gate = Gate()
        var calls = 0
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            preparation.start(timeoutNanoseconds: 1_000_000, operation: {
                await gate.wait()
            }, completion: { result in
                calls += 1
                continuation.resume(returning: result)
            })
        }
        guard case .failure(PaywallPreparationError.timeout) = result else {
            Issue.record("Expected bounded preparation timeout")
            gate.release()
            return
        }
        gate.release()
        await Task.yield()
        #expect(calls == 1)
    }

    @Test func latePreviousAttemptCannotFinishRetry() async {
        let preparation = PaywallPreparation()
        let first = Gate()
        let second = Gate()
        let firstReturned = Gate()
        var firstCompletions = 0
        var secondCompletions = 0
        preparation.start(operation: { await first.wait(); await firstReturned.wait() }, completion: { _ in firstCompletions += 1 })
        let firstStarted = await first.waitUntilStarted()
        #expect(firstStarted)
        preparation.cancel()
        let accepted = preparation.start(operation: { await second.wait() }, completion: { _ in secondCompletions += 1 })
        #expect(accepted)
        let secondStarted = await second.waitUntilStarted()
        #expect(secondStarted)
        first.release()
        let previousReturned = await firstReturned.waitUntilStarted()
        #expect(previousReturned)
        firstReturned.release()
        #expect(firstCompletions == 1)
        #expect(secondCompletions == 0)
        preparation.cancel()
        second.release()
        await Task.yield()
        #expect(secondCompletions == 1)
    }

    @Test func successfulPreparationReportsSuccessOnce() async {
        let preparation = PaywallPreparation()
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            preparation.start(operation: {}, completion: { continuation.resume(returning: $0) })
        }
        if case .failure = result { Issue.record("Expected successful preparation") }
        preparation.cancel()
    }

    @Test func providerFailureIsPreservedForStageClassification() async {
        let preparation = PaywallPreparation()
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            preparation.start(operation: {
                throw PaywallPreparationError.unavailable(stage: "offerings")
            }, completion: { continuation.resume(returning: $0) })
        }
        guard case .failure(PaywallPreparationError.unavailable(let stage)) = result else {
            Issue.record("Expected offerings failure")
            return
        }
        #expect(stage == "offerings")
    }

    @Test func preparationFailureClassificationNeverExposesProviderMessage() {
        #expect(RCSubscriptionManager.preparationFailureKind(URLError(.notConnectedToInternet)) == "network")
        #expect(RCSubscriptionManager.preparationFailureKind(NSError(domain: "RevenueCat.ErrorCode", code: 23)) == "configuration")
        #expect(RCSubscriptionManager.preparationFailureKind(NSError(domain: "private-provider", code: 123)) == "unknown")
    }
}
