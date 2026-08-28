//
//  Persistence.swift
//  MemoirAI
//
//  Created by user941803 on 4/6/25.
//

import CoreData

struct AccountLocalCleanupManifest {
    var localFileURLs: [URL]
    var memoryIDs: Set<UUID>
    var profileIDs: Set<UUID>

    static let empty = AccountLocalCleanupManifest(
        localFileURLs: [],
        memoryIDs: [],
        profileIDs: []
    )
}
import Foundation

enum PersistenceConfigurationPolicy {
    static func usesCloudKit(inMemory: Bool, isRunningTests: Bool) -> Bool {
        !inMemory && !isRunningTests
    }

    static func shouldRetryLocalOnly(error: NSError, attemptedCloudKit: Bool) -> Bool {
        attemptedCloudKit
            && error.domain == NSCocoaErrorDomain
            && [134060, 134400].contains(error.code)
    }
}

struct PersistenceController {
    // MARK: - Single shared instance
    static let shared = PersistenceController()

    // MARK: - Preview instance (for SwiftUI previews)
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)

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
        let persistentContainer = NSPersistentCloudKitContainer(name: "MemoirDataModel")
        container = persistentContainer

        if inMemory {
            persistentContainer.persistentStoreDescriptions.first!.url =
                URL(fileURLWithPath: "/dev/null")
        }

        guard let description = persistentContainer.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }

        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if PersistenceConfigurationPolicy.usesCloudKit(
            inMemory: inMemory,
            isRunningTests: isRunningTests
        ) {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.Buildr.MemoirAI"
            )
        }
        
        let attemptedCloudKit = description.cloudKitContainerOptions != nil
        persistentContainer.loadPersistentStores(completionHandler: { storeDescription, error in
            if let error = error as NSError? {
                print("❌ Core Data store loading error: \(error)")
                print("❌ Error details: \(error.userInfo)")
                guard PersistenceConfigurationPolicy.shouldRetryLocalOnly(
                    error: error,
                    attemptedCloudKit: attemptedCloudKit
                ) else {
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
                description.cloudKitContainerOptions = nil
                persistentContainer.loadPersistentStores { localDescription, localError in
                    if let localError = localError as NSError? {
                        fatalError("Local Core Data fallback failed \(localError), \(localError.userInfo)")
                    }
                    print("⚠️ CloudKit unavailable (\(error.code)); local Core Data fallback loaded")
                    print("✅ CloudKit container: \(localDescription.cloudKitContainerOptions?.containerIdentifier ?? "None")")
                }
                return
            }
            print("✅ Core Data store loaded successfully")
            print("✅ CloudKit container: \(storeDescription.cloudKitContainerOptions?.containerIdentifier ?? "None")")
        })

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Ensure fresh data on every fetch (no staleness)
        container.viewContext.stalenessInterval = 0
    }
    
}

// MARK: - Convenience fetch helper (used by deep-link router)
extension PersistenceController {
    /// Fetch a single `MemoryEntry` whose `id` equals the supplied UUID.
    /// Returns `nil` if not found.
    func entry(id: UUID) -> MemoryEntry? {
        guard let uid = MemoryUserScope.currentFirebaseUserId else { return nil }

        let ctx = container.viewContext
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", id as CVarArg),
            NSPredicate(format: "firebaseUserId == %@", uid)
        ])
        request.fetchLimit  = 1
        request.includesPendingChanges = true
        return (try? ctx.fetch(request))?.first
    }

    /// Deletes through a managed object context so the removals are exported to
    /// the user's private CloudKit database instead of bypassing mirroring at SQL level.
    func deleteUserData(firebaseUserId: String) async throws -> AccountLocalCleanupManifest {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let manifest: AccountLocalCleanupManifest = try await context.perform {
            let memoryRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
            memoryRequest.predicate = NSPredicate(format: "firebaseUserId == %@", firebaseUserId)
            memoryRequest.fetchBatchSize = 100
            let memories = try context.fetch(memoryRequest)
            let profileIDs = Set(memories.compactMap(\.profileID))
            let memoryIDs = Set(memories.compactMap(\.id))
            let urls = memories.compactMap(\.audioFileURL)
                .compactMap(URL.init(string:))
                .filter(\.isFileURL)

            for memory in memories {
                context.delete(memory)
            }

            if !profileIDs.isEmpty {
                let characterRequest: NSFetchRequest<GlobalCharacter> = GlobalCharacter.fetchRequest()
                characterRequest.predicate = NSPredicate(format: "profileID IN %@", Array(profileIDs))
                for character in try context.fetch(characterRequest) {
                    context.delete(character)
                }
            }
            if context.hasChanges {
                try context.save()
            }
            return AccountLocalCleanupManifest(
                localFileURLs: urls,
                memoryIDs: memoryIDs,
                profileIDs: profileIDs
            )
        }
        await container.viewContext.perform {
            container.viewContext.reset()
        }
        return manifest
    }
}
