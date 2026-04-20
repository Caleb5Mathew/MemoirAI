//
//  GlobalCharacterManager.swift
//  MemoirAI
//
//  Manages global character registry - links characters across memories
//

import Foundation
import CoreData

@MainActor
class GlobalCharacterManager {
    static let shared = GlobalCharacterManager()
    
    private let context: NSManagedObjectContext
    
    private init() {
        self.context = PersistenceController.shared.container.viewContext
    }
    
    // MARK: - CRUD Operations
    
    /// Find or create a global character by name for a profile
    func findOrCreateGlobalCharacter(name: String, profileID: UUID) -> UUID {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Try to find existing character
        let request: NSFetchRequest<GlobalCharacter> = GlobalCharacter.fetchRequest()
        request.predicate = NSPredicate(
            format: "canonicalName ==[c] %@ AND profileID == %@",
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            profileID as CVarArg
        )
        request.fetchLimit = 1
        
        if let existing = try? context.fetch(request).first,
           let existingId = existing.id {
            return existingId
        }
        
        // Create new global character
        let newCharacter = GlobalCharacter(context: context)
        let newId = UUID()
        newCharacter.id = newId
        newCharacter.canonicalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        newCharacter.profileID = profileID
        newCharacter.createdAt = Date()
        
        do {
            try context.save()
            print("✅ Created new global character: \(name) (ID: \(newId.uuidString))")
            return newId
        } catch {
            print("❌ Failed to create global character: \(error)")
            // Return the UUID we created even if save failed
            return newId
        }
    }
    
    /// Get all global characters for a profile
    func getAllGlobalCharacters(for profileID: UUID) -> [GlobalCharacter] {
        let request: NSFetchRequest<GlobalCharacter> = GlobalCharacter.fetchRequest()
        request.predicate = NSPredicate(format: "profileID == %@", profileID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GlobalCharacter.canonicalName, ascending: true)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("❌ Failed to fetch global characters: \(error)")
            return []
        }
    }
    
    /// Get global character by ID
    func getGlobalCharacter(id: UUID) -> GlobalCharacter? {
        let request: NSFetchRequest<GlobalCharacter> = GlobalCharacter.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    /// Get global character by name (case-insensitive)
    func getGlobalCharacter(name: String, profileID: UUID) -> GlobalCharacter? {
        let request: NSFetchRequest<GlobalCharacter> = GlobalCharacter.fetchRequest()
        request.predicate = NSPredicate(
            format: "canonicalName ==[c] %@ AND profileID == %@",
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            profileID as CVarArg
        )
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    // MARK: - Character Appearance Management
    
    /// Get the most recent appearance of a character across all memories
    func getMostRecentAppearance(globalCharacterId: UUID, profileID: UUID) -> CharacterDetails.Character? {
        // Find all memories for this profile
        let memoryRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        memoryRequest.predicate = MemoryUserScope.profilePredicate(profileID: profileID)
        memoryRequest.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]
        
        guard let memories = try? context.fetch(memoryRequest) else {
            return nil
        }
        
        // Search through memories for this character
        for memory in memories {
            guard let detailsString = memory.characterDetails,
                  let data = detailsString.data(using: .utf8),
                  let characterDetails = try? JSONDecoder().decode(CharacterDetails.self, from: data) else {
                continue
            }
            
            // Find character with matching globalCharacterId
            if let character = characterDetails.characters.first(where: { $0.globalCharacterId == globalCharacterId }) {
                return character
            }
        }
        
        return nil
    }
    
    /// Get all appearances of a character across memories
    func getAllAppearances(globalCharacterId: UUID, profileID: UUID) -> [(memory: MemoryEntry, character: CharacterDetails.Character)] {
        var appearances: [(memory: MemoryEntry, character: CharacterDetails.Character)] = []
        
        let memoryRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        memoryRequest.predicate = MemoryUserScope.profilePredicate(profileID: profileID)
        memoryRequest.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]
        
        guard let memories = try? context.fetch(memoryRequest) else {
            return appearances
        }
        
        for memory in memories {
            guard let detailsString = memory.characterDetails,
                  let data = detailsString.data(using: .utf8),
                  let characterDetails = try? JSONDecoder().decode(CharacterDetails.self, from: data) else {
                continue
            }
            
            if let character = characterDetails.characters.first(where: { $0.globalCharacterId == globalCharacterId }) {
                appearances.append((memory: memory, character: character))
            }
        }
        
        return appearances
    }
    
    /// Count how many memories a character appears in
    func getMemoryCount(globalCharacterId: UUID, profileID: UUID) -> Int {
        return getAllAppearances(globalCharacterId: globalCharacterId, profileID: profileID).count
    }
    
    // MARK: - Migration
    
    /// Migrate existing memories to use global character registry
    /// Scans ALL memories (including orphaned ones), creates global characters, and links existing character instances
    func migrateExistingCharacters(for profileID: UUID) {
        print("🔄 Starting character migration for profile: \(profileID.uuidString)")
        
        // Fetch ALL memories (not filtered by profileID) to catch orphaned memories too
        let memoryRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        if let uid = MemoryUserScope.currentFirebaseUserId {
            memoryRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "firebaseUserId == %@", uid),
                NSPredicate(format: "firebaseUserId == nil")
            ])
        }
        
        guard let allMemories = try? context.fetch(memoryRequest) else {
            print("❌ Failed to fetch memories for migration")
            return
        }
        
        print("📊 Found \(allMemories.count) total memories in database")
        
        // Count memories with character details
        let memoriesWithCharacters = allMemories.filter { 
            $0.characterDetails != nil && !($0.characterDetails?.isEmpty ?? true) 
        }
        print("📊 Found \(memoriesWithCharacters.count) memories with character details")
        
        var updatedCount = 0
        var globalCharactersCreated = 0
        var orphanedMemoriesFixed = 0
        
        for memory in allMemories {
            // Fix orphaned memories - reassign to current profile
            if memory.profileID != profileID {
                memory.profileID = profileID
                orphanedMemoriesFixed += 1
            }
            
            guard let detailsString = memory.characterDetails,
                  !detailsString.isEmpty,
                  let data = detailsString.data(using: .utf8),
                  var characterDetails = try? JSONDecoder().decode(CharacterDetails.self, from: data) else {
                continue
            }
            
            var needsUpdate = false
            
            // Process each character in this memory
            for index in characterDetails.characters.indices {
                let character = characterDetails.characters[index]
                
                // Skip if already linked
                if character.globalCharacterId != nil {
                    continue
                }
                
                // Skip if no name
                guard !character.name.isEmpty else {
                    continue
                }
                
                // Find or create global character
                let globalId = findOrCreateGlobalCharacter(
                    name: character.name,
                    profileID: profileID
                )
                
                // Link this character instance to global character
                characterDetails.characters[index].globalCharacterId = globalId
                needsUpdate = true
                
                // Check if this was a new global character
                if let globalChar = getGlobalCharacter(id: globalId),
                   let createdAt = globalChar.createdAt,
                   abs(createdAt.timeIntervalSinceNow) < 1.0 {
                    // Created within last second, likely new
                    globalCharactersCreated += 1
                }
                
                print("🔗 Linked character '\(character.name)' to global ID: \(globalId.uuidString)")
            }
            
            // Save updated character details if changed
            if needsUpdate {
                if let encoded = try? JSONEncoder().encode(characterDetails),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    memory.setValue(jsonString, forKey: "characterDetails")
                    updatedCount += 1
                }
            }
        }
        
        // Save all changes
        do {
            try context.save()
            print("✅ Migration complete:")
            print("   - Fixed \(orphanedMemoriesFixed) orphaned memories")
            print("   - Updated \(updatedCount) memories with character links")
            print("   - Created \(globalCharactersCreated) new global characters")
        } catch {
            print("❌ Failed to save migration changes: \(error)")
        }
    }
    
    // MARK: - Character Merging
    
    /// Merge two global characters (combines appearances, keeps the first one)
    func mergeCharacters(sourceId: UUID, into targetId: UUID, profileID: UUID) -> Bool {
        guard let source = getGlobalCharacter(id: sourceId),
              let target = getGlobalCharacter(id: targetId) else {
            return false
        }
        
        // Get all memories with source character
        let memoryRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        memoryRequest.predicate = MemoryUserScope.profilePredicate(profileID: profileID)
        
        guard let memories = try? context.fetch(memoryRequest) else {
            return false
        }
        
        var updatedCount = 0
        
        for memory in memories {
            guard let detailsString = memory.characterDetails,
                  let data = detailsString.data(using: .utf8),
                  var characterDetails = try? JSONDecoder().decode(CharacterDetails.self, from: data) else {
                continue
            }
            
            // Update any characters with sourceId to use targetId
            var updated = false
            for index in characterDetails.characters.indices {
                if characterDetails.characters[index].globalCharacterId == sourceId {
                    characterDetails.characters[index].globalCharacterId = targetId
                    updated = true
                }
            }
            
            if updated {
                // Save updated character details
                if let encoded = try? JSONEncoder().encode(characterDetails),
                   let jsonString = String(data: encoded, encoding: .utf8) {
                    memory.setValue(jsonString, forKey: "characterDetails")
                    updatedCount += 1
                }
            }
        }
        
        // Delete source character
        context.delete(source)
        
        do {
            try context.save()
            print("✅ Merged character \(source.canonicalName ?? "") into \(target.canonicalName ?? ""), updated \(updatedCount) memories")
            return true
        } catch {
            print("❌ Failed to merge characters: \(error)")
            return false
        }
    }
}
