import Foundation
import Testing
@testable import MemoirAI

struct CloudTranscriptionTests {
    @Test func legacyProfileDecoding_defaultsGlossaryToEmpty() throws {
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id.uuidString,
            "name": "Rosalie"
        ])

        let profile = try JSONDecoder().decode(Profile.self, from: data)
        #expect(profile.id == id)
        #expect(profile.transcriptionGlossary.isEmpty)
    }

    @Test func glossary_trimsRemovesEmptyAndDeduplicatesIgnoringCase() {
        let profile = Profile(
            name: " Rosalie ",
            photoData: nil,
            childNames: ["Caleb", "rosalie"],
            transcriptionGlossary: [" St. Louis ", "", "caleb", "bad<term"]
        )

        #expect(CloudTranscriptionService.glossary(for: profile) == ["Rosalie", "Caleb", "St. Louis"])
    }

    @Test func glossary_enforcesServerLimits() {
        let profile = Profile(
            name: String(repeating: "x", count: 81),
            photoData: nil,
            transcriptionGlossary: (0..<45).map { "term-\($0)" }
        )

        let glossary = CloudTranscriptionService.glossary(for: profile)
        #expect(glossary.count == 40)
        #expect(glossary.allSatisfy { $0.count <= 80 })
    }

    @Test func retryPolicy_requestsQueuedAndFailedM4ARecordings() {
        #expect(TranscriptionRetryPolicy.shouldRequest(
            status: "queued",
            audioFileExtension: "m4a",
            updatedAt: nil
        ))
        #expect(TranscriptionRetryPolicy.shouldRequest(
            status: "failed",
            audioFileExtension: "M4A",
            updatedAt: Date()
        ))
    }

    @Test func retryPolicy_onlyRetriesStaleProcessingRequests() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(!TranscriptionRetryPolicy.shouldRequest(
            status: "processing",
            audioFileExtension: "m4a",
            updatedAt: now.addingTimeInterval(-60),
            now: now
        ))
        #expect(TranscriptionRetryPolicy.shouldRequest(
            status: "processing",
            audioFileExtension: "m4a",
            updatedAt: now.addingTimeInterval(-TranscriptionRetryPolicy.processingTimeout),
            now: now
        ))
    }

    @Test func retryPolicy_rejectsCompletedAndLegacyCAFRecordings() {
        #expect(!TranscriptionRetryPolicy.shouldRequest(
            status: "completed",
            audioFileExtension: "m4a",
            updatedAt: nil
        ))
        #expect(!TranscriptionRetryPolicy.shouldRequest(
            status: "failed",
            audioFileExtension: "caf",
            updatedAt: nil
        ))
    }

    @Test func syncPolicy_resetsOnlyWhenM4AAudioChanges() {
        #expect(MemoryTranscriptionSyncPolicy.mode(
            audioChanged: true,
            isM4A: true,
            status: "queued",
            editedText: "Old edit",
            text: "Old edit"
        ) == .resetForNewAudio)
    }

    @Test func syncPolicy_preservesServerFieldsForUneditedCloudTranscription() {
        #expect(MemoryTranscriptionSyncPolicy.mode(
            audioChanged: false,
            isM4A: true,
            status: "processing",
            editedText: nil,
            text: ""
        ) == .preserveServer)
    }

    @Test func syncPolicy_preservesIntentionalEmptyEdits() {
        #expect(MemoryTranscriptionSyncPolicy.mode(
            audioChanged: false,
            isM4A: true,
            status: "completed",
            editedText: "",
            text: ""
        ) == .writeEditedText(""))
    }

    @Test func failurePolicy_requiresRerecordingForPermanentAudioErrors() {
        #expect(TranscriptionFailurePolicy.status(
            for: "The recording could not be read. Please record it again."
        ) == "needsRerecording")
    }

    @Test func failurePolicy_keepsNetworkFailuresRetryable() {
        #expect(TranscriptionFailurePolicy.status(
            for: "The network connection was lost."
        ) == "failed")
    }
}
