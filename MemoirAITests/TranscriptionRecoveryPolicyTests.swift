import Foundation
import Testing
import FirebaseFunctions
import FirebaseFirestore
@testable import MemoirAI

struct TranscriptionRecoveryPolicyTests {
    @Test func remoteOnlyM4APreservesCanonicalTextInsteadOfWritingEmptyLegacyText() {
        let isM4A = MemoryCloudAudioPolicy.isM4A(uploadURL: nil,
            existingAudioURL: "https://storage.example/o/users%2Fowner%2Faudio%2Fmemory.m4a?alt=media",
            remoteStoragePath: "users/owner/audio/memory.m4a")
        #expect(isM4A)
        #expect(MemoryTranscriptionSyncPolicy.mode(audioChanged: false, isM4A: isM4A,
            status: "completed", editedText: nil, text: "") == .preserveServer)
        #expect(MemoryCloudAudioPolicy.isM4A(uploadURL: nil,
            existingAudioURL: "https://example.com/audio.M4A?token=secret", remoteStoragePath: nil))
        #expect(!MemoryCloudAudioPolicy.isM4A(uploadURL: URL(fileURLWithPath: "/tmp/new.caf"),
            existingAudioURL: "https://example.com/old.m4a", remoteStoragePath: "old.m4a"))
        #expect(!MemoryCloudAudioPolicy.isM4A(uploadURL: nil, existingAudioURL: nil, remoteStoragePath: nil))
    }

    @Test func backendFailuresKeepTheirActualRecoveryReason() {
        let rows: [(FunctionsErrorCode, String, TranscriptionIssue)] = [
            (.unauthenticated, "Unauthenticated", .authentication),
            (.permissionDenied, "Denied", .permissionDenied),
            (.resourceExhausted, "Try again tomorrow", .dailyLimit),
            (.resourceExhausted, "Service busy", .rateLimited),
            (.deadlineExceeded, "Timed out", .timeout),
            (.unavailable, "Unavailable", .network),
            (.notFound, "Missing audio", .uploadNotReady),
            (.failedPrecondition, "Recording upload is not ready", .uploadNotReady),
            (.failedPrecondition, "This recording must be re-recorded", .rerecord),
            (.aborted, "Recording changed", .accountChanged),
            (.internal, "Provider failure", .unknown)
        ]
        for (code, message, expected) in rows {
            let error = NSError(domain: FunctionsErrorDomain, code: code.rawValue,
                userInfo: [NSLocalizedDescriptionKey: message])
            #expect(TranscriptionIssue.classify(error) == expected)
            #expect(!expected.message.isEmpty)
            #expect(!expected.analyticsReason.isEmpty)
        }
        #expect(TranscriptionIssue.classify(URLError(.notConnectedToInternet)) == .network)
        #expect(TranscriptionIssue.classify(URLError(.timedOut)) == .timeout)
        #expect(TranscriptionIssue.classify(URLError(.cancelled)) == .cancelled)
        #expect(TranscriptionIssue.classify(CancellationError()) == .cancelled)
        #expect(TranscriptionIssue.classify(CloudTranscriptionError.alreadyProcessing) == .processing)
        #expect(TranscriptionIssue.classify(CloudTranscriptionError.failure(.dailyLimit)) == .dailyLimit)
        #expect(TranscriptionIssue.classify(CloudTranscriptionError.accountChanged) == .accountChanged)
        #expect(TranscriptionIssue.classify(CloudTranscriptionError.memoryUnavailable) == .permissionDenied)
        #expect(TranscriptionIssue.classify(CloudTranscriptionError.notAuthenticated) == .authentication)
        #expect(TranscriptionIssue.classify(CloudTranscriptionError.invalidResponse) == .unknown)
    }

    @Test func staleProcessingCanBeRetriedInsteadOfShowingAnEndlessSpinner() {
        let now = Date(timeIntervalSince1970: 100_000)
        let recent = now.addingTimeInterval(-30)
        let stale = now.addingTimeInterval(-86400)
        #expect(TranscriptionPresentationPolicy.isActive(status: "processing", updatedAt: recent, now: now))
        #expect(!TranscriptionPresentationPolicy.isActive(status: "processing", updatedAt: stale, now: now))
        #expect(!TranscriptionPresentationPolicy.isActive(status: "processing", updatedAt: nil, now: now))
        #expect(!TranscriptionPresentationPolicy.isActive(status: "queued", updatedAt: recent, now: now))
        #expect(TranscriptionPresentationPolicy.isActive(status: "failed", updatedAt: stale, isInFlight: true, now: now))
        #expect(TranscriptionPresentationPolicy.canRetry(status: "processing", updatedAt: stale, audioURL: "file:///tmp/a.m4a", now: now))
        #expect(!TranscriptionPresentationPolicy.canRetry(status: "processing", updatedAt: recent, audioURL: "file:///tmp/a.m4a", now: now))
        #expect(TranscriptionPresentationPolicy.canRetry(status: "queued", updatedAt: stale, audioURL: "file:///tmp/a.m4a", now: now))
        #expect(!TranscriptionPresentationPolicy.canRetry(status: "queued", updatedAt: now, audioURL: "file:///tmp/a.m4a", now: now))
        #expect(!TranscriptionPresentationPolicy.canRetry(status: "completed", updatedAt: stale, audioURL: "file:///tmp/a.m4a", now: now))
        #expect(!TranscriptionPresentationPolicy.canRetry(status: "failed", updatedAt: stale, audioURL: "file:///tmp/a.caf", now: now))
        #expect(TranscriptionPresentationPolicy.canRetry(status: nil, updatedAt: nil, audioURL: "file:///tmp/a.m4a", now: now))
    }

    @Test func retryBackoffPersistsWithoutLeakingAcrossAccounts() throws {
        let suite = "TranscriptionRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let now = Date(timeIntervalSince1970: 86_400 + 3_600)
        TranscriptionFailureStore.record(.dailyLimit, memoryID: id, userID: "A", now: now, defaults: defaults)
        #expect(TranscriptionFailureStore.issue(memoryID: id, userID: "A", defaults: defaults) == .dailyLimit)
        #expect(TranscriptionFailureStore.issue(memoryID: id, userID: "B", defaults: defaults) == nil)
        #expect(!TranscriptionFailureStore.canAutomaticallyRetry(memoryID: id, userID: "A", now: now.addingTimeInterval(60), defaults: defaults))
        #expect(TranscriptionFailureStore.canAutomaticallyRetry(memoryID: id, userID: "A", now: Date(timeIntervalSince1970: 172_800), defaults: defaults))
        #expect(TranscriptionFailureStore.canAutomaticallyRetry(memoryID: id, userID: "B", now: now, defaults: defaults))
        TranscriptionFailureStore.record(.rateLimited, memoryID: id, userID: "A", now: now, defaults: defaults)
        #expect(!TranscriptionFailureStore.canAutomaticallyRetry(memoryID: id, userID: "A", now: now.addingTimeInterval(59), defaults: defaults))
        #expect(TranscriptionFailureStore.canAutomaticallyRetry(memoryID: id, userID: "A", now: now.addingTimeInterval(60), defaults: defaults))
        TranscriptionFailureStore.clear(memoryID: id, userID: "A", defaults: defaults)
        #expect(TranscriptionFailureStore.issue(memoryID: id, userID: "A", defaults: defaults) == nil)
        #expect(TranscriptionFailureStore.canAutomaticallyRetry(memoryID: id, userID: "A", now: now, defaults: defaults))
    }

    @Test func selectedProfileDoesNotInheritAnotherProfilesRows() {
        let selected = UUID(), other = UUID()
        #expect(MemoryLibraryScopePolicy.matches(entryProfileID: selected, entryUserID: "A", selectedProfileID: selected, currentUserID: "A"))
        #expect(!MemoryLibraryScopePolicy.matches(entryProfileID: other, entryUserID: "A", selectedProfileID: selected, currentUserID: "A"))
        #expect(!MemoryLibraryScopePolicy.matches(entryProfileID: selected, entryUserID: "B", selectedProfileID: selected, currentUserID: "A"))
        #expect(!MemoryLibraryScopePolicy.matches(entryProfileID: selected, entryUserID: nil, selectedProfileID: selected, currentUserID: nil))
    }

    @Test func profileRowsMergeLegacyFieldsDeduplicateAndPreserveMoreThan80Books() {
        let selected = UUID(), other = UUID()
        var rows: [(documentID: String, data: [String: Any])] = (0..<120).map {
            ("book-\($0)", ["profileId": selected.uuidString.lowercased(), "createdAt": Timestamp(seconds: Int64($0), nanoseconds: 0)])
        }
        rows.append(("legacy", ["profileID": selected.uuidString, "createdAt": Timestamp(seconds: 200, nanoseconds: 0)]))
        rows.append(rows[0])
        rows.append(("wrong", ["profileId": other.uuidString, "profileID": selected.uuidString]))
        let result = ProfileCloudRowsPolicy.normalizedRows(rows, profileID: selected)
        #expect(result.count == 121)
        #expect(result.first?.documentID == "legacy")
        #expect(result.last?.documentID == "book-0")
        #expect(result.allSatisfy { $0.data["profileId"] as? String == selected.uuidString })
        #expect(ProfileCloudRowsPolicy.profileID(in: ["profileID": selected.uuidString.lowercased()]) == selected.uuidString)
        #expect(ProfileCloudRowsPolicy.profileID(in: ["profileId": "invalid"]) == nil)
    }

    @Test func analyticsRetainsTypedFailureMetadataAndDropsRecordingContent() {
        for issue in TranscriptionIssue.allCases {
            let safe = AnalyticsPrivacyPolicy.sanitized(["failure_stage": "transcription", "failure_reason": issue.analyticsReason,
                "duration_ms": 15, "transcript": "private story", "error_description": "private content"])
            #expect(safe["failure_reason"] as? String == issue.analyticsReason)
            #expect(safe["failure_stage"] as? String == "transcription")
            #expect(safe["transcript"] == nil)
            #expect(safe["error_description"] == nil)
        }
        #expect(AnalyticsEventCategory.category(for: "Memory Transcription Failed") == "Memory creation")
    }
}
