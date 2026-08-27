import Foundation
import FirebaseAuth
import FirebaseFunctions

enum CloudTranscriptionError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case alreadyProcessing

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to transcribe a recording."
        case .invalidResponse: return "The transcription service returned an invalid response."
        case .alreadyProcessing: return "This recording is already being transcribed."
        }
    }
}

enum MemoryTranscriptionSyncMode: Equatable {
    case resetForNewAudio
    case writeEditedText(String)
    case writeLegacyText(String)
    case preserveServer
}

enum MemoryTranscriptionSyncPolicy {
    static func mode(
        audioChanged: Bool,
        isM4A: Bool,
        status: String?,
        editedText: String?,
        text: String
    ) -> MemoryTranscriptionSyncMode {
        if audioChanged && isM4A && status?.lowercased() == "queued" { return .resetForNewAudio }
        if let editedText { return .writeEditedText(editedText) }
        if !isM4A || status == nil { return .writeLegacyText(text) }
        return .preserveServer
    }
}

enum TranscriptionRetryPolicy {
    static let processingTimeout: TimeInterval = 5 * 60

    static func shouldRequest(
        status: String?,
        audioFileExtension: String?,
        updatedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard audioFileExtension?.lowercased() == "m4a" else { return false }
        switch status?.lowercased() {
        case "queued", "failed":
            return true
        case "processing":
            guard let updatedAt else { return true }
            return now.timeIntervalSince(updatedAt) >= processingTimeout
        default:
            return false
        }
    }
}

enum TranscriptionFailurePolicy {
    static func status(for errorDescription: String) -> String {
        let message = errorDescription.lowercased()
        let permanentPhrases = [
            "too large",
            "could not be read",
            "no speech was detected",
            "format is unsupported",
            "record it again",
            "re-recorded"
        ]
        return permanentPhrases.contains(where: message.contains) ? "needsRerecording" : "failed"
    }
}

actor CloudTranscriptionService {
    static let shared = CloudTranscriptionService()
    private var activeMemoryIDs = Set<UUID>()

    private init() {}

    func transcribe(memoryID: UUID, profile: Profile, language: String = "en") async throws -> String {
        try await transcribe(
            memoryID: memoryID,
            glossary: Self.glossary(for: profile),
            language: language
        )
    }

    func transcribe(memoryID: UUID, glossary: [String], language: String = "en") async throws -> String {
        guard Auth.auth().currentUser != nil else { throw CloudTranscriptionError.notAuthenticated }
        guard activeMemoryIDs.insert(memoryID).inserted else {
            throw CloudTranscriptionError.alreadyProcessing
        }
        defer { activeMemoryIDs.remove(memoryID) }
        let expectedAudioFileURL = await MainActor.run {
            PersistenceController.shared.entry(id: memoryID)?.audioFileURL
        }
        await updateLocalState(memoryID: memoryID, status: "processing")
        let callable = Functions.functions().httpsCallable("transcribeMemoryAudio")
        callable.timeoutInterval = 310
        do {
            let result = try await callable.call([
                "memoryId": memoryID.uuidString,
                "language": language,
                "glossary": glossary
            ])
            guard let payload = result.data as? [String: Any] else {
                throw CloudTranscriptionError.invalidResponse
            }
            if payload["status"] as? String == "processing" {
                throw CloudTranscriptionError.alreadyProcessing
            }
            guard
                  let text = payload["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudTranscriptionError.invalidResponse
            }
            try await saveCompletedTranscription(
                text,
                memoryID: memoryID,
                language: language,
                expectedAudioFileURL: expectedAudioFileURL
            )
            return text
        } catch {
            if case CloudTranscriptionError.alreadyProcessing = error {
                throw error
            }
            await updateLocalState(
                memoryID: memoryID,
                status: TranscriptionFailurePolicy.status(for: error.localizedDescription),
                expectedAudioFileURL: expectedAudioFileURL
            )
            throw error
        }
    }

    static func glossary(for profile: Profile) -> [String] {
        var seen = Set<String>()
        let unsupportedCharacters = CharacterSet(charactersIn: "<>\r\n")
        let terms = ([profile.name] + profile.childNames + profile.transcriptionGlossary)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty &&
                $0.count <= 80 &&
                $0.rangeOfCharacter(from: unsupportedCharacters) == nil &&
                seen.insert($0.lowercased()).inserted
            }
        return Array(terms.prefix(40))
    }

    private func saveCompletedTranscription(
        _ text: String,
        memoryID: UUID,
        language: String,
        expectedAudioFileURL: String?
    ) async throws {
        try await MainActor.run {
            guard let entry = PersistenceController.shared.entry(id: memoryID) else { return }
            guard entry.audioFileURL == expectedAudioFileURL else { return }
            entry.transcriptionRawText = text
            entry.transcriptionStatus = "completed"
            entry.transcriptionLanguage = language
            entry.transcriptionModel = "gpt-transcribe"
            entry.transcriptionVersion += 1
            entry.transcriptionUpdatedAt = Date()
            if entry.transcriptionEditedText == nil {
                entry.text = text
            }
            try entry.managedObjectContext?.save()
            NotificationCenter.default.post(name: .memorySaved, object: nil)
        }
    }

    private func updateLocalState(
        memoryID: UUID,
        status: String,
        expectedAudioFileURL: String? = nil
    ) async {
        await MainActor.run {
            guard let entry = PersistenceController.shared.entry(id: memoryID) else { return }
            if let expectedAudioFileURL, entry.audioFileURL != expectedAudioFileURL { return }
            entry.transcriptionStatus = status
            entry.transcriptionUpdatedAt = Date()
            do {
                try entry.managedObjectContext?.save()
                NotificationCenter.default.post(name: .memorySaved, object: nil)
            } catch {
                print("⚠️ Could not save transcription status: \(error.localizedDescription)")
            }
        }
    }
}
