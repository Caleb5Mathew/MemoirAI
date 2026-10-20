import XCTest
@testable import MemoirAI

@MainActor
final class OnboardingMemoryPreflightTests: XCTestCase {
    private let profileID = UUID()

    private func key(story: String = "A complete childhood story", user: String = "owner") -> OnboardingMemoryPreflightKey {
        OnboardingMemoryPreflightKey(userID: user, profileID: profileID,
            name: "Alex", audience: .myself, storyteller: .subject, prompt: "Childhood?", story: story,
            rawTranscript: story, audioURL: nil, audioDigest: nil)
    }

    func testReusesIdenticalPreparation() async throws {
        let coordinator = OnboardingMemoryPreflight()
        let input = key()
        var calls = 0
        coordinator.start(key: input) { calls += 1; return "Complete transcript" }
        coordinator.start(key: input) { calls += 1; return "Wrong duplicate" }
        let first = try await coordinator.value(for: input)
        let second = try await coordinator.value(for: input)
        XCTAssertEqual(first, "Complete transcript")
        XCTAssertEqual(second, first)
        XCTAssertEqual(calls, 1)
    }

    func testChangedStoryAndAccountReplaceTask() async throws {
        let coordinator = OnboardingMemoryPreflight()
        let original = key()
        let changed = key(story: "Different complete story", user: "different-owner")
        coordinator.start(key: original) { "Old result" }
        coordinator.start(key: changed) { "New result" }
        do {
            _ = try await coordinator.value(for: original)
            XCTFail("A previous account's task must not be consumed")
        } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
        let result = try await coordinator.value(for: changed)
        XCTAssertEqual(result, "New result")
    }

    func testInvalidationRejectsLateResultEvenIfOperationIgnoresCancellation() async {
        let coordinator = OnboardingMemoryPreflight()
        let input = key()
        var continuation: CheckedContinuation<String, Never>?
        coordinator.start(key: input) {
            await withCheckedContinuation { continuation = $0 }
        }
        let waiter = Task { try await coordinator.value(for: input) }
        while continuation == nil { await Task.yield() }
        coordinator.invalidate()
        continuation?.resume(returning: "Stale result")
        do {
            _ = try await waiter.value
            XCTFail("Late completion must be rejected")
        } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testFailureCanBeRetried() async throws {
        let coordinator = OnboardingMemoryPreflight()
        let input = key()
        coordinator.start(key: input) { throw MemoryCreationError.cloudSyncFailed }
        do {
            _ = try await coordinator.value(for: input)
            XCTFail("Expected upload failure")
        } catch { XCTAssertNil(coordinator.key) }
        coordinator.start(key: input) { "Recovered full transcript" }
        let result = try await coordinator.value(for: input)
        XCTAssertEqual(result, "Recovered full transcript")
    }

    func testAudioDigestDetectsChangedBytesAtSameURL() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("original audio".utf8).write(to: url)
        let first = try OnboardingMemoryPreflightKey.digest(of: url)
        try Data("replacement audio".utf8).write(to: url)
        XCTAssertNotEqual(first, try OnboardingMemoryPreflightKey.digest(of: url))
    }
    func testDraftPreservesAudioDigestAcrossLaunches() throws {
        let draft = OnboardingDraft(session: OnboardingSession(), story: "A complete story",
            rawTranscript: nil, audioURL: nil, photoData: nil, audioDigest: "saved-digest")
        let decoded = try JSONDecoder().decode(OnboardingDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded.audioDigest, "saved-digest")
        let legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any]
        var legacy = try XCTUnwrap(legacyJSON)
        legacy.removeValue(forKey: "audioDigest")
        let legacyDraft = try JSONDecoder().decode(OnboardingDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(legacyDraft.audioDigest)
    }

}
