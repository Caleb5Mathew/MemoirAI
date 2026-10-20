import CoreData
import Foundation
import FirebaseAuth

enum OnboardingMemoryValidation {
    static func normalizedTranscript(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.split(whereSeparator: \.isWhitespace).count >= 6 else { return nil }
        return text
    }
}

@MainActor
struct MemoryCreationService {
    @discardableResult
    func saveOnboardingMemory(
        id: UUID,
        prompt: String,
        transcript: String,
        rawTranscript: String? = nil,
        audioURL: URL?,
        profile: Profile,
        firebaseUserID: String,
        queueCloudSync: Bool = true
    ) throws -> UUID {
        guard let normalized = OnboardingMemoryValidation.normalizedTranscript(transcript) else {
            throw MemoryCreationError.storyTooShort
        }
        let original = rawTranscript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = original?.isEmpty == false ? original : normalized
        let narratorEdit = raw == normalized ? nil : normalized
        if let audioURL {
            let size = (try FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else { throw MemoryCreationError.emptyAudio }
        }

        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            guard existing.firebaseUserId == firebaseUserID, existing.profileID == profile.id,
                  existing.prompt == prompt, existing.audioFileURL == audioURL?.absoluteString,
                  existing.transcriptionEditedText == normalized || existing.transcriptionRawText == normalized || existing.text == normalized else {
                throw MemoryCreationError.changedStory
            }
            return id
        }

        let entry = MemoryEntry(context: context)
        entry.id = id
        entry.prompt = prompt
        entry.text = normalized
        entry.transcriptionRawText = raw
        entry.audioFileURL = audioURL?.absoluteString
        entry.transcriptionEditedText = narratorEdit
        entry.transcriptionStatus = audioURL == nil ? nil : "queued"
        entry.transcriptionLanguage = "en"
        entry.createdAt = Date()
        entry.chapter = "Earliest Memories"
        entry.memoirModeRaw = MemoirMode.normal.rawValue
        entry.profileID = profile.id
        entry.firebaseUserId = firebaseUserID
        do {
            try context.save()
        } catch {
            context.delete(entry)
            throw error
        }
        if queueCloudSync { FirestoreSyncService.shared.queueMemorySyncWithProfile(entry, profile: profile) }
        return id
    }

    func prepareOnboardingMemory(id: UUID, profile: Profile, firebaseUserID: String, story: String, hasAudio: Bool) async throws -> String {
        let started = Date()
        guard Auth.auth().currentUser?.uid == firebaseUserID,
              let entry = PersistenceController.shared.entry(id: id),
              entry.firebaseUserId == firebaseUserID, entry.profileID == profile.id else {
            throw MemoryCreationError.cloudSyncFailed
        }
        guard await FirestoreSyncService.shared.syncMemory(entry, profileName: profile.name) else {
            throw MemoryCreationError.cloudSyncFailed
        }
        try Task.checkCancellation()
        #if DEBUG
        print("Onboarding preflight sync_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
        #endif
        guard hasAudio else { return story }
        async let playback = FirestoreSyncService.shared.freshAudioPlaybackURL(memoryID: id, expectedUserID: firebaseUserID)
        async let reading = completedReadingCopy(id: id, profile: profile, firebaseUserID: firebaseUserID)
        let text = try await reading
        guard await playback != nil, Auth.auth().currentUser?.uid == firebaseUserID else {
            throw MemoryCreationError.cloudSyncFailed
        }
        try Task.checkCancellation()
        #if DEBUG
        print("Onboarding preflight total_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
        #endif
        return text
    }

    /// Live captions may stop before a long recording does. Use the full audio.
    func completedReadingCopy(id: UUID, profile: Profile, firebaseUserID: String) async throws -> String {
        for _ in 0..<150 {
            try Task.checkCancellation()
            guard Auth.auth().currentUser?.uid == firebaseUserID,
                  let entry = PersistenceController.shared.entry(id: id),
                  entry.firebaseUserId == firebaseUserID else { throw MemoryCreationError.cloudSyncFailed }
            if entry.transcriptionStatus == "completed" {
                return MemoryTranscriptionTextPolicy.displayText(
                    edited: entry.transcriptionEditedText, canonical: entry.text, raw: entry.transcriptionRawText
                )
            }
            do {
                let canonical = try await CloudTranscriptionService.shared.transcribe(memoryID: id, profile: profile)
                return MemoryTranscriptionTextPolicy.validUserEdit(entry.transcriptionEditedText) ?? canonical
            } catch CloudTranscriptionError.alreadyProcessing {
                try await Task.sleep(for: .seconds(2))
            }
        }
        throw CloudTranscriptionError.alreadyProcessing
    }

    /// Returns only after the original audio has a usable remote playback URL.
    func syncOnboardingMemory(id: UUID, profile: Profile, firebaseUserID: String) async throws -> URL? {
        guard Auth.auth().currentUser?.uid == firebaseUserID else { throw MemoryCreationError.cloudSyncFailed }
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let entry = try context.fetch(request).first,
              entry.firebaseUserId == firebaseUserID, entry.profileID == profile.id else {
            throw MemoryCreationError.cloudSyncFailed
        }
        let hasAudio = entry.audioFileURL != nil
        guard await FirestoreSyncService.shared.syncMemory(entry, profileName: profile.name),
              Auth.auth().currentUser?.uid == firebaseUserID else {
            throw MemoryCreationError.cloudSyncFailed
        }
        guard hasAudio else { return nil }
        guard let url = await FirestoreSyncService.shared.freshAudioPlaybackURL(memoryID: id, expectedUserID: firebaseUserID) else {
            throw MemoryCreationError.cloudSyncFailed
        }
        return url
    }
}

enum MemoryCreationError: LocalizedError {
    case storyTooShort
    case emptyAudio
    case changedStory
    case cloudSyncFailed

    var errorDescription: String? {
        switch self {
        case .storyTooShort: return "Tell us a little more so the page has a story to hold onto."
        case .changedStory: return "This saved memory differs from your current story. Start a new page to keep both versions."
        case .cloudSyncFailed: return "Your memory is saved on this device. Reconnect and retry so its recording can be heard from the book."
        case .emptyAudio: return "The recording was empty. Please record it again."
        }
    }
}
