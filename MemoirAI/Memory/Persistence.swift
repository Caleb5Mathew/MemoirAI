//
//  Persistence.swift
//  MemoirAI
//
//  Created by user941803 on 4/6/25.
//

import CoreData
import Foundation

struct PersistenceController {
    // MARK: - Single shared instance
    static let shared = PersistenceController()

    // MARK: - Preview instance (for SwiftUI previews)
    static var preview: PersistenceController = {
        let controller = PersistenceController()

        // Sample data for preview
        let ctx = controller.container.viewContext
        let sample = MemoryEntry(context: ctx)
        sample.id        = UUID()
        sample.prompt    = "Sample Prompt"
        sample.text      = "This is a sample memory."
        sample.createdAt = Date()

        do {
            try ctx.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }

        return controller
    }()

    // MARK: - Core-Data container
    let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "MemoirDataModel") // Matches .xcdatamodeld file
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data store failed to load: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
}

// MARK: - Convenience fetch helper (used by deep-link router)
extension PersistenceController {
    /// Fetch a single `MemoryEntry` whose `id` equals the supplied UUID.
    /// Returns `nil` if not found.
    func entry(id: UUID) -> MemoryEntry? {
        let ctx = container.viewContext
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate   = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit  = 1
        request.includesPendingChanges = true
        return (try? ctx.fetch(request))?.first
    }
}
