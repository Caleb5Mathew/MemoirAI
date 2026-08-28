import Foundation

enum OnboardingCompletionState {
    static func resolved(local: Bool, cloud: Bool) -> Bool {
        local || cloud
    }
}

enum AccountCloudDataPolicy {
    static let legacyDeletionBarrierKey = "memoir_account_deletion_barrier_v1"

    static func deletionBarrierKey(userID: String) -> String {
        "memoir_account_deletion_barrier_v2_\(userID)"
    }

    static func isDeletionBarrierActive(
        userID: String?,
        cloudStore: NSUbiquitousKeyValueStore = .default
    ) -> Bool {
        if cloudStore.bool(forKey: legacyDeletionBarrierKey) { return true }
        guard let userID = MemoryOwnershipPolicy.normalizedUserID(userID) else { return false }
        return cloudStore.bool(forKey: deletionBarrierKey(userID: userID))
    }

    static func allowsProfileWrite(deletionBarrierActive: Bool) -> Bool {
        !deletionBarrierActive
    }

    static func shouldRemoveProfileKey(_ key: String, userID: String) -> Bool {
        key.contains(userID) && (
            key.hasPrefix("memoir_profiles_backup_")
                || key.hasPrefix("memoir_selectedProfileIndex_")
                || key.hasPrefix("memoir_profile_")
                || key.hasPrefix("memoir_storybook_")
        )
    }
}

@MainActor
final class iCloudManager: ObservableObject {
    static let shared = iCloudManager()
    
    @Published var hasCompletedOnboarding: Bool = false
    
    private let key = "hasCompletedOnboarding"              // iCloud key
    private let localKey = "hasCompletedOnboarding_local"    // local fallback
    private let cloudStore = NSUbiquitousKeyValueStore.default
    
    private init() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.ubiquitousKeyValueStoreDidChange(_:)),
                                               name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: cloudStore)
        // Load initial value from UserDefaults for instant availability
        let local = UserDefaults.standard.bool(forKey: localKey)
        cloudStore.synchronize()
        let cloudVal = cloudStore.bool(forKey: key)
        let resolved = AccountCloudDataPolicy.isDeletionBarrierActive(
            userID: MemoryUserScope.currentFirebaseUserId,
            cloudStore: cloudStore
        )
            ? false
            : OnboardingCompletionState.resolved(local: local, cloud: cloudVal)
        self.hasCompletedOnboarding = resolved
        if resolved != local {
            UserDefaults.standard.set(resolved, forKey: localKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    func completeOnboarding() {
        if let userID = MemoryUserScope.currentFirebaseUserId {
            cloudStore.removeObject(forKey: AccountCloudDataPolicy.deletionBarrierKey(userID: userID))
        }
        cloudStore.removeObject(forKey: AccountCloudDataPolicy.legacyDeletionBarrierKey)
        hasCompletedOnboarding = true
        // Persist locally for immediate next launch
        UserDefaults.standard.set(true, forKey: localKey)
        UserDefaults.standard.synchronize()
        
        // Persist to iCloud
        cloudStore.set(true, forKey: key)
        cloudStore.synchronize()
    }

    func resetAfterAccountDeletion(userID: String) {
        cloudStore.set(true, forKey: AccountCloudDataPolicy.deletionBarrierKey(userID: userID))
        cloudStore.removeObject(forKey: key)
        cloudStore.synchronize()
        UserDefaults.standard.removeObject(forKey: localKey)
        hasCompletedOnboarding = false
    }
    
    @objc private func ubiquitousKeyValueStoreDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonForChange = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber else { return }
        
        let reason = reasonForChange.intValue
        guard reason == NSUbiquitousKeyValueStoreServerChange
                || reason == NSUbiquitousKeyValueStoreInitialSyncChange else { return }
        
        if AccountCloudDataPolicy.isDeletionBarrierActive(
            userID: MemoryUserScope.currentFirebaseUserId,
            cloudStore: cloudStore
        ) {
            hasCompletedOnboarding = false
            UserDefaults.standard.removeObject(forKey: localKey)
            return
        }

        let cloudValue = cloudStore.bool(forKey: key)
        let resolved = OnboardingCompletionState.resolved(
            local: self.hasCompletedOnboarding,
            cloud: cloudValue
        )
        guard self.hasCompletedOnboarding != resolved else { return }
        
        // Never flip false→true mid-session: it yanks the user out of the
        // onboarding carousel. The correct value will be picked up on the
        // next cold launch via init(), which reads the iCloud KVS cache
        // synchronously before the view tree is built.
        if resolved && !self.hasCompletedOnboarding {
            return
        }

        self.hasCompletedOnboarding = resolved
        UserDefaults.standard.set(resolved, forKey: localKey)
    }

    func resetOnboardingForDebug() {
#if DEBUG
        hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: localKey)
        cloudStore.set(false, forKey: key)
        cloudStore.synchronize()
#endif
    }
}
