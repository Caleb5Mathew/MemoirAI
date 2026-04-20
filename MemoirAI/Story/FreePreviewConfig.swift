//
//  FreePreviewConfig.swift
//  MemoirAI
//
//  Created by user941803 on 7/4/25.
//

import Foundation
import FirebaseAuth

/// Central place for free-preview limits so we only change one number.
/// Uses iCloud KV store as primary source of truth (harder to hack) with UserDefaults as backup.
/// Quota is scoped per Firebase Auth user so multiple accounts on one device each get their own preview pool.
struct FreePreviewConfig {
    /// Maximum pages (images) a non-subscriber can generate in their free preview.
    static let maxPagesWithoutSubscription = 3

    // MARK: - Storage Keys

    private static let freeImagesUsedKeyPrefix = "memoirai_freePreviewImagesUsed"
    private static let legacyBoolKeyPrefix = "memoirai_freeBookUsed"

    /// Pre–user-scoping keys (legacy global, one pool per device / iCloud account).
    private static let legacyGlobalCountKey = "memoirai_freePreviewImagesUsed"
    private static let legacyGlobalBoolKey = "memoirai_freeBookUsed"

    private static func freeImagesUsedKey(for uid: String) -> String {
        "\(freeImagesUsedKeyPrefix)_\(uid)"
    }

    private static func legacyBoolKey(for uid: String) -> String {
        "\(legacyBoolKeyPrefix)_\(uid)"
    }

    // MARK: - Auth

    /// Free preview reads/writes require a signed-in Firebase user (anonymous is fine).
    private static var firebaseUID: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - Get Used Count (iCloud as primary, UserDefaults as backup)

    /// Returns the number of free preview images the user has consumed.
    /// Before Firebase auth completes, returns `0` (optimistic full quota; nothing is persisted yet).
    static var freeImagesUsed: Int {
        guard let uid = firebaseUID else {
            return 0
        }

        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.synchronize()

        let countKey = freeImagesUsedKey(for: uid)
        let userLegacyKey = legacyBoolKey(for: uid)

        let hasLocalValue = UserDefaults.standard.object(forKey: countKey) != nil
        let hasCloudValue = cloudStore.object(forKey: countKey) != nil

        // First time we see this UID — migrate global legacy keys once, then clear them so new users on this device are not blocked.
        if !hasLocalValue && !hasCloudValue {
            let globalLegacy = cloudStore.bool(forKey: legacyGlobalBoolKey)
                || UserDefaults.standard.bool(forKey: legacyGlobalBoolKey)
            if globalLegacy {
                setFreeImagesUsed(maxPagesWithoutSubscription)
                clearGlobalLegacyKeys()
                return maxPagesWithoutSubscription
            }
            return 0
        }

        let cloudCount = Int(cloudStore.longLong(forKey: countKey))
        let localCount = UserDefaults.standard.integer(forKey: countKey)

        // Per-user legacy bool (if we ever wrote it) + empty counters → treat as fully used.
        let userLegacy = cloudStore.bool(forKey: userLegacyKey)
            || UserDefaults.standard.bool(forKey: userLegacyKey)
        if userLegacy && cloudCount == 0 && localCount == 0 {
            setFreeImagesUsed(maxPagesWithoutSubscription)
            return maxPagesWithoutSubscription
        }

        return max(cloudCount, localCount)
    }

    // MARK: - Set Used Count

    /// Updates the free preview usage count in both iCloud and UserDefaults.
    static func setFreeImagesUsed(_ count: Int) {
        guard let uid = firebaseUID else {
            print("FreePreviewConfig: skip setFreeImagesUsed — no Firebase user yet")
            return
        }

        let cloudStore = NSUbiquitousKeyValueStore.default
        let countKey = freeImagesUsedKey(for: uid)

        cloudStore.set(Int64(count), forKey: countKey)
        cloudStore.synchronize()

        UserDefaults.standard.set(count, forKey: countKey)
        UserDefaults.standard.synchronize()

        print("FreePreviewConfig: Updated free images used to \(count) (uid: \(uid))")
    }

    // MARK: - Increment Used Count

    /// Increments the free preview usage count by the specified amount.
    static func incrementFreeImagesUsed(by amount: Int = 1) {
        guard firebaseUID != nil else {
            print("FreePreviewConfig: skip increment — no Firebase user yet")
            return
        }
        let newCount = min(freeImagesUsed + amount, maxPagesWithoutSubscription)
        setFreeImagesUsed(newCount)
    }

    // MARK: - Remaining Count

    /// Returns how many free preview images the user has remaining.
    static var freeImagesRemaining: Int {
        max(0, maxPagesWithoutSubscription - freeImagesUsed)
    }

    // MARK: - Can Generate

    /// Returns true if the user can still generate free preview images.
    static var canGenerateFreePreview: Bool {
        freeImagesRemaining > 0
    }

    // MARK: - Debug

    static func printStatus() {
        print("FreePreviewConfig Status:")
        print("   Max allowed: \(maxPagesWithoutSubscription)")
        print("   Firebase UID: \(firebaseUID ?? "(nil — pre-auth)")")
        print("   Used: \(freeImagesUsed)")
        print("   Remaining: \(freeImagesRemaining)")
        print("   Can generate: \(canGenerateFreePreview)")
    }

    // MARK: - Legacy cleanup

    private static func clearGlobalLegacyKeys() {
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.removeObject(forKey: legacyGlobalBoolKey)
        cloudStore.removeObject(forKey: legacyGlobalCountKey)
        cloudStore.synchronize()

        UserDefaults.standard.removeObject(forKey: legacyGlobalBoolKey)
        UserDefaults.standard.removeObject(forKey: legacyGlobalCountKey)
        UserDefaults.standard.synchronize()

        print("FreePreviewConfig: Cleared global legacy free-preview keys after migration")
    }

    // MARK: - Simulator

#if targetEnvironment(simulator)
    /// Runs once per install (UserDefaults flag) so simulator devs get a clean quota after erase,
    /// without wiping quota on every launch (preserves testing exhaustion mid-session).
    private static let simulatorCleanupUserDefaultsKey = "MemoirAI_SimulatorFreePreviewSanitized_v2"

    static func applySimulatorStaleDataCleanupIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: simulatorCleanupUserDefaultsKey) else { return }

        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.synchronize()

        let localKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in localKeys where shouldClearPreviewStorageKey(key) {
            UserDefaults.standard.removeObject(forKey: key)
        }

        for key in cloudStore.dictionaryRepresentation.keys where shouldClearPreviewStorageKey(key) {
            cloudStore.removeObject(forKey: key)
        }
        cloudStore.synchronize()

        UserDefaults.standard.set(true, forKey: simulatorCleanupUserDefaultsKey)
        UserDefaults.standard.synchronize()
        print("Simulator: cleared free preview / legacy KV keys (one-shot per install)")
    }

    private static func shouldClearPreviewStorageKey(_ key: String) -> Bool {
        key.hasPrefix(freeImagesUsedKeyPrefix) || key.hasPrefix(legacyBoolKeyPrefix)
    }
#endif
}
