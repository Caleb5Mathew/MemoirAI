//
//  BatchTranscriptionManager.swift
//  MemoirAI
//
//  Created by user941803 on 7/4/25.
//


import Foundation
import CoreData
import Speech

/// Batch-processes speech transcription for every memory that still has audio but no text.
/// Publishes live progress so the UI can show a percentage/ProgressView.
final class BatchTranscriptionManager: ObservableObject {
    @Published var total: Int = 0
    @Published var processed: Int = 0
    @Published var isRunning: Bool = false

    /// IDs of memories currently being transcribed right now (by this manager or
    /// any of the recording surfaces that kick off a transcription directly).
    /// Views observe this to show "Transcribing…" instead of a generic
    /// "coming soon" placeholder.
    @Published private(set) var inFlightMemoryIDs: Set<UUID> = []

    static let shared = BatchTranscriptionManager()

    private let context: NSManagedObjectContext
    private init() {
        context = PersistenceController.shared.container.viewContext
    }

    /// True if at least one memory still needs transcription.
    var hasUntranscribed: Bool { untranscribedCount > 0 }
    var untranscribedCount: Int { fetchUntranscribed().count }

    /// Mark a memory as actively being transcribed right now. Safe to call from any thread.
    func markInFlight(_ id: UUID) {
        DispatchQueue.main.async { self.inFlightMemoryIDs.insert(id) }
    }

    /// Clear the in-flight marker for a memory (transcription finished, succeeded or failed). Safe to call from any thread.
    func markComplete(_ id: UUID) {
        DispatchQueue.main.async { self.inFlightMemoryIDs.remove(id) }
    }

    /// True if this memory currently has a transcription request in flight.
    func isInFlight(_ id: UUID) -> Bool { inFlightMemoryIDs.contains(id) }

    /// Start transcribing everything that still needs transcription.
    /// Runs serially; calls `completion` on the main queue when finished.
    func start(completion: (() -> Void)? = nil) {
        guard !isRunning else { return }
        guard let userID = MemoryUserScope.currentFirebaseUserId else {
            completion?()
            return
        }
        
        // Check speech recognition permission first
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            print("❌ Speech recognition not authorized")
            completion?()
            return
        }

        let todo = fetchUntranscribed()
        total = todo.count
        processed = 0
        guard total > 0 else {
            completion?()
            return
        }

        isRunning = true
        transcribe(list: todo, index: 0, userID: userID) {
            DispatchQueue.main.async {
                self.isRunning = false
                completion?()
                // Notify that transcription is completed
                NotificationCenter.default.post(name: .transcriptionCompleted, object: nil)
            }
        }
    }

    private func fetchUntranscribed() -> [MemoryEntry] {
        guard let userID = MemoryUserScope.currentFirebaseUserId else { return [] }
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "firebaseUserId == %@", userID),
            NSPredicate(format: "(audioFileURL != nil OR audioData != nil) AND (text == nil OR text == '')")
        ])
        // Newest first – shorter recordings usually come last
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]
        return ((try? context.fetch(request)) ?? []).filter { entry in
            URL(string: entry.audioFileURL ?? "")?.pathExtension.lowercased() != "m4a"
        }
    }

    private func transcribe(
        list: [MemoryEntry],
        index: Int,
        userID: String,
        completion: @escaping () -> Void
    ) {
        guard MemoryUserScope.currentFirebaseUserId == userID else {
            completion()
            return
        }
        if index >= list.count {
            completion()
            return
        }
        let memory = list[index]
        guard let url = memory.playbackURL else {
            // Skip if no playable URL
            DispatchQueue.main.async {
                self.processed += 1
            }
            transcribe(list: list, index: index + 1, userID: userID, completion: completion)
            return
        }

        if let entryID = memory.id {
            markInFlight(entryID)
        }

        SpeechTranscriber.shared.transcribe(url: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text):
                guard MemoryUserScope.currentFirebaseUserId == userID,
                      MemoryOwnershipPolicy.belongsToUser(
                        entryOwnerID: memory.firebaseUserId,
                        currentUserID: userID
                      ) else {
                    break
                }
                memory.text = text
                do {
                    try self.context.save()
                    NotificationCenter.default.post(name: .memorySaved, object: nil)
                    print("Enhanced transcription completed")
                } catch {
                    self.context.rollback()
                    print("❌ Could not save enhanced transcription: \(error.localizedDescription)")
                }
            case .failure(let error):
                // Leave memory.text untouched so `needsTranscription` still matches
                // this entry and a future batch run retries it.
                print("❌ Enhanced batch transcription error for memory \(memory.id?.uuidString.prefix(8) ?? "?")…:", error)
            }
            if let entryID = memory.id {
                self.markComplete(entryID)
            }
            DispatchQueue.main.async {
                self.processed += 1
            }
            self.transcribe(
                list: list,
                index: index + 1,
                userID: userID,
                completion: completion
            )
        }
    }
}

extension MemoryEntry {
    /// Returns true if this entry has audio but no text yet.
    var needsTranscription: Bool {
        hasAudio &&
        (text?.isEmpty ?? true) &&
        URL(string: audioFileURL ?? "")?.pathExtension.lowercased() != "m4a"
    }
}
