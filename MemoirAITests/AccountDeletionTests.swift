import CoreData
import Foundation
import Testing
import FirebaseFunctions
@testable import MemoirAI

struct AccountDeletionTests {
    private struct CleanupFailure: Error {}

    @Test func accountSwitchContentDetectorStopsAfterLocalContent() async throws {
        var queriedCollections: [String] = []
        let hasContent = try await AccountSwitchContentPolicy.hasContent(
            localMemoryCount: { 1 },
            remoteCollectionHasDocuments: { collection in
                queriedCollections.append(collection)
                return false
            }
        )

        #expect(hasContent)
        #expect(queriedCollections.isEmpty)
    }

    @Test func accountSwitchContentDetectorStopsAtFirstRemoteContent() async throws {
        var queriedCollections: [String] = []
        let hasContent = try await AccountSwitchContentPolicy.hasContent(
            localMemoryCount: { 0 },
            remoteCollectionHasDocuments: { collection in
                queriedCollections.append(collection)
                return collection == "orders"
            }
        )

        #expect(hasContent)
        #expect(queriedCollections == ["memories", "profiles", "bookVersions", "storybookJobs", "orders"])
    }

    @Test func localCleanupCoordinator_retriesUntilEveryStageSucceeds() async throws {
        let suiteName = "AccountCleanupCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var cacheClears = 0
        let failed = await AccountLocalCleanupCoordinator.run(
            firebaseUserID: "user-a",
            defaults: defaults,
            clearPersistence: { throw CleanupFailure() },
            clearFiles: { _ in },
            clearCaches: { cacheClears += 1 }
        )
        #expect(!failed)
        #expect(defaults.bool(forKey: AccountLocalCleanupCoordinator.pendingKey))
        #expect(cacheClears == 1)

        let succeeded = await AccountLocalCleanupCoordinator.run(
            firebaseUserID: "user-a",
            defaults: defaults,
            clearPersistence: { .empty },
            clearFiles: { _ in },
            clearCaches: { cacheClears += 1 }
        )
        #expect(succeeded)
        #expect(defaults.object(forKey: AccountLocalCleanupCoordinator.pendingKey) == nil)
        #expect(cacheClears == 2)
    }

    @MainActor
    @Test func deletionErrorPolicy_distinguishesActiveCheckoutFromRecentLogin() {
        let checkoutError = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            userInfo: [FunctionsErrorDetailsKey: ["reason": "active-checkout"]]
        )
        let mappedCheckout = AuthenticationService.mapAccountDeletionError(checkoutError)
        #expect(mappedCheckout.localizedDescription.contains("checkout"))

        let storybookError = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            userInfo: [FunctionsErrorDetailsKey: ["reason": "active-storybook"]]
        )
        let mappedStorybook = AuthenticationService.mapAccountDeletionError(storybookError)
        #expect(mappedStorybook.localizedDescription.contains("storybook"))

        let recentLoginError = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue
        )
        let mappedLogin = AuthenticationService.mapAccountDeletionError(recentLoginError)
        #expect(mappedLogin.localizedDescription.contains("sign in again"))
    }

    @Test func cloudProfilePolicy_blocksAllProfileResurrectionKeys() {
        #expect(AccountCloudDataPolicy.shouldRemoveProfileKey(
            "memoir_profiles_backup_user-a",
            userID: "user-a"
        ))
        #expect(AccountCloudDataPolicy.shouldRemoveProfileKey(
            "memoir_selectedProfileIndex_user-a",
            userID: "user-a"
        ))
        #expect(!AccountCloudDataPolicy.shouldRemoveProfileKey(
            "memoir_profile_user-b_123_photo",
            userID: "user-a"
        ))
        #expect(!AccountCloudDataPolicy.shouldRemoveProfileKey(
            "unrelated_preference",
            userID: "user-a"
        ))
        #expect(AccountCloudDataPolicy.allowsProfileWrite(deletionBarrierActive: false))
        #expect(!AccountCloudDataPolicy.allowsProfileWrite(deletionBarrierActive: true))
    }

    @Test func revenueCatIdentityPolicy_linksOnlyWhenFirebaseIdentityChanges() {
        #expect(RevenueCatIdentityPolicy.shouldIdentify(
            currentAppUserID: "device-anonymous",
            firebaseUserID: "firebase-user"
        ))
        #expect(!RevenueCatIdentityPolicy.shouldIdentify(
            currentAppUserID: "firebase-user",
            firebaseUserID: "firebase-user"
        ))
        #expect(!RevenueCatIdentityPolicy.shouldIdentify(
            currentAppUserID: "device-anonymous",
            firebaseUserID: ""
        ))
    }

    @Test func localDefaultsPolicy_removesUserContentButPreservesBillingIdentity() throws {
        let suiteName = "AccountDeletionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("profile", forKey: "characterDetails_123")
        defaults.set(true, forKey: "hasCompletedOnboarding_local")
        defaults.set("revenue-cat-id", forKey: "memoirai_rc_user_id")
        defaults.set(4, forKey: "memoirai_free_preview_count")
        defaults.set("private address", forKey: "order_last_shipping_user-1")
        defaults.set("checkout", forKey: CheckoutReturnPolicy.pendingSessionDefaultsKey)
        defaults.set(1, forKey: "memoirai_cloud_transcription_disclosure_version")
        defaults.set("family", forKey: "current_family_group")

        let memoryID = UUID()
        defaults.set("private", forKey: "characterDetails_\(memoryID.uuidString)")
        defaults.set("other", forKey: "memoirai_image_allowance_user-2_$rc_monthly")
        AccountLocalDataCleaner.clearUserDefaults(
            firebaseUserID: "user-1",
            manifest: AccountLocalCleanupManifest(
                localFileURLs: [],
                memoryIDs: [memoryID],
                profileIDs: []
            ),
            defaults: defaults
        )

        #expect(defaults.string(forKey: "characterDetails_123") == "profile")
        #expect(defaults.object(forKey: "hasCompletedOnboarding_local") == nil)
        #expect(defaults.string(forKey: "memoirai_rc_user_id") == "revenue-cat-id")
        #expect(defaults.integer(forKey: "memoirai_free_preview_count") == 4)
        #expect(defaults.object(forKey: "order_last_shipping_user-1") == nil)
        #expect(defaults.object(forKey: CheckoutReturnPolicy.pendingSessionDefaultsKey) == nil)
        #expect(defaults.object(forKey: "memoirai_cloud_transcription_disclosure_version") == nil)
        #expect(defaults.object(forKey: "current_family_group") == nil)
        #expect(defaults.object(forKey: "characterDetails_\(memoryID.uuidString)") == nil)
        #expect(defaults.string(forKey: "memoirai_image_allowance_user-2_$rc_monthly") == "other")
    }

    @Test func persistenceDeletion_removesOnlyTheRequestedUser() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext

        let memory = MemoryEntry(context: context)
        memory.id = UUID()
        memory.text = "private memory"
        memory.firebaseUserId = "user-a"
        memory.profileID = UUID()

        let otherMemory = MemoryEntry(context: context)
        otherMemory.id = UUID()
        otherMemory.text = "other memory"
        otherMemory.firebaseUserId = "user-b"
        otherMemory.profileID = UUID()

        let photo = Photo(context: context)
        photo.id = UUID()
        photo.data = Data([1, 2, 3])
        photo.memoryEntry = memory

        let character = GlobalCharacter(context: context)
        character.id = UUID()
        character.canonicalName = "Private name"
        character.profileID = memory.profileID
        let otherCharacter = GlobalCharacter(context: context)
        otherCharacter.id = UUID()
        otherCharacter.canonicalName = "Other private name"
        otherCharacter.profileID = otherMemory.profileID
        try context.save()

        _ = try await persistence.deleteUserData(firebaseUserId: "user-a")

        let memoryRequest = NSFetchRequest<NSManagedObject>(entityName: "MemoryEntry")
        #expect(try context.count(for: memoryRequest) == 1)
        let photoRequest = NSFetchRequest<NSManagedObject>(entityName: "Photo")
        #expect(try context.count(for: photoRequest) == 0)
        let characterRequest = NSFetchRequest<NSManagedObject>(entityName: "GlobalCharacter")
        #expect(try context.count(for: characterRequest) == 1)
    }
}
