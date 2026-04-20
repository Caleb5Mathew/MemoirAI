import Foundation
import CoreData

enum MemoryUserScope {
    static var currentFirebaseUserId: String? {
        guard let uid = FirebaseConfig.shared.currentUserId?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !uid.isEmpty else {
            return nil
        }
        return uid
    }

    static func profilePredicate(profileID: UUID, includeLegacyUnassigned: Bool = true) -> NSPredicate {
        let profilePredicate = NSPredicate(format: "profileID == %@", profileID as CVarArg)

        guard let uid = currentFirebaseUserId else {
            return profilePredicate
        }

        let ownerPredicate = NSPredicate(format: "firebaseUserId == %@", uid)
        guard includeLegacyUnassigned else {
            return NSCompoundPredicate(andPredicateWithSubpredicates: [profilePredicate, ownerPredicate])
        }

        let legacyPredicate = NSPredicate(format: "firebaseUserId == nil")
        let ownerOrLegacy = NSCompoundPredicate(orPredicateWithSubpredicates: [ownerPredicate, legacyPredicate])
        return NSCompoundPredicate(andPredicateWithSubpredicates: [profilePredicate, ownerOrLegacy])
    }

    static func belongsToCurrentUser(_ entry: MemoryEntry, includeLegacyUnassigned: Bool = true) -> Bool {
        guard let uid = currentFirebaseUserId else {
            return true
        }

        guard let owner = entry.firebaseUserId, !owner.isEmpty else {
            return includeLegacyUnassigned
        }

        return owner == uid
    }
}
