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
        transcribe(list: todo, index: 0) {
            DispatchQueue.main.async {
                self.isRunning = false
                completion?()
                // Notify that transcription is completed
                NotificationCenter.default.post(name: .transcriptionCompleted, object: nil)
            }
        }
    }

    private func fetchUntranscribed() -> [MemoryEntry] {
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "(audioFileURL != nil OR audioData != nil) AND (text == nil OR text == '')")
        // Newest first – shorter recordings usually come last
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    private func transcribe(list: [MemoryEntry], index: Int, completion: @escaping () -> Void) {
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
            transcribe(list: list, index: index + 1, completion: completion)
            return
        }

        if let entryID = memory.id {
            markInFlight(entryID)
        }

        SpeechTranscriber.shared.transcribe(url: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text):
                memory.text = text
                try? self.context.save()
                // Notify interested views so they refresh.
                NotificationCenter.default.post(name: .memorySaved, object: nil)
                print("✅ Enhanced transcription completed for memory: \(text.prefix(50))...")
            case .failure(let error):
                // Leave memory.text untouched so `needsTranscription` still matches
                // this entry and a future batch run retries it.
                print("❌ Enhanced batch transcription error for memory \(memory.id?.uuidString ?? "?"):", error)
            }
            if let entryID = memory.id {
                self.markComplete(entryID)
            }
            DispatchQueue.main.async {
                self.processed += 1
            }
            self.transcribe(list: list, index: index + 1, completion: completion)
        }
    }
}

extension MemoryEntry {
    /// Returns true if this entry has audio but no text yet.
    var needsTranscription: Bool { hasAudio && (text?.isEmpty ?? true) }
} 
