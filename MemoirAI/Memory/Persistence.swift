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
    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "MemoirDataModel")

        if inMemory {
            container.persistentStoreDescriptions.first!.url =
                URL(fileURLWithPath: "/dev/null")
        }

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        // Set the CloudKit container options
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.Buildr.MemoirAI")
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print("❌ Core Data store loading error: \(error)")
                print("❌ Error details: \(error.userInfo)")
                
                // Don't fatal error for CloudKit sync issues - let the app continue
                if error.domain == "NSCocoaErrorDomain" && error.code == 134060 {
                    print("⚠️ CloudKit sync error - app will continue with local data")
                } else {
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            } else {
                print("✅ Core Data store loaded successfully")
                print("✅ CloudKit container: \(storeDescription.cloudKitContainerOptions?.containerIdentifier ?? "None")")
            }
        })

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy =
            NSMergeByPropertyObjectTrumpMergePolicy
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
