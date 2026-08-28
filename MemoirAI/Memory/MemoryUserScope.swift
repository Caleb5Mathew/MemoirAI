import Foundation
import CoreData

enum MemoryProfileRecoveryPolicy {
    /// Legacy rows created before profile assignment can be attached to the selected profile.
    /// A non-nil profile is always authoritative and must never be rewritten here.
    static func recoveredProfileID(existingProfileID: UUID?, selectedProfileID: UUID) -> UUID? {
        guard existingProfileID == nil else { return nil }
        return selectedProfileID
    }
}

enum MemoryOwnershipPolicy {
    static let legacyOwnerKey = "local_memory_uid_backfill_owner_v2"
    static let cloudLegacyOwnerKey = "memoir_local_memory_uid_backfill_owner_v2"

    static func normalizedUserID(_ userID: String?) -> String? {
        guard let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else {
            return nil
        }
        return userID
    }

    static func resolvedLegacyOwnerID(localOwnerID: String?, cloudOwnerID: String?) -> String? {
        normalizedUserID(localOwnerID) ?? normalizedUserID(cloudOwnerID)
    }

    static func canClaimLegacyRows(
        claimedOwnerID: String?,
        currentUserID: String?,
        deletionBarrierActive: Bool = false
    ) -> Bool {
        guard !deletionBarrierActive else { return false }
        guard let currentUserID = normalizedUserID(currentUserID) else { return false }
        guard let claimedOwnerID = normalizedUserID(claimedOwnerID) else { return true }
        return claimedOwnerID == currentUserID
    }

    static func belongsToUser(entryOwnerID: String?, currentUserID: String?) -> Bool {
        guard let currentUserID = normalizedUserID(currentUserID),
              let entryOwnerID = normalizedUserID(entryOwnerID) else {
            return false
        }
        return entryOwnerID == currentUserID
    }

    static func canAttemptRemoteWrite(intendedUserID: String?, currentUserID: String?) -> Bool {
        guard let intendedUserID = normalizedUserID(intendedUserID),
              let currentUserID = normalizedUserID(currentUserID) else {
            return false
        }
        return intendedUserID == currentUserID
    }
}

enum MemoryUserScope {
    static var currentFirebaseUserId: String? {
        MemoryOwnershipPolicy.normalizedUserID(FirebaseConfig.shared.currentUserId)
    }

    static func recordingStartFailureMessage(firebaseUserID: String?) -> String? {
        guard MemoryOwnershipPolicy.normalizedUserID(firebaseUserID) != nil else {
            return "MemoirAI needs a secure connection before recording so your memory can be saved safely. Check your internet connection and try again."
        }
        return nil
    }

    static func profilePredicate(profileID: UUID) -> NSPredicate {
        guard let uid = currentFirebaseUserId else {
            return NSPredicate(value: false)
        }

        let profilePredicate = NSPredicate(format: "profileID == %@", profileID as CVarArg)
        let ownerPredicate = NSPredicate(format: "firebaseUserId == %@", uid)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [profilePredicate, ownerPredicate])
    }

    static func belongsToCurrentUser(_ entry: MemoryEntry) -> Bool {
        MemoryOwnershipPolicy.belongsToUser(
            entryOwnerID: entry.firebaseUserId,
            currentUserID: currentFirebaseUserId
        )
    }
}
