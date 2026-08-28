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
import SwiftUI

@MainActor
final class PersistenceLoadMonitor: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    static let shared = PersistenceLoadMonitor()
    @Published private(set) var state: State = .loading

    private init() {}

    func report(_ error: NSError) {
        state = .failed(PersistenceConfigurationPolicy.recoveryMessage(error: error))
    }

    func markReady() {
        state = .ready
    }
}

enum PersistenceConfigurationPolicy {
    static func allowsApplicationContent(state: PersistenceLoadMonitor.State) -> Bool {
        state == .ready
    }

    static func usesCloudKit(inMemory: Bool, isRunningTests: Bool) -> Bool {
        !inMemory && !isRunningTests
    }

    static func shouldRetryLocalOnly(error: NSError, attemptedCloudKit: Bool) -> Bool {
        attemptedCloudKit
            && error.domain == NSCocoaErrorDomain
            && [134060, 134400].contains(error.code)
    }

    static func recoveryMessage(error: NSError) -> String {
        "Memoir could not open its saved data. Your existing store was preserved. Free device storage, restart the app, and contact support if this continues. (\(error.code))"
    }
}

enum RecordingOrphanCleanup {
    static func removeStaleRecordings(
        in directory: URL,
        referencedFileURLs: Set<URL>,
        now: Date,
        gracePeriod: TimeInterval = 30 * 24 * 60 * 60,
        fileManager: FileManager = .default
    ) -> [URL] {
        let candidates = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var removed: [URL] = []
        for url in candidates {
            guard ["m4a", "caf"].contains(url.pathExtension.lowercased()),
                  UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                  !referencedFileURLs.contains(url),
                  let modifiedAt = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                  ).contentModificationDate,
                  now.timeIntervalSince(modifiedAt) >= gracePeriod else { continue }
            do {
                try fileManager.removeItem(at: url)
                removed.append(url)
            } catch {
                print("Recording orphan cleanup failed for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return removed
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
            print("Preview data save failed: \(error.localizedDescription)")
        }

        return controller
    }()

    // MARK: - Core-Data container
    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        let persistentContainer = NSPersistentCloudKitContainer(name: "MemoirDataModel")
        container = persistentContainer

        let description = persistentContainer.persistentStoreDescriptions.first
            ?? NSPersistentStoreDescription()
        if persistentContainer.persistentStoreDescriptions.isEmpty {
            persistentContainer.persistentStoreDescriptions = [description]
        }
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
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
                    Self.loadEmergencyInMemoryStore(
                        container: persistentContainer,
                        originalError: error
                    )
                    return
                }
                description.cloudKitContainerOptions = nil
                persistentContainer.loadPersistentStores { localDescription, localError in
                    if let localError = localError as NSError? {
                        Self.loadEmergencyInMemoryStore(
                            container: persistentContainer,
                            originalError: localError
                        )
                        return
                    }
                    print("⚠️ CloudKit unavailable (\(error.code)); local Core Data fallback loaded")
                    print("✅ CloudKit container: \(localDescription.cloudKitContainerOptions?.containerIdentifier ?? "None")")
                    Task { @MainActor in
                        PersistenceLoadMonitor.shared.markReady()
                    }
                }
                return
            }
            print("✅ Core Data store loaded successfully")
            print("✅ CloudKit container: \(storeDescription.cloudKitContainerOptions?.containerIdentifier ?? "None")")
            Task { @MainActor in
                PersistenceLoadMonitor.shared.markReady()
            }
        })

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Ensure fresh data on every fetch (no staleness)
        container.viewContext.stalenessInterval = 0
    }

    private static func loadEmergencyInMemoryStore(
        container: NSPersistentCloudKitContainer,
        originalError: NSError
    ) {
        let emergencyDescription = NSPersistentStoreDescription()
        emergencyDescription.type = NSInMemoryStoreType
        emergencyDescription.url = URL(fileURLWithPath: "/dev/null")
        emergencyDescription.cloudKitContainerOptions = nil
        container.persistentStoreDescriptions = [emergencyDescription]
        container.loadPersistentStores { _, emergencyError in
            if let emergencyError {
                print("Emergency Core Data store failed: \(emergencyError.localizedDescription)")
            } else {
                print("Loaded emergency in-memory Core Data store; original store remains untouched")
            }
            Task { @MainActor in
                PersistenceLoadMonitor.shared.report(originalError)
            }
        }
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
    func deleteUserData(
        firebaseUserId: String,
        knownProfileIDs: Set<UUID> = []
    ) async throws -> AccountLocalCleanupManifest {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let manifest: AccountLocalCleanupManifest = try await context.perform {
            let memoryRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
            memoryRequest.predicate = NSPredicate(format: "firebaseUserId == %@", firebaseUserId)
            memoryRequest.fetchBatchSize = 100
            let memories = try context.fetch(memoryRequest)
            var profileIDs = Set(memories.compactMap(\.profileID)).union(knownProfileIDs)
            let memoryIDs = Set(memories.compactMap(\.id))
            let urls = memories.compactMap(\.audioFileURL)
                .compactMap(URL.init(string:))
                .filter(\.isFileURL)

            for memory in memories {
                context.delete(memory)
            }

            let characterRequest: NSFetchRequest<GlobalCharacter> = GlobalCharacter.fetchRequest()
            characterRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "firebaseUserId == %@", firebaseUserId),
                NSPredicate(
                    format: "firebaseUserId == nil AND profileID IN %@",
                    Array(profileIDs)
                )
            ])
            for character in try context.fetch(characterRequest) {
                if let profileID = character.profileID { profileIDs.insert(profileID) }
                context.delete(character)
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
