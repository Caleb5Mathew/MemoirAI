///
//  MemoryEntryViewModel.swift
//  MemoirAI
//
//  Created by user941803 on 4/6/25.
//

import Foundation
import CoreData

class MemoryEntryViewModel: ObservableObject {
    private let context = PersistenceController.shared.container.viewContext

    @Published var entries: [MemoryEntry] = []
    @Published var currentProfileID: UUID? // ✅ Keeps track of current profile

    // ✅ Call this when switching or using a profile
    func fetchEntries(for profileID: UUID) {
        currentProfileID = profileID

        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]
        request.predicate = NSPredicate(format: "profileID == %@", profileID as CVarArg)

        do {
            entries = try context.fetch(request)
        } catch {
            print("Error fetching entries: \(error)")
        }
    }

    // ✅ Pass profileID when adding an entry
    func addEntry(prompt: String, text: String?, audioURL: URL?, profileID: UUID) {
        let newEntry = MemoryEntry(context: context)
        newEntry.id = UUID()
        newEntry.prompt = prompt
        newEntry.text = text
        newEntry.audioFileURL = audioURL?.absoluteString
        newEntry.createdAt = Date()
        newEntry.profileID = profileID

        currentProfileID = profileID
        save()
    }

    func deleteEntry(_ entry: MemoryEntry) {
        context.delete(entry)
        save()
    }

    // ✅ Now calls fetchEntries with remembered profile
    private func save() {
        do {
            try context.save()
            if let profileID = currentProfileID {
                fetchEntries(for: profileID)
            }
        } catch {
            print("Error saving context: \(error)")
        }
    }
}
