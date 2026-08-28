import Foundation
import SwiftUI
import CoreData
import CryptoKit
import FirebaseFirestore
import FirebaseStorage
#if canImport(UIKit)
import UIKit
#endif

enum ProfileDeletionOutcome: Equatable {
    case deleted
    case lastProfile
    case hasContent
    case verificationFailed
}

enum ProfileDeletionPolicy {
    static func outcome(
        profileCount: Int,
        hasContent: Bool,
        verificationSucceeded: Bool
    ) -> ProfileDeletionOutcome {
        guard profileCount > 1 else { return .lastProfile }
        guard verificationSucceeded else { return .verificationFailed }
        return hasContent ? .hasContent : .deleted
    }
}

enum ProfileStorageScope {
    static func fileName(userID: String) -> String {
        "profiles_\(userID).json"
    }

    static func backupKey(userID: String) -> String {
        "memoir_profiles_backup_\(userID)"
    }

    static func selectedIndexKey(userID: String) -> String {
        "selectedProfileIndex_\(userID)"
    }

    static func cloudSelectedIndexKey(userID: String) -> String {
        "memoir_selectedProfileIndex_\(userID)"
    }

    static func cloudProfileKey(userID: String, profileID: UUID) -> String {
        "memoir_profile_\(userID)_\(profileID.uuidString)"
    }

    static func deletedProfileIDsKey(userID: String) -> String {
        "memoir_deleted_profile_ids_\(userID)"
    }

    static let pendingMutationsKey = "memoir_pending_profile_mutations_v1"
}

struct PendingProfileMutation: Codable, Equatable {
    enum Kind: String, Codable {
        case upsert
        case delete
    }

    let userID: String
    let profileID: UUID
    let kind: Kind
    let profile: Profile?
    let queuedAt: Date
}

enum ProfileMutationQueuePolicy {
    static func enqueued(
        _ mutation: PendingProfileMutation,
        into existing: [PendingProfileMutation]
    ) -> [PendingProfileMutation] {
        existing.filter {
            !($0.userID == mutation.userID && $0.profileID == mutation.profileID)
        } + [mutation]
    }
}

enum ProfileRemoteUpsertPolicy {
    static func shouldApply(
        pendingUpdatedAt: Date,
        remoteUpdatedAt: Date?,
        tombstoneExists: Bool
    ) -> Bool {
        guard !tombstoneExists else { return false }
        guard let remoteUpdatedAt else { return true }
        return pendingUpdatedAt > remoteUpdatedAt
    }
}

enum ProfilePhotoStorageScope {
    static func path(userID: String, profileID: UUID) -> String {
        "users/\(userID)/profiles/\(profileID.uuidString.lowercased())/subjectPhoto.jpg"
    }
}

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var selectedProfileIndex: Int = 0 {
        didSet {
            saveSelectedProfileIndex()
        }
    }

    private var activeUserID: String?

    init() {
        profiles = [Profile(name: "Grandparent", photoData: nil)]
    }

    func activateUser(_ userID: String) async {
        guard let normalizedUserID = MemoryOwnershipPolicy.normalizedUserID(userID) else { return }
        guard activeUserID != normalizedUserID else { return }

        activeUserID = normalizedUserID
        profiles = []
        selectedProfileIndex = 0
        loadProfiles(userID: normalizedUserID)
        await hydrateProfilesFromFirestore(userID: normalizedUserID)

        guard activeUserID == normalizedUserID else { return }

        if profiles.isEmpty {
            profiles = [Profile(name: "Grandparent", photoData: nil)]
        }
        selectedProfileIndex = min(selectedProfileIndex, max(0, profiles.count - 1))
        saveProfiles()
        await replayPendingProfileMutations(for: normalizedUserID)
    }

    var selectedProfile: Profile {
        if profiles.isEmpty {
            let defaultProfile = Profile(name: "Grandparent", photoData: nil)
            profiles.append(defaultProfile)
            selectedProfileIndex = 0
            saveProfiles()
        }

        if !profiles.indices.contains(selectedProfileIndex) {
            selectedProfileIndex = 0
        }

        return profiles[selectedProfileIndex]
    }

    var canCreateNewProfile: Bool {
        let subscriptionManager = RCSubscriptionManager.shared
        
        if subscriptionManager.hasActiveSubscription {
            return true
        }
        
        return profiles.count < 1
    }

    var profileLimitMessage: String {
        let subscriptionManager = RCSubscriptionManager.shared
        
        if subscriptionManager.hasActiveSubscription {
            return "Unlimited profiles available"
        }
        
        if profiles.count >= 1 {
            return "Subscribe to create multiple profiles"
        }
        
        return "You can create 1 free profile"
    }

    func addProfile(_ profile: Profile) -> Bool {
        guard canCreateNewProfile else {
            print("❌ Profile creation blocked - subscription required for multiple profiles")
            return false
        }
        
        var profile = profile
        profile.updatedAt = Date()
        profiles.append(profile)
        selectedProfileIndex = profiles.count - 1
        saveProfiles()
        syncProfileToCloudKit(profile)
        syncProfileToFirestore(profile)
        
        print("✅ Profile added successfully. Total profiles: \(profiles.count)")
        return true
    }

    func deleteSelectedProfile() async -> ProfileDeletionOutcome {
        guard profiles.indices.contains(selectedProfileIndex), let userID = activeUserID else {
            return .verificationFailed
        }
        let profileID = profiles[selectedProfileIndex].id
        guard profiles.count > 1 else { return .lastProfile }

        do {
            let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "firebaseUserId == %@", userID),
                NSPredicate(format: "profileID == %@", profileID as CVarArg)
            ])
            request.fetchLimit = 1
            if try PersistenceController.shared.container.viewContext.count(for: request) > 0 {
                return .hasContent
            }

            let userRef = Firestore.firestore().collection("users").document(userID)
            let remoteQueries: [(String, String)] = [
                ("memories", "profileID"),
                ("bookVersions", "profileID"),
                ("bookVersions", "profileId"),
                ("storybookJobs", "profileId")
            ]
            for (collection, field) in remoteQueries {
                let snapshot = try await userRef.collection(collection)
                    .whereField(field, isEqualTo: profileID.uuidString)
                    .limit(to: 1)
                    .getDocuments()
                if !snapshot.documents.isEmpty { return .hasContent }
            }
        } catch {
            print("Profile deletion verification failed: \(error.localizedDescription)")
            return .verificationFailed
        }

        guard activeUserID == userID,
              profiles.indices.contains(selectedProfileIndex),
              profiles[selectedProfileIndex].id == profileID else {
            return .verificationFailed
        }
        let deletedProfile = profiles.remove(at: selectedProfileIndex)
        var deletedIDs = deletedProfileIDs(userID: userID)
        deletedIDs.insert(deletedProfile.id)
        saveDeletedProfileIDs(deletedIDs, userID: userID)
        selectedProfileIndex = max(0, selectedProfileIndex - 1)
        saveProfiles()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: StorybookStorageScope.migrationFlagKey(
            userID: userID,
            profileID: profileID
        ))
        let cloudStore = NSUbiquitousKeyValueStore.default
        let cloudProfilePrefix = ProfileStorageScope.cloudProfileKey(
            userID: userID,
            profileID: profileID
        )
        for key in cloudStore.dictionaryRepresentation.keys
        where key == cloudProfilePrefix || key.hasPrefix("\(cloudProfilePrefix)_") {
            cloudStore.removeObject(forKey: key)
        }
        cloudStore.removeObject(forKey: StorybookStorageScope.cloudCurrentKey(
            userID: userID,
            profileID: profileID
        ))
        cloudStore.removeObject(forKey: StorybookStorageScope.cloudHistoryKey(
            userID: userID,
            profileID: profileID
        ))
        cloudStore.synchronize()
        enqueueProfileDeletion(deletedProfile.id, userID: userID)
        await replayPendingProfileMutations(for: userID)
        return .deleted
    }

    func resetAfterAccountDeletion(userID: String) {
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.set(true, forKey: AccountCloudDataPolicy.deletionBarrierKey(userID: userID))
        for key in cloudStore.dictionaryRepresentation.keys
        where AccountCloudDataPolicy.shouldRemoveProfileKey(key, userID: userID) {
            cloudStore.removeObject(forKey: key)
        }
        cloudStore.synchronize()
        savePendingProfileMutations(
            loadPendingProfileMutations().filter { $0.userID != userID }
        )

        activeUserID = nil
        profiles = [Profile(name: "Grandparent", photoData: nil)]
        selectedProfileIndex = 0
    }

    func updateSelectedProfile(with newProfile: Profile) {
        guard profiles.indices.contains(selectedProfileIndex) else { return }
        let old = profiles[selectedProfileIndex]
        var newProfile = newProfile
        newProfile.updatedAt = Date()
        profiles[selectedProfileIndex] = newProfile
        saveProfiles()
        syncProfileToCloudKit(newProfile)
        syncProfileToFirestore(newProfile)
        if Self.shouldInvalidateFaceLikeness(old: old, new: newProfile) {
            Task { await recomputeFaceDescriptionIfNeeded(for: newProfile.id) }
        }
    }

    func updateProfile(_ updatedProfile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == updatedProfile.id }) else { return }
        let old = profiles[index]
        var updatedProfile = updatedProfile
        updatedProfile.updatedAt = Date()
        profiles[index] = updatedProfile
        saveProfiles()
        syncProfileToCloudKit(updatedProfile)
        syncProfileToFirestore(updatedProfile)
        if Self.shouldInvalidateFaceLikeness(old: old, new: updatedProfile) {
            Task { await recomputeFaceDescriptionIfNeeded(for: updatedProfile.id) }
        }
    }

    private static func shouldInvalidateFaceLikeness(old: Profile, new: Profile) -> Bool {
        old.photoData != new.photoData || old.ethnicity != new.ethnicity || old.gender != new.gender
    }

    /// Recomputes OpenAI vision likeness text when headshot or ethnicity/gender inputs change.
    func recomputeFaceDescriptionIfNeeded(for profileId: UUID) async {
        guard let userID = activeUserID else { return }
        guard let idx = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        let p = profiles[idx]

        guard let jpeg = p.photoData, !jpeg.isEmpty else {
            if p.faceDescription != nil || p.faceDescriptionPhotoHash != nil {
                profiles[idx].faceDescription = nil
                profiles[idx].faceDescriptionPhotoHash = nil
                profiles[idx].updatedAt = Date()
                saveProfiles()
                syncProfileToCloudKit(profiles[idx])
                syncProfileToFirestore(profiles[idx])
            }
            return
        }

        let fp = Self.faceLikenessCacheFingerprint(jpeg: jpeg, ethnicity: p.ethnicity, gender: p.gender)
        if p.faceDescriptionPhotoHash == fp, let existing = p.faceDescription, !existing.isEmpty {
            return
        }

        let ctx = ImageContext()
        do {
            let desc = try await ctx.faceDescriptor(
                fileID: "profile-local",
                jpegData: jpeg,
                race: p.ethnicity,
                gender: p.gender
            )
            guard activeUserID == userID,
                  let currentIndex = profiles.firstIndex(where: { $0.id == profileId }),
                  Self.faceLikenessCacheFingerprint(
                    jpeg: profiles[currentIndex].photoData ?? Data(),
                    ethnicity: profiles[currentIndex].ethnicity,
                    gender: profiles[currentIndex].gender
                  ) == fp else {
                return
            }
            profiles[currentIndex].faceDescription = desc
            profiles[currentIndex].faceDescriptionPhotoHash = fp
            profiles[currentIndex].updatedAt = Date()
            saveProfiles()
            syncProfileToCloudKit(profiles[currentIndex])
            syncProfileToFirestore(profiles[currentIndex])
            print("✅ Profile face description updated")
        } catch {
            print("⚠️ Face description failed:", error.localizedDescription)
        }
    }

    private static func faceLikenessCacheFingerprint(jpeg: Data, ethnicity: String?, gender: String?) -> String {
        var payload = jpeg
        let meta = "|eth:\(ethnicity ?? "")|gen:\(gender ?? "")|"
        if let m = meta.data(using: .utf8) { payload.append(m) }
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    func updateName(for profile: Profile, to newName: String) {
        guard let index = profiles.firstIndex(of: profile) else { return }
        profiles[index].name = newName
        profiles[index].updatedAt = Date()
        saveProfiles()
        syncProfileToCloudKit(profiles[index])
        syncProfileToFirestore(profiles[index])
    }

    func removePhotoFromSelectedProfile() {
        guard profiles.indices.contains(selectedProfileIndex) else { return }
        let profileId = profiles[selectedProfileIndex].id
        profiles[selectedProfileIndex].photoData = nil
        profiles[selectedProfileIndex].faceDescription = nil
        profiles[selectedProfileIndex].faceDescriptionPhotoHash = nil
        profiles[selectedProfileIndex].updatedAt = Date()
        saveProfiles()
        syncProfileToCloudKit(profiles[selectedProfileIndex])
        syncProfileToFirestore(profiles[selectedProfileIndex])
        // Clear the separate iCloud KV photo key so it can't resurrect on restore
        guard let userID = activeUserID else { return }
        let profileKey = ProfileStorageScope.cloudProfileKey(
            userID: userID,
            profileID: profileId
        )
        NSUbiquitousKeyValueStore.default.removeObject(forKey: "\(profileKey)_photo")
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    func selectPreviousProfile() {
        guard !profiles.isEmpty else { return }
        selectedProfileIndex = (selectedProfileIndex - 1 + profiles.count) % profiles.count
    }

    func selectNextProfile() {
        guard !profiles.isEmpty else { return }
        selectedProfileIndex = (selectedProfileIndex + 1) % profiles.count
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private func profilesURL(userID: String) -> URL {
        getDocumentsDirectory().appendingPathComponent(ProfileStorageScope.fileName(userID: userID))
    }

    private func saveProfiles() {
        guard let userID = activeUserID else { return }
        let url = profilesURL(userID: userID)
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: url)

            let cloudStore = NSUbiquitousKeyValueStore.default
            guard !AccountCloudDataPolicy.isDeletionBarrierActive(
                userID: userID,
                cloudStore: cloudStore
            ) else { return }

            let cloudSnapshot = profilesEncodedForICloudKVS(profiles)
            if let cloudData = cloudSnapshot {
                cloudStore.set(
                    cloudData,
                    forKey: ProfileStorageScope.backupKey(userID: userID)
                )
            } else {
                print("⚠️ Skipping memoir_profiles_backup — payload still too large for iCloud KVS after compression")
            }
            cloudStore.synchronize()
        }
    }

    /// iCloud KVS allows ~1 MB total; keep backups small with JPEG caps and optional photo stripping.
    private func profilesEncodedForICloudKVS(_ source: [Profile]) -> Data? {
        let compressedProfiles = source.map {
            $0.withPhotoData(Self.compressPhotoDataForICloudKVS($0.photoData))
        }
        if let data = try? JSONEncoder().encode(compressedProfiles), data.count <= 950_000 {
            return data
        }
        let withoutPhotos = source.map { $0.withPhotoData(nil) }
        return try? JSONEncoder().encode(withoutPhotos)
    }

#if canImport(UIKit)
    /// Downscale + JPEG-recompress profile photos before writing to `NSUbiquitousKeyValueStore` (1 MB store limit).
    static func compressPhotoDataForICloudKVS(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        let maxBytes = 88_000
        if data.count <= maxBytes { return data }
        guard let image = UIImage(data: data) else { return nil }

        var working = image
        for _ in 0..<6 {
            let w = working.size.width
            let h = working.size.height
            let longest = max(w, h)
            guard longest > 420 else { break }
            let scale = 420 / longest
            let newSize = CGSize(width: max(1, w * scale), height: max(1, h * scale))
            let renderer = UIGraphicsImageRenderer(size: newSize)
            working = renderer.image { _ in
                working.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        var quality: CGFloat = 0.78
        while quality >= 0.32 {
            if let jpeg = working.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return jpeg
            }
            quality -= 0.08
        }
        return working.jpegData(compressionQuality: 0.3)
    }
#else
    static func compressPhotoDataForICloudKVS(_ data: Data?) -> Data? { data }
#endif

    private func loadProfiles(userID: String) {
        let url = profilesURL(userID: userID)
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.synchronize()
        if AccountCloudDataPolicy.isDeletionBarrierActive(userID: userID, cloudStore: cloudStore) {
            try? FileManager.default.removeItem(at: url)
            for key in cloudStore.dictionaryRepresentation.keys
            where AccountCloudDataPolicy.shouldRemoveProfileKey(key, userID: userID) {
                cloudStore.removeObject(forKey: key)
            }
            UserDefaults.standard.removeObject(
                forKey: ProfileStorageScope.selectedIndexKey(userID: userID)
            )
            cloudStore.synchronize()
        }
        var loadedProfiles: [Profile] = []
        
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            loadedProfiles = decoded
        }
        else if UserDefaults.standard.bool(forKey: "firebase_migration_complete_\(userID)"),
                let legacyData = try? Data(
                    contentsOf: getDocumentsDirectory().appendingPathComponent("profiles.json")
                ),
                let decoded = try? JSONDecoder().decode([Profile].self, from: legacyData) {
            loadedProfiles = decoded
            try? legacyData.write(to: url, options: .atomic)
            print("Migrated trusted legacy profiles into the active account namespace")
        }
        else if let backupData = NSUbiquitousKeyValueStore.default.data(
            forKey: ProfileStorageScope.backupKey(userID: userID)
        ),
                let decoded = try? JSONDecoder().decode([Profile].self, from: backupData) {
            loadedProfiles = decoded
            print("🔄 Restored profiles from iCloud backup")
            
            try? backupData.write(to: url)
        }
        
        self.profiles = loadedProfiles

        // Try local first, then iCloud backup
        let localIndexKey = ProfileStorageScope.selectedIndexKey(userID: userID)
        var savedIndex = UserDefaults.standard.integer(forKey: localIndexKey)
        
        // If local is 0 (default) and we have profiles, try iCloud backup
        if savedIndex == 0 && !profiles.isEmpty {
            NSUbiquitousKeyValueStore.default.synchronize()
            let cloudIndex = NSUbiquitousKeyValueStore.default.longLong(
                forKey: ProfileStorageScope.cloudSelectedIndexKey(userID: userID)
            )
            if cloudIndex > 0 {
                savedIndex = Int(cloudIndex)
                // Restore to local storage
                UserDefaults.standard.set(savedIndex, forKey: localIndexKey)
            }
        }
        
        selectedProfileIndex = min(savedIndex, max(0, profiles.count - 1))
    }

    private func saveSelectedProfileIndex() {
        guard let userID = activeUserID else { return }
        UserDefaults.standard.set(
            selectedProfileIndex,
            forKey: ProfileStorageScope.selectedIndexKey(userID: userID)
        )

        let cloudStore = NSUbiquitousKeyValueStore.default
        guard !AccountCloudDataPolicy.isDeletionBarrierActive(
            userID: userID,
            cloudStore: cloudStore
        ) else { return }
        
        // Backup to iCloud for persistence across app deletion/reinstall
        cloudStore.set(
            selectedProfileIndex,
            forKey: ProfileStorageScope.cloudSelectedIndexKey(userID: userID)
        )
        cloudStore.synchronize()
    }
    
    // MARK: - CloudKit Sync Methods
    
    private func syncProfileToCloudKit(_ profile: Profile) {
        guard let userID = activeUserID else { return }
        let cloudStore = NSUbiquitousKeyValueStore.default
        guard AccountCloudDataPolicy.allowsProfileWrite(
            deletionBarrierActive: AccountCloudDataPolicy.isDeletionBarrierActive(
                userID: userID,
                cloudStore: cloudStore
            )
        ) else { return }

        // Sync individual profile fields to CloudKit for enhanced persistence
        let profileKey = ProfileStorageScope.cloudProfileKey(
            userID: userID,
            profileID: profile.id
        )
        let profileForCloud = profile.withPhotoData(Self.compressPhotoDataForICloudKVS(profile.photoData))

        // Store profile data
        if let profileData = try? JSONEncoder().encode(profileForCloud) {
            cloudStore.set(profileData, forKey: profileKey)
        }
        
        // Store individual fields for easier access
        cloudStore.set(profile.name, forKey: "\(profileKey)_name")
        
        if let birthdate = profile.birthdate {
            cloudStore.set(birthdate, forKey: "\(profileKey)_birthdate")
        }
        
        if let ethnicity = profile.ethnicity {
            cloudStore.set(ethnicity, forKey: "\(profileKey)_ethnicity")
        }
        
        if let gender = profile.gender {
            cloudStore.set(gender, forKey: "\(profileKey)_gender")
        }
        
        if let photoData = profileForCloud.photoData {
            cloudStore.set(photoData, forKey: "\(profileKey)_photo")
        } else {
            cloudStore.removeObject(forKey: "\(profileKey)_photo")
        }
        
        cloudStore.synchronize()
        print("Profile synced to CloudKit")
    }

    private func deletedProfileIDs(userID: String) -> Set<UUID> {
        let values = UserDefaults.standard.stringArray(
            forKey: ProfileStorageScope.deletedProfileIDsKey(userID: userID)
        ) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    private func saveDeletedProfileIDs(_ ids: Set<UUID>, userID: String) {
        UserDefaults.standard.set(
            ids.map(\.uuidString).sorted(),
            forKey: ProfileStorageScope.deletedProfileIDsKey(userID: userID)
        )
    }

    private func loadPendingProfileMutations() -> [PendingProfileMutation] {
        guard let data = UserDefaults.standard.data(forKey: ProfileStorageScope.pendingMutationsKey),
              let mutations = try? JSONDecoder().decode([PendingProfileMutation].self, from: data) else {
            return []
        }
        return mutations
    }

    private func savePendingProfileMutations(_ mutations: [PendingProfileMutation]) {
        if mutations.isEmpty {
            UserDefaults.standard.removeObject(forKey: ProfileStorageScope.pendingMutationsKey)
        } else if let data = try? JSONEncoder().encode(mutations) {
            UserDefaults.standard.set(data, forKey: ProfileStorageScope.pendingMutationsKey)
        }
    }

    private func enqueueProfileMutation(_ mutation: PendingProfileMutation) {
        savePendingProfileMutations(
            ProfileMutationQueuePolicy.enqueued(mutation, into: loadPendingProfileMutations())
        )
    }

    private func enqueueProfileDeletion(_ profileID: UUID, userID: String) {
        enqueueProfileMutation(PendingProfileMutation(
            userID: userID,
            profileID: profileID,
            kind: .delete,
            profile: nil,
            queuedAt: Date()
        ))
    }

    private func syncProfileToFirestore(_ profile: Profile) {
        guard let userID = activeUserID,
              !deletedProfileIDs(userID: userID).contains(profile.id) else { return }
        var persistedProfile = profile
        persistedProfile.photoData = nil
        enqueueProfileMutation(PendingProfileMutation(
            userID: userID,
            profileID: profile.id,
            kind: .upsert,
            profile: persistedProfile,
            queuedAt: Date()
        ))
        Task { @MainActor in
            await replayPendingProfileMutations(for: userID)
        }
    }

    func retryPendingProfileMutations() async {
        guard let activeUserID else { return }
        await replayPendingProfileMutations(for: activeUserID)
    }

    private func replayPendingProfileMutations(for userID: String) async {
        guard activeUserID == userID else { return }
        let pending = loadPendingProfileMutations()
            .filter { $0.userID == userID }
            .sorted { $0.queuedAt < $1.queuedAt }
        for mutation in pending {
            guard activeUserID == userID else { return }
            do {
                switch mutation.kind {
                case .upsert:
                    guard let profile = mutation.profile,
                          !deletedProfileIDs(userID: userID).contains(profile.id) else {
                        clearPendingProfileMutation(mutation)
                        continue
                    }
                    let payload: [String: Any] = [
                        "name": profile.name,
                        "birthdate": profile.birthdate.map { Timestamp(date: $0) as Any } ?? NSNull(),
                        "ethnicity": profile.ethnicity.map { $0 as Any } ?? NSNull(),
                        "gender": profile.gender.map { $0 as Any } ?? NSNull(),
                        "createdAt": Timestamp(date: profile.createdAt),
                        "updatedAt": Timestamp(date: profile.updatedAt),
                        "childNames": profile.childNames,
                        "transcriptionGlossary": profile.transcriptionGlossary,
                        "faceDescription": profile.faceDescription.map { $0 as Any } ?? NSNull(),
                        "faceDescriptionPhotoHash": profile.faceDescriptionPhotoHash.map { $0 as Any } ?? NSNull(),
                        "syncedAt": FieldValue.serverTimestamp()
                    ]
                    try await commitProfileUpsert(
                        profile,
                        payload: payload,
                        userID: userID
                    )
                case .delete:
                    try await commitProfileDeletion(mutation.profileID, userID: userID)
                }
                guard activeUserID == userID else { return }
                clearPendingProfileMutation(mutation)
            } catch {
                print("❌ Profile mutation retry deferred: \(error.localizedDescription)")
            }
        }
    }

    private func commitProfileUpsert(
        _ profile: Profile,
        payload: [String: Any],
        userID: String
    ) async throws {
        let database = Firestore.firestore()
        let userRef = database.collection("users").document(userID)
        let profileRef = userRef.collection("profiles").document(profile.id.uuidString)
        let tombstoneRef = userRef.collection("profileTombstones").document(profile.id.uuidString)

        _ = try await database.runTransaction { transaction, errorPointer -> Any? in
            do {
                let tombstone = try transaction.getDocument(tombstoneRef)
                let remoteProfile = try transaction.getDocument(profileRef)
                let remoteUpdatedAt = (remoteProfile.data()?["updatedAt"] as? Timestamp)?.dateValue()
                guard ProfileRemoteUpsertPolicy.shouldApply(
                    pendingUpdatedAt: profile.updatedAt,
                    remoteUpdatedAt: remoteUpdatedAt,
                    tombstoneExists: tombstone.exists
                ) else {
                    return false
                }
                transaction.setData(payload, forDocument: profileRef, merge: true)
                return true
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }
    }

    private func clearPendingProfileMutation(_ mutation: PendingProfileMutation) {
        var pending = loadPendingProfileMutations()
        pending.removeAll {
            $0.userID == mutation.userID
                && $0.profileID == mutation.profileID
                && $0.kind == mutation.kind
                && $0.queuedAt == mutation.queuedAt
        }
        savePendingProfileMutations(pending)
    }

    private func commitProfileDeletion(_ profileID: UUID, userID: String) async throws {
        let userRef = Firestore.firestore().collection("users").document(userID)
        let batch = Firestore.firestore().batch()
        batch.setData(
            ["deletedAt": FieldValue.serverTimestamp(), "schemaVersion": 1],
            forDocument: userRef.collection("profileTombstones").document(profileID.uuidString)
        )
        batch.deleteDocument(userRef.collection("profiles").document(profileID.uuidString))
        try await batch.commit()
        do {
            try await Storage.storage().reference(
                withPath: ProfilePhotoStorageScope.path(userID: userID, profileID: profileID)
            ).delete()
        } catch let error as NSError where error.domain == StorageErrorDomain
            && error.code == StorageErrorCode.objectNotFound.rawValue {
            return
        }
    }

    static func mergedProfiles(
        local: [Profile],
        remote: [Profile],
        deletedIDs: Set<UUID>
    ) -> [Profile] {
        var byID = Dictionary(uniqueKeysWithValues: remote
            .filter { !deletedIDs.contains($0.id) }
            .map { ($0.id, $0) })
        for profile in local where !deletedIDs.contains(profile.id) {
            if let remoteProfile = byID[profile.id], remoteProfile.updatedAt > profile.updatedAt {
                continue
            }
            byID[profile.id] = profile
        }
        return byID.values.sorted { $0.createdAt < $1.createdAt }
    }

    private func hydrateProfilesFromFirestore(userID: String) async {
        do {
            let userRef = Firestore.firestore().collection("users").document(userID)
            let selectedProfileID = profiles.indices.contains(selectedProfileIndex)
                ? profiles[selectedProfileIndex].id
                : nil
            let snapshot = try await userRef.collection("profiles").getDocuments()
            let tombstoneSnapshot = try await userRef.collection("profileTombstones").getDocuments()
            var deletedIDs = deletedProfileIDs(userID: userID)
            deletedIDs.formUnion(tombstoneSnapshot.documents.compactMap { UUID(uuidString: $0.documentID) })
            saveDeletedProfileIDs(deletedIDs, userID: userID)
            var recovered = snapshot.documents.compactMap { document -> Profile? in
                guard let profileID = UUID(uuidString: document.documentID) else { return nil }
                let data = document.data()
                let local = profiles.first { $0.id == profileID }
                return Profile(
                    id: profileID,
                    name: String(data["name"] as? String ?? local?.name ?? "Memoir"),
                    photoData: local?.photoData,
                    birthdate: (data["birthdate"] as? Timestamp)?.dateValue() ?? local?.birthdate,
                    ethnicity: data["ethnicity"] as? String ?? local?.ethnicity,
                    gender: data["gender"] as? String ?? local?.gender,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? local?.createdAt,
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
                        ?? (data["syncedAt"] as? Timestamp)?.dateValue()
                        ?? local?.updatedAt,
                    childNames: data["childNames"] as? [String] ?? local?.childNames ?? [],
                    transcriptionGlossary: data["transcriptionGlossary"] as? [String]
                        ?? local?.transcriptionGlossary
                        ?? [],
                    faceDescription: data["faceDescription"] as? String ?? local?.faceDescription,
                    faceDescriptionPhotoHash: data["faceDescriptionPhotoHash"] as? String
                        ?? local?.faceDescriptionPhotoHash
                )
            }

            if recovered.isEmpty {
                let memories = try await userRef.collection("memories").limit(to: 500).getDocuments()
                var seen = Set<UUID>()
                recovered = memories.documents.compactMap { document in
                    let data = document.data()
                    guard let rawProfileID = data["profileID"] as? String,
                          let profileID = UUID(uuidString: rawProfileID),
                          seen.insert(profileID).inserted else {
                        return nil
                    }
                    let name = (data["profileName"] as? String)?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    let resolvedName = name?.isEmpty == false ? name ?? "Memoir" : "Memoir"
                    return Profile(
                        id: profileID,
                        name: resolvedName,
                        photoData: nil
                    )
                }
            }

            guard activeUserID == userID else { return }
            profiles = Self.mergedProfiles(local: profiles, remote: recovered, deletedIDs: deletedIDs)
            if let selectedProfileID,
               let selectedIndex = profiles.firstIndex(where: { $0.id == selectedProfileID }) {
                selectedProfileIndex = selectedIndex
            } else {
                selectedProfileIndex = 0
            }
            await restoreMissingProfilePhotos(userID: userID)
        } catch {
            print("❌ Could not restore profiles from Firebase: \(error.localizedDescription)")
        }
    }

    private func restoreMissingProfilePhotos(userID: String) async {
        let missingProfileIDs = profiles
            .filter { $0.photoData == nil }
            .prefix(20)
            .map(\.id)
        guard !missingProfileIDs.isEmpty else { return }

        var restoredAny = false
        for profileID in missingProfileIDs {
            do {
                let data = try await Storage.storage().reference(
                    withPath: ProfilePhotoStorageScope.path(userID: userID, profileID: profileID)
                ).data(maxSize: 5 * 1024 * 1024)
                guard activeUserID == userID,
                      let index = profiles.firstIndex(where: { $0.id == profileID }),
                      profiles[index].photoData == nil else { return }
                profiles[index].photoData = data
                restoredAny = true
            } catch let error as NSError where error.domain == StorageErrorDomain
                && error.code == StorageErrorCode.objectNotFound.rawValue {
                continue
            } catch {
                print("Profile photo restore failed: \(error.localizedDescription)")
            }
        }
        if restoredAny, activeUserID == userID {
            saveProfiles()
        }
    }
}
