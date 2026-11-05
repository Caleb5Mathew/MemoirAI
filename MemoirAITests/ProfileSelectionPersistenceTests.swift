import Foundation
import Testing
@testable import MemoirAI

@MainActor
struct ProfileSelectionPersistenceTests {
    @MainActor
    private struct Fixture {
        let defaults: UserDefaults
        let suite: String
        let directory: URL
        let userID = "profile-test-" + UUID().uuidString

        init() throws {
            suite = "ProfileSelectionTests." + UUID().uuidString
            defaults = try #require(UserDefaults(suiteName: suite))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func store(_ profiles: [Profile], userID: String? = nil) throws {
            let url = directory.appendingPathComponent(ProfileStorageScope.fileName(userID: userID ?? self.userID))
            try JSONEncoder().encode(profiles).write(to: url, options: .atomic)
        }

        func model() -> ProfileViewModel {
            ProfileViewModel(selectionDefaults: defaults, selectionCloudStore: nil, profilesDirectory: directory)
        }

        func clean() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func coldActivationDoesNotOverwriteSavedSelection() throws {
        let f = try Fixture(); defer { f.clean() }
        let a = Profile(name: "First"), b = Profile(name: "Second")
        try f.store([a, b])
        f.defaults.set(b.id.uuidString, forKey: ProfileStorageScope.selectedIDKey(userID: f.userID))
        f.defaults.set(1, forKey: ProfileStorageScope.selectedIndexKey(userID: f.userID))
        let model = f.model()
        model.beginUserActivation(f.userID)
        #expect(model.selectedProfile.id == b.id)
        #expect(f.defaults.integer(forKey: ProfileStorageScope.selectedIndexKey(userID: f.userID)) == 1)
        #expect(f.defaults.string(forKey: ProfileStorageScope.selectedIDKey(userID: f.userID)) == b.id.uuidString)
        #expect(model.isLoadingProfiles)
        #expect(model.hasReadyProfile)
    }

    @Test func switchThenNewModelRestoresTheSamePerson() throws {
        let f = try Fixture(); defer { f.clean() }
        let a = Profile(name: "First"), b = Profile(name: "Second")
        try f.store([a, b])
        let first = f.model()
        first.beginUserActivation(f.userID)
        first.selectedProfileIndex = 1
        let reopened = f.model()
        reopened.beginUserActivation(f.userID)
        #expect(reopened.selectedProfile.id == b.id)
    }

    @Test func localZeroIsAnIntentionalSelectionNotMissingStorage() {
        let cloudID = UUID()
        #expect(ProfileSelectionPreference.restored(localID: nil, localIndex: 0,
                                                   cloudID: cloudID.uuidString, cloudIndex: 1) == .legacyIndex(0))
        #expect(ProfileSelectionPreference.restored(localID: nil, localIndex: nil,
                                                   cloudID: cloudID.uuidString, cloudIndex: 1) == .profile(cloudID))
    }

    @Test func legacyIndexBecomesIdentityBeforeCloudReordersProfiles() throws {
        let f = try Fixture(); defer { f.clean() }
        let a = Profile(name: "First", createdAt: Date(timeIntervalSince1970: 20))
        let b = Profile(name: "Second", createdAt: Date(timeIntervalSince1970: 10))
        try f.store([a, b])
        f.defaults.set(1, forKey: ProfileStorageScope.selectedIndexKey(userID: f.userID))
        let model = f.model(); model.beginUserActivation(f.userID)
        model.applyHydratedProfiles([b, a], deletedIDs: [], userID: f.userID)
        #expect(model.selectedProfile.id == b.id)
        #expect(model.selectedProfileIndex == 0)
    }

    @Test func selectionMadeDuringHydrationWinsOverInitialSelection() throws {
        let f = try Fixture(); defer { f.clean() }
        let a = Profile(name: "First"), b = Profile(name: "Second")
        try f.store([a, b])
        f.defaults.set(a.id.uuidString, forKey: ProfileStorageScope.selectedIDKey(userID: f.userID))
        let model = f.model(); model.beginUserActivation(f.userID)
        model.selectedProfileIndex = 1
        model.applyHydratedProfiles([a, b], deletedIDs: [], userID: f.userID)
        #expect(model.selectedProfile.id == b.id)
    }

    @Test func remoteOnlySelectionSurvivesUntilHydrationReturns() throws {
        let f = try Fixture(); defer { f.clean() }
        let a = Profile(name: "Cached"), b = Profile(name: "Remote")
        try f.store([a])
        f.defaults.set(b.id.uuidString, forKey: ProfileStorageScope.selectedIDKey(userID: f.userID))
        let model = f.model(); model.beginUserActivation(f.userID)
        #expect(model.selectedProfile.id == a.id)
        #expect(!model.hasReadyProfile)
        model.applyHydratedProfiles([b], deletedIDs: [], userID: f.userID)
        #expect(model.selectedProfile.id == b.id)
        #expect(model.hasReadyProfile)
    }

    @Test func failedHydrationPreservesRemoteSelectionAcrossFallbackAndRelaunch() throws {
        let f = try Fixture(); defer { f.clean() }
        let cached = Profile(name: "Cached"), remote = Profile(name: "Remote")
        try f.store([cached])
        f.defaults.set(remote.id.uuidString, forKey: ProfileStorageScope.selectedIDKey(userID: f.userID))
        let model = f.model()
        model.beginUserActivation(f.userID)
        model.finishProfileSelectionRecovery(recovered: false)
        #expect(model.hasReadyProfile)
        #expect(model.selectedProfile.id == cached.id)
        #expect(model.profileLoadError != nil)
        #expect(f.defaults.string(forKey: ProfileStorageScope.selectedIDKey(userID: f.userID)) == remote.id.uuidString)
        let relaunched = f.model()
        relaunched.beginUserActivation(f.userID)
        relaunched.applyHydratedProfiles([remote], deletedIDs: [], userID: f.userID)
        relaunched.finishProfileSelectionRecovery(recovered: true)
        #expect(relaunched.selectedProfile.id == remote.id)
        #expect(relaunched.profileLoadError == nil)
    }

    @Test func explicitSelectionAfterFailedHydrationReplacesUnresolvedPreference() throws {
        let f = try Fixture(); defer { f.clean() }
        let cached = Profile(name: "Cached")
        try f.store([cached])
        f.defaults.set(UUID().uuidString, forKey: ProfileStorageScope.selectedIDKey(userID: f.userID))
        let model = f.model(); model.beginUserActivation(f.userID)
        model.finishProfileSelectionRecovery(recovered: false)
        model.selectedProfileIndex = 0
        #expect(f.defaults.string(forKey: ProfileStorageScope.selectedIDKey(userID: f.userID)) == cached.id.uuidString)
    }

    @Test func readingAnEmptyLoadingModelDoesNotCreateOrSaveAProfile() throws {
        let f = try Fixture(); defer { f.clean() }
        try f.store([])
        let model = f.model(); model.beginUserActivation(f.userID)
        let first = model.selectedProfile.id
        #expect(model.selectedProfile.id == first)
        #expect(model.profiles.isEmpty)
        #expect(!model.hasReadyProfile)
        #expect(f.defaults.object(forKey: ProfileStorageScope.selectedIDKey(userID: f.userID)) == nil)
        let remote = Profile(name: "Recovered")
        model.applyHydratedProfiles([remote], deletedIDs: [], userID: f.userID)
        #expect(model.profiles.map(\.id) == [remote.id])
    }

    @Test func deletedSelectionFallsBackWithoutResurrectingDeletedProfile() throws {
        let f = try Fixture(); defer { f.clean() }
        let a = Profile(name: "Keep"), b = Profile(name: "Deleted")
        try f.store([a, b])
        f.defaults.set(b.id.uuidString, forKey: ProfileStorageScope.selectedIDKey(userID: f.userID))
        let model = f.model(); model.beginUserActivation(f.userID)
        model.applyHydratedProfiles([a, b], deletedIDs: [b.id], userID: f.userID)
        #expect(model.selectedProfile.id == a.id)
        #expect(model.profiles.count == 1)
    }

    @Test func accountSwitchRejectsOldHydrationAndKeepsSeparateSelections() throws {
        let f = try Fixture(); defer { f.clean() }
        let a = Profile(name: "Account A"), b = Profile(name: "Account A second"), c = Profile(name: "Account B")
        let other = "other-" + UUID().uuidString
        try f.store([a, b]); try f.store([c], userID: other)
        let model = f.model(); model.beginUserActivation(f.userID); model.selectedProfileIndex = 1
        model.beginUserActivation(other)
        #expect(!model.applyHydratedProfiles([a, b], deletedIDs: [], userID: f.userID))
        #expect(model.selectedProfile.id == c.id)
        model.beginUserActivation(f.userID)
        #expect(model.selectedProfile.id == b.id)
    }

    @Test func newSelectionKeysAreRemovedOnlyForTheirAccount() {
        let local = ProfileStorageScope.selectedIDKey(userID: "account-a")
        let cloud = ProfileStorageScope.cloudSelectedIDKey(userID: "account-a")
        #expect(AccountLocalDataPolicy.shouldRemoveUserDefaultsKey(local, firebaseUserID: "account-a"))
        #expect(!AccountLocalDataPolicy.shouldRemoveUserDefaultsKey(local, firebaseUserID: "account-b"))
        #expect(AccountCloudDataPolicy.shouldRemoveProfileKey(cloud, userID: "account-a"))
        #expect(!AccountCloudDataPolicy.shouldRemoveProfileKey(cloud, userID: "account-b"))
    }
}
