import Foundation
import SwiftUI
import CoreData

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var selectedProfileIndex: Int = 0 {
        didSet {
            saveSelectedProfileIndex()
        }
    }

    private let profilesKey = "profiles.json"
    private let selectedIndexKey = "selectedProfileIndex"

    init() {
        loadProfiles()
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
        
        profiles.append(profile)
        selectedProfileIndex = profiles.count - 1
        saveProfiles()
        syncProfileToCloudKit(profile)
        
        print("✅ Profile added successfully. Total profiles: \(profiles.count)")
        return true
    }

    func deleteSelectedProfile() {
        guard profiles.indices.contains(selectedProfileIndex) else { return }
        
        guard profiles.count > 1 else {
            print("❌ Cannot delete the last profile")
            return
        }
        
        profiles.remove(at: selectedProfileIndex)
        selectedProfileIndex = max(0, selectedProfileIndex - 1)
        saveProfiles()
    }

    func updateSelectedProfile(with newProfile: Profile) {
        guard profiles.indices.contains(selectedProfileIndex) else { return }
        profiles[selectedProfileIndex] = newProfile
        saveProfiles()
        syncProfileToCloudKit(newProfile)
    }

    func updateName(for profile: Profile, to newName: String) {
        guard let index = profiles.firstIndex(of: profile) else { return }
        profiles[index].name = newName
        saveProfiles()
    }

    func removePhotoFromSelectedProfile() {
        guard profiles.indices.contains(selectedProfileIndex) else { return }
        profiles[selectedProfileIndex].photoData = nil
        saveProfiles()
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

    private func saveProfiles() {
        let url = getDocumentsDirectory().appendingPathComponent(profilesKey)
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: url)
            
            NSUbiquitousKeyValueStore.default.set(data, forKey: "memoir_profiles_backup")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    private func loadProfiles() {
        let url = getDocumentsDirectory().appendingPathComponent(profilesKey)
        var loadedProfiles: [Profile] = []
        
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            loadedProfiles = decoded
        }
        else if let backupData = NSUbiquitousKeyValueStore.default.data(forKey: "memoir_profiles_backup"),
                let decoded = try? JSONDecoder().decode([Profile].self, from: backupData) {
            loadedProfiles = decoded
            print("🔄 Restored profiles from iCloud backup")
            
            try? backupData.write(to: url)
        }
        
        self.profiles = loadedProfiles

        if profiles.isEmpty {
            let defaultProfile = Profile(name: "Grandparent", photoData: nil)
            profiles.append(defaultProfile)
            selectedProfileIndex = 0
            saveProfiles()
        }

        // Try local first, then iCloud backup
        var savedIndex = UserDefaults.standard.integer(forKey: selectedIndexKey)
        
        // If local is 0 (default) and we have profiles, try iCloud backup
        if savedIndex == 0 && !profiles.isEmpty {
            NSUbiquitousKeyValueStore.default.synchronize()
            let cloudIndex = NSUbiquitousKeyValueStore.default.longLong(forKey: "memoir_selectedProfileIndex")
            if cloudIndex > 0 {
                savedIndex = Int(cloudIndex)
                // Restore to local storage
                UserDefaults.standard.set(savedIndex, forKey: selectedIndexKey)
            }
        }
        
        selectedProfileIndex = min(savedIndex, max(0, profiles.count - 1))
    }

    private func saveSelectedProfileIndex() {
        UserDefaults.standard.set(selectedProfileIndex, forKey: selectedIndexKey)
        
        // Backup to iCloud for persistence across app deletion/reinstall
        NSUbiquitousKeyValueStore.default.set(selectedProfileIndex, forKey: "memoir_selectedProfileIndex")
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    // MARK: - CloudKit Sync Methods
    
    private func syncProfileToCloudKit(_ profile: Profile) {
        // Sync individual profile fields to CloudKit for enhanced persistence
        let profileKey = "memoir_profile_\(profile.id.uuidString)"
        
        // Store profile data
        if let profileData = try? JSONEncoder().encode(profile) {
            NSUbiquitousKeyValueStore.default.set(profileData, forKey: profileKey)
        }
        
        // Store individual fields for easier access
        NSUbiquitousKeyValueStore.default.set(profile.name, forKey: "\(profileKey)_name")
        
        if let birthdate = profile.birthdate {
            NSUbiquitousKeyValueStore.default.set(birthdate, forKey: "\(profileKey)_birthdate")
        }
        
        if let ethnicity = profile.ethnicity {
            NSUbiquitousKeyValueStore.default.set(ethnicity, forKey: "\(profileKey)_ethnicity")
        }
        
        if let gender = profile.gender {
            NSUbiquitousKeyValueStore.default.set(gender, forKey: "\(profileKey)_gender")
        }
        
        if let photoData = profile.photoData {
            NSUbiquitousKeyValueStore.default.set(photoData, forKey: "\(profileKey)_photo")
        }
        
        NSUbiquitousKeyValueStore.default.synchronize()
        print("✅ Profile synced to CloudKit: \(profile.name)")
    }
    
    private func restoreProfileFromCloudKit(_ profileId: UUID) -> Profile? {
        let profileKey = "memoir_profile_\(profileId.uuidString)"
        
        // Try to restore full profile data first
        if let profileData = NSUbiquitousKeyValueStore.default.data(forKey: profileKey),
           let profile = try? JSONDecoder().decode(Profile.self, from: profileData) {
            return profile
        }
        
        // Fallback to restoring individual fields
        let name = NSUbiquitousKeyValueStore.default.string(forKey: "\(profileKey)_name") ?? "Restored Profile"
        let birthdate = NSUbiquitousKeyValueStore.default.object(forKey: "\(profileKey)_birthdate") as? Date
        let ethnicity = NSUbiquitousKeyValueStore.default.string(forKey: "\(profileKey)_ethnicity")
        let gender = NSUbiquitousKeyValueStore.default.string(forKey: "\(profileKey)_gender")
        let photoData = NSUbiquitousKeyValueStore.default.data(forKey: "\(profileKey)_photo")
        
        return Profile(
            id: profileId,
            name: name,
            photoData: photoData,
            birthdate: birthdate,
            ethnicity: ethnicity,
            gender: gender
        )
    }
}
