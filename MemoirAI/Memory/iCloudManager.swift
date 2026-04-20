import Foundation

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
        self.hasCompletedOnboarding = local
        
        // Initial iCloud sync (may update the value later)
        cloudStore.synchronize()
        let cloudVal = cloudStore.bool(forKey: key)
        if cloudVal != local {
            self.hasCompletedOnboarding = cloudVal
            UserDefaults.standard.set(cloudVal, forKey: localKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        // Persist locally for immediate next launch
        UserDefaults.standard.set(true, forKey: localKey)
        UserDefaults.standard.synchronize()
        
        // Persist to iCloud
        cloudStore.set(true, forKey: key)
        cloudStore.synchronize()
    }
    
    @objc private func ubiquitousKeyValueStoreDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonForChange = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber else { return }
        
        let reason = reasonForChange.intValue
        guard reason == NSUbiquitousKeyValueStoreServerChange
                || reason == NSUbiquitousKeyValueStoreInitialSyncChange else { return }
        
        let cloudValue = cloudStore.bool(forKey: key)
        guard self.hasCompletedOnboarding != cloudValue else { return }
        
        // Never flip false→true mid-session: it yanks the user out of the
        // onboarding carousel. The correct value will be picked up on the
        // next cold launch via init(), which reads the iCloud KVS cache
        // synchronously before the view tree is built.
        if cloudValue && !self.hasCompletedOnboarding {
            return
        }
        
        self.hasCompletedOnboarding = cloudValue
        UserDefaults.standard.set(cloudValue, forKey: localKey)
    }
}
