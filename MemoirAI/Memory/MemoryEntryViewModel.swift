//
//  MemoryEntryViewModel.swift
//  MemoirAI
//
//  Created by user941803 on 4/6/25.
//
//



import Foundation
import CoreData

class MemoryEntryViewModel: ObservableObject {
    private let context = PersistenceController.shared.container.viewContext

    @Published var entries: [MemoryEntry] = []

    init() {
        fetchEntries()
    }

    func fetchEntries() {
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]

        do {
            entries = try context.fetch(request)
        } catch {
            print("Error fetching entries: \(error)")
        }
    }

    func addEntry(prompt: String, text: String?, audioURL: URL?) {
        let newEntry = MemoryEntry(context: context)
        newEntry.id = UUID()
        newEntry.prompt = prompt
        newEntry.text = text
        newEntry.audioFileURL = audioURL?.absoluteString
        newEntry.createdAt = Date()

        save()
    }

    func deleteEntry(_ entry: MemoryEntry) {
        context.delete(entry)
        save()
    }

    private func save() {
        do {
            try context.save()
            fetchEntries()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}
