//
//  AuthenticationService.swift
//  MemoirAI
//
//  Handles Firebase Authentication with Apple and Google Sign-In
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
import GoogleSignIn
import FirebaseCore
import FirebaseFunctions
import RevenueCat
import CoreData

enum AccountLocalDataPolicy {
    private static let exactKeys: Set<String> = [
        "hasCompletedOnboarding",
        "hasCompletedOnboarding_local",
        "profiles",
        "selectedProfileIndex",
        "ordersLastViewedAt",
        "pendingStripeReturnSessionId",
        "memoirai_cloud_transcription_disclosure_version",
        "memoirai.storybookCompletedJobsSeen",
        "current_family_group",
        "family_members",
        "shared_stories",
        "guidedTutorial_lastProfileUUID",
        "memoirai_pending_syncs",
        "memoirai_pending_memory_syncs",
        "memoirai_pending_memory_deletions",
        "memoirai_renewal_date",
        "order_last_shipping"
    ]

    static func shouldRemoveUserDefaultsKey(
        _ key: String,
        firebaseUserID: String,
        memoryIDs: Set<UUID> = [],
        profileIDs: Set<UUID> = []
    ) -> Bool {
        if exactKeys.contains(key) { return true }
        if key.contains(firebaseUserID) { return true }
        if memoryIDs.contains(where: { key.hasSuffix($0.uuidString) }) { return true }
        if profileIDs.contains(where: { key.contains($0.uuidString) }) { return true }
        return false
    }
}

enum AccountLocalDataCleaner {
    static func profileIDs(fromProfileData data: Data) -> Set<UUID> {
        guard let profiles = try? JSONDecoder().decode([Profile].self, from: data) else { return [] }
        return Set(profiles.map(\.id))
    }

    static func storedProfileIDs(
        firebaseUserID: String,
        fileManager: FileManager = .default
    ) -> Set<UUID> {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        let url = documents.appendingPathComponent(ProfileStorageScope.fileName(userID: firebaseUserID))
        guard let data = try? Data(contentsOf: url) else { return [] }
        return profileIDs(fromProfileData: data)
    }

    static func clearUserDefaults(
        firebaseUserID: String,
        manifest: AccountLocalCleanupManifest,
        defaults: UserDefaults = .standard
    ) {
        for key in defaults.dictionaryRepresentation().keys
        where AccountLocalDataPolicy.shouldRemoveUserDefaultsKey(
            key,
            firebaseUserID: firebaseUserID,
            memoryIDs: manifest.memoryIDs,
            profileIDs: manifest.profileIDs
        ) {
            defaults.removeObject(forKey: key)
        }
    }

    static func clearUserFiles(
        firebaseUserID: String,
        localFileURLs: [URL],
        fileManager: FileManager = .default,
        onboardingDraftStore: OnboardingDraftStore = OnboardingDraftStore()
    ) throws {
        for url in localFileURLs where url.isFileURL && fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let storybookURL = support
                .appendingPathComponent("StorybookCache", isDirectory: true)
                .appendingPathComponent("users", isDirectory: true)
                .appendingPathComponent(firebaseUserID, isDirectory: true)
            if fileManager.fileExists(atPath: storybookURL.path) {
                try fileManager.removeItem(at: storybookURL)
            }
        }

        try onboardingDraftStore.clear(userID: firebaseUserID)

        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let profileURL = documents.appendingPathComponent(
                ProfileStorageScope.fileName(userID: firebaseUserID)
            )
            if fileManager.fileExists(atPath: profileURL.path) {
                try fileManager.removeItem(at: profileURL)
            }
        }
    }
}

enum AccountLocalCleanupCoordinator {
    static let pendingKey = "memoirai_account_cleanup_pending_v1"
    static let pendingUserIDKey = "memoirai_account_cleanup_pending_uid_v1"
    static let pendingProfileIDsKey = "memoirai_account_cleanup_pending_profiles_v1"

    static func run(
        firebaseUserID: String,
        defaults: UserDefaults = .standard,
        clearPersistence: () async throws -> AccountLocalCleanupManifest,
        clearFiles: (AccountLocalCleanupManifest) throws -> Void,
        clearCaches: () -> Void
    ) async -> Bool {
        defaults.set(true, forKey: pendingKey)
        var completed = true
        var manifest = AccountLocalCleanupManifest.empty
        do {
            manifest = try await clearPersistence()
        } catch {
            print("Account deletion: Core Data cleanup failed: \(error.localizedDescription)")
            return false
        }
        do {
            try clearFiles(manifest)
        } catch {
            completed = false
            print("Account deletion: local file cleanup failed: \(error.localizedDescription)")
        }
        AccountLocalDataCleaner.clearUserDefaults(
            firebaseUserID: firebaseUserID,
            manifest: manifest,
            defaults: defaults
        )
        clearCaches()
        if completed {
            defaults.removeObject(forKey: pendingKey)
            defaults.removeObject(forKey: pendingUserIDKey)
            defaults.removeObject(forKey: pendingProfileIDsKey)
        }
        return completed
    }
}

enum AccountSwitchContentPolicy {
    static let remoteCollections = [
        "memories",
        "profiles",
        "bookVersions",
        "storybookJobs",
        "orders",
        "pendingCartCheckouts"
    ]

    static func hasContent(
        localMemoryCount: () throws -> Int,
        remoteCollectionHasDocuments: (String) async throws -> Bool
    ) async throws -> Bool {
        if try localMemoryCount() > 0 { return true }
        for collection in remoteCollections {
            if try await remoteCollectionHasDocuments(collection) { return true }
        }
        return false
    }
}

enum LinkedAccountPolicy {
    static let supportedProviderIDs: Set<String> = ["apple.com", "google.com", "password"]

    static func shouldLinkCurrentUser(isGuest: Bool, preserveCurrentAccount: Bool) -> Bool {
        isGuest || preserveCurrentAccount
    }

    static func canDisconnect(providerID: String, linkedProviderIDs: [String]) -> Bool {
        let supported = Set(linkedProviderIDs).intersection(supportedProviderIDs)
        return supported.contains(providerID) && supported.subtracting([providerID]).isEmpty == false
    }
}

enum GuestSessionPolicy {
    static func isGuest(
        isNativeAnonymous: Bool,
        hasMemoirGuestClaim: Bool = false
    ) -> Bool {
        isNativeAnonymous || hasMemoirGuestClaim
    }
}

enum GuestRecoveryFailurePolicy {
    static func shouldReplaceSavedSecret(
        error: NSError,
        isNativeAnonymous: Bool
    ) -> Bool {
        isNativeAnonymous
            && error.domain == FunctionsErrorDomain
            && error.code == FunctionsErrorCode.notFound.rawValue
    }
}

/// Observable service for managing user authentication state
@MainActor
final class AuthenticationService: ObservableObject {
    
    static let shared = AuthenticationService()
    
    @Published var user: User?
    @Published var isSignedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published private(set) var isDeletingAccount: Bool = false
    @Published private(set) var recoveredGuestUserID: String?
    @Published private(set) var isSessionPrepared = false
    @Published var errorMessage: String?
    
    // For Apple Sign In nonce
    private var currentNonce: String?
    private var sessionPreparationTask: Task<Bool, Never>?
    
    private init() {
        if UserDefaults.standard.bool(forKey: AccountLocalCleanupCoordinator.pendingKey) {
            Task { [weak self] in
                guard let firebaseUserID = UserDefaults.standard.string(
                    forKey: AccountLocalCleanupCoordinator.pendingUserIDKey
                ) ?? Auth.auth().currentUser?.uid else {
                    print("Account cleanup pending without an owner UID; anonymous sign-in remains paused")
                    return
                }
                let completed = await AccountLocalCleanupCoordinator.run(
                    firebaseUserID: firebaseUserID,
                    clearPersistence: {
                        let persistedProfileIDs = Set(
                            (UserDefaults.standard.stringArray(
                                forKey: AccountLocalCleanupCoordinator.pendingProfileIDsKey
                            ) ?? []).compactMap(UUID.init(uuidString:))
                        )
                        return try await PersistenceController.shared.deleteUserData(
                            firebaseUserId: firebaseUserID,
                            knownProfileIDs: AccountLocalDataCleaner.storedProfileIDs(
                                firebaseUserID: firebaseUserID
                            ).union(persistedProfileIDs)
                        )
                    },
                    clearFiles: { manifest in
                        try AccountLocalDataCleaner.clearUserFiles(
                            firebaseUserID: firebaseUserID,
                            localFileURLs: manifest.localFileURLs
                        )
                    },
                    clearCaches: {
                        self?.clearLocalCaches()
                    }
                )
                if completed {
                    await self?.prepareAuthenticatedSessionForLaunch()
                }
            }
        }

        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                let previousUserID = self?.user?.uid
                if previousUserID != user?.uid, self?.sessionPreparationTask == nil {
                    self?.isSessionPrepared = false
                }
                ProductAnalytics.shared.updateIdentity(userID: user?.uid, isGuest: user?.isAnonymous ?? true)
                self?.user = user
                self?.isSignedIn = user != nil
                
                if let user = user {
                    let tokenResult = try? await user.getIDTokenResult()
                    let hasMemoirGuestClaim = tokenResult?.claims["memoirGuest"] as? Bool == true
                    self?.recoveredGuestUserID = hasMemoirGuestClaim ? user.uid : nil
                    guard Auth.auth().currentUser?.uid == user.uid else { return }
                    ProductAnalytics.shared.updateIdentity(
                        userID: user.uid, isGuest: user.isAnonymous || hasMemoirGuestClaim
                    )
                    print("Auth state changed: signed in")
                    if self?.isGuestUser(user) == false {
                        UserDefaults.standard.removeObject(forKey: MemoirPersistenceUserDefaults.suggestAccountLinkAfterBook)
                    }
                    await RCSubscriptionManager.shared.identify(firebaseUserID: user.uid)
                    // Ensure user document exists in Firestore
                    await self?.createOrUpdateUserDocument()
                } else {
                    self?.recoveredGuestUserID = nil
                    RCSubscriptionManager.shared.clearIdentityState()
                    print("ℹ️ Auth state changed: signed out")
                }
            }
        }
    }
    
    // MARK: - Sign In with Apple
    
    /// Generate a random nonce for Apple Sign In
    func randomNonceString(length: Int = 32) -> String? {
        guard length > 0 else { return nil }
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            print("Apple sign-in nonce generation failed with OSStatus \(errorCode)")
            return nil
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }
    
    /// SHA256 hash of input string
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Prepare for Apple Sign In - call before presenting ASAuthorizationController
    func prepareAppleSignIn() -> String? {
        guard let nonce = randomNonceString() else {
            currentNonce = nil
            return nil
        }
        currentNonce = nonce
        return sha256(nonce)
    }
    
    // MARK: - Anonymous Sign In
    
    /// Sign in anonymously - call this on app launch for automatic Firebase sync
    func signInAnonymouslyIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: AccountLocalCleanupCoordinator.pendingKey) else {
            print("Account cleanup pending; anonymous sign-in is paused")
            return
        }
        // Already signed in (anonymous or with provider)
        if Auth.auth().currentUser != nil {
            print("Already signed in")
            return
        }
        
        do {
            _ = try await Auth.auth().signInAnonymously()
            print("Signed in anonymously")
        } catch {
            print("❌ Anonymous sign-in failed: \(error.localizedDescription)")
        }
    }

    /// Resolves a recoverable iCloud guest before any profile or memory store is
    /// activated. Returning `false` keeps the temporary Firebase UID isolated
    /// until recovery can be retried safely.
    @discardableResult
    func prepareAuthenticatedSessionForLaunch() async -> Bool {
        if isSessionPrepared { return true }
        if let sessionPreparationTask {
            return await sessionPreparationTask.value
        }
        let task = Task { @MainActor [weak self] in
            await self?.performSessionPreparation() ?? false
        }
        sessionPreparationTask = task
        let result = await task.value
        sessionPreparationTask = nil
        return result
    }

    private func performSessionPreparation() async -> Bool {
        isSessionPrepared = false
        await signInAnonymouslyIfNeeded()
        guard let initialUser = Auth.auth().currentUser else {
            errorMessage = "Memoir could not connect to your private cloud account. Check your connection and try again."
            return false
        }

        if isGuestUser(initialUser) {
            do {
                switch try await GuestRecoveryCoordinator.shared.recoverCurrentGuestIfAvailable() {
                case .recovered:
                    guard let recoveredUser = Auth.auth().currentUser else {
                        throw GuestRecoveryError.notAuthenticated
                    }
                    await refreshRecoveredGuestClaim(for: recoveredUser)
                case .noSavedSecret:
                    try await GuestRecoveryCoordinator.shared.enrollCurrentGuest()
                case .skippedNonAnonymousAccount:
                    break
                }
            } catch {
                if GuestRecoveryFailurePolicy.shouldReplaceSavedSecret(
                    error: error as NSError,
                    isNativeAnonymous: initialUser.isAnonymous
                ) {
                    do {
                        try GuestRecoveryCoordinator.shared.discardLocalSecret()
                        try await GuestRecoveryCoordinator.shared.enrollCurrentGuest()
                        isSessionPrepared = true
                        return true
                    } catch {
                        print("Guest recovery key replacement failed: \(error.localizedDescription)")
                    }
                }
                errorMessage = "Memoir could not restore your private guest account. Your cloud data is unchanged; check your connection and reopen the app."
                print("Guest account preparation failed: \(error.localizedDescription)")
                return false
            }
        }

        isSessionPrepared = true
        return true
    }

    private func refreshRecoveredGuestClaim(for user: User) async {
        let tokenResult = try? await user.getIDTokenResult(forcingRefresh: true)
        recoveredGuestUserID = tokenResult?.claims["memoirGuest"] as? Bool == true
            ? user.uid
            : nil
    }
    
    /// Check if current user is anonymous (not linked to Google)
    var isAnonymous: Bool {
        guard let user = Auth.auth().currentUser else { return true }
        return isGuestUser(user)
    }

    func isGuestUser(_ user: User) -> Bool {
        GuestSessionPolicy.isGuest(
            isNativeAnonymous: user.isAnonymous,
            hasMemoirGuestClaim: recoveredGuestUserID == user.uid
        )
    }
    
    // MARK: - Link Google Account (upgrade from anonymous)

    /// Result of attempting to attach a credential (Apple, Google, or email/password) to the
    /// current session. Also used by email/password flows (`createEmailAccount` implies
    /// `.linkedNewAccount`, `signInWithEmail` implies `.signedInExistingAccount`) so callers
    /// can decide whether to treat the person as first-time or returning.
    enum AccountLinkOutcome {
        /// A brand-new permanent account now exists for this device (either by linking the
        /// anonymous user or by creating a fresh account). Treat as a first-time user — still
        /// go through onboarding.
        case linkedNewAccount
        /// The credential already belonged to a different, pre-existing account, and this
        /// session switched to sign into that account instead of linking. Treat as a
        /// returning user (their account already has history — safe to skip onboarding).
        case signedInExistingAccount
    }

    /// Account management preserves the current UID, including when a credential conflicts.
    /// Welcome flows may restore an existing account after checking the guest has no content.
    private func linkOrSignIn(
        with credential: AuthCredential,
        preserveCurrentAccount: Bool
    ) async throws -> AccountLinkOutcome {
        guard await prepareAuthenticatedSessionForLaunch() else {
            throw AuthError.guestRecoveryUnavailable
        }
        // Guarantee an anonymous session exists before deciding link-vs-sign-in. Without this,
        // a caller invoked before `signInAnonymouslyIfNeeded()` finishes (e.g. a very fast tap
        // on the first-launch welcome screen) would see `currentUser == nil`, fall through to
        // the "not anonymous" branch below, and mislabel a brand-new account as returning.
        if Auth.auth().currentUser == nil {
            await signInAnonymouslyIfNeeded()
        }

        guard let currentUser = Auth.auth().currentUser else {
            throw AuthError.notSignedIn
        }
        guard LinkedAccountPolicy.shouldLinkCurrentUser(
            isGuest: isGuestUser(currentUser),
            preserveCurrentAccount: preserveCurrentAccount
        ) else {
            _ = try await Auth.auth().signIn(with: credential)
            return .signedInExistingAccount
        }

        let wasGuest = isGuestUser(currentUser)
        do {
            let result = try await currentUser.link(with: credential)
            if wasGuest {
                await retireGuestRecoveryAfterAccountUpgrade()
            }
            user = result.user
            await createOrUpdateUserDocument()
            return .linkedNewAccount
        } catch {
            let nsError = error as NSError
            if preserveCurrentAccount,
               [AuthErrorCode.credentialAlreadyInUse.rawValue,
                AuthErrorCode.accountExistsWithDifferentCredential.rawValue,
                AuthErrorCode.emailAlreadyInUse.rawValue].contains(nsError.code) {
                throw AuthError.providerLinkedToAnotherAccount
            }
            if !preserveCurrentAccount,
               nsError.code == AuthErrorCode.credentialAlreadyInUse.rawValue,
               let updatedCredential = nsError.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential {
                guard try await canReplaceAnonymousAccount(currentUser) else {
                    throw AuthError.accountMergeRequired
                }
                await revokeGuestRecoveryBeforeAccountReplacement()
                _ = try await Auth.auth().signIn(with: updatedCredential)
                return .signedInExistingAccount
            }
            throw error
        }
    }

    /// Links Apple to the current session. Account management must preserve the current account.
    /// Welcome flows may return `.signedInExistingAccount` for a returning user.
    @discardableResult
    func linkAppleAccount(
        credential: ASAuthorizationAppleIDCredential,
        preserveCurrentAccount: Bool = false
    ) async throws -> AccountLinkOutcome {
        ProductAnalytics.shared.track("Authentication Started", ["provider": "apple", "auth_operation": "link_account"])
        var analyticsSucceeded = false
        defer {
            if analyticsSucceeded, let activeUser = Auth.auth().currentUser {
                ProductAnalytics.shared.updateIdentity(userID: activeUser.uid, isGuest: isGuestUser(activeUser))
            }
            ProductAnalytics.shared.track(analyticsSucceeded ? "Authentication Succeeded" : "Authentication Failed", [
                "provider": "apple", "auth_operation": "link_account"
            ])
        }

        guard let nonce = currentNonce else {
            throw AuthError.missingNonce
        }
        guard let appleIDToken = credential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        let outcome: AccountLinkOutcome
        do {
            outcome = try await linkOrSignIn(with: firebaseCredential, preserveCurrentAccount: preserveCurrentAccount)
            print(outcome == .linkedNewAccount ? "Linked Apple account" : "✅ Signed in with Apple (existing account)")
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }

        if let fullName = credential.fullName,
           let givenName = fullName.givenName,
           let user = Auth.auth().currentUser {
            let displayName = [givenName, fullName.familyName].compactMap { $0 }.joined(separator: " ")
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
        }

        analyticsSucceeded = true
        return outcome
    }

    /// Links Google to the current session. Account management must preserve the current account.
    /// Welcome flows may return `.signedInExistingAccount` for a returning user.
    @discardableResult
    func linkGoogleAccount(preserveCurrentAccount: Bool = false) async throws -> AccountLinkOutcome {
        ProductAnalytics.shared.track("Authentication Started", ["provider": "google", "auth_operation": "link_account"])
        var analyticsSucceeded = false
        defer {
            if analyticsSucceeded, let activeUser = Auth.auth().currentUser {
                ProductAnalytics.shared.updateIdentity(userID: activeUser.uid, isGuest: isGuestUser(activeUser))
            }
            ProductAnalytics.shared.track(analyticsSucceeded ? "Authentication Succeeded" : "Authentication Failed", [
                "provider": "google", "auth_operation": "link_account"
            ])
        }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootViewController = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            throw AuthError.noRootViewController
        }
        var presentingViewController = rootViewController
        while let presented = presentingViewController.presentedViewController {
            presentingViewController = presented
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.invalidCredential
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            let outcome = try await linkOrSignIn(with: credential, preserveCurrentAccount: preserveCurrentAccount)
            print(outcome == .linkedNewAccount ? "Linked Google account" : "✅ Signed in with Google (existing account)")
            analyticsSucceeded = true
            return outcome
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Removes a sign-in method only when another supported method can recover this account.
    func disconnectAccount(providerID: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw AuthError.notSignedIn
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await currentUser.reload()
            guard LinkedAccountPolicy.canDisconnect(
                providerID: providerID,
                linkedProviderIDs: currentUser.providerData.map(\.providerID)
            ) else {
                throw AuthError.lastSignInMethod
            }
            user = try await currentUser.unlink(fromProvider: providerID)
            await createOrUpdateUserDocument()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Email / Password Auth

    /// Basic client-side email format check (not exhaustive RFC 5322 validation).
    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    /// Firebase's server-side minimum password length is 6; we require 8 for a stronger baseline.
    static func isValidPassword(_ password: String) -> Bool {
        password.count >= 8
    }

    /// Creates a new email/password account. If the current user is anonymous, links the
    /// credential so existing local/Firestore data is preserved under the same uid. If the
    /// current user is already authenticated with another provider, creates a brand new account.
    func createEmailAccount(email: String, password: String) async throws {
        ProductAnalytics.shared.track("Authentication Started", ["provider": "email", "auth_operation": "create_account"])
        var analyticsSucceeded = false
        defer {
            if analyticsSucceeded, let activeUser = Auth.auth().currentUser {
                ProductAnalytics.shared.updateIdentity(userID: activeUser.uid, isGuest: isGuestUser(activeUser))
            }
            ProductAnalytics.shared.track(analyticsSucceeded ? "Authentication Succeeded" : "Authentication Failed", [
                "provider": "email", "auth_operation": "create_account"
            ])
        }

        guard Self.isValidEmail(email) else { throw AuthError.invalidEmail }
        guard Self.isValidPassword(password) else { throw AuthError.weakPassword }
        guard await prepareAuthenticatedSessionForLaunch() else {
            throw AuthError.guestRecoveryUnavailable
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let credential = EmailAuthProvider.credential(withEmail: email, password: password)

        do {
            if let currentUser = Auth.auth().currentUser, isGuestUser(currentUser) {
                try await currentUser.link(with: credential)
                await retireGuestRecoveryAfterAccountUpgrade()
                print("✅ Linked email/password account to anonymous user")
            } else {
                _ = try await Auth.auth().createUser(withEmail: email, password: password)
                print("✅ Created email/password account")
            }
        } catch {
            let mapped = Self.mapEmailAuthError(error)
            errorMessage = mapped.errorDescription
            throw mapped
        }
        analyticsSucceeded = true
    }

    /// Signs in an existing email/password account. This never links — if the current session
    /// is anonymous it is replaced by the authenticated user (matching Firebase's default
    /// `signIn` behavior), which is correct for a returning user reclaiming their real account.
    func signInWithEmail(email: String, password: String) async throws {
        ProductAnalytics.shared.track("Authentication Started", ["provider": "email", "auth_operation": "sign_in"])
        var analyticsSucceeded = false
        defer {
            if analyticsSucceeded, let activeUser = Auth.auth().currentUser {
                ProductAnalytics.shared.updateIdentity(userID: activeUser.uid, isGuest: isGuestUser(activeUser))
            }
            ProductAnalytics.shared.track(analyticsSucceeded ? "Authentication Succeeded" : "Authentication Failed", [
                "provider": "email", "auth_operation": "sign_in"
            ])
        }

        guard Self.isValidEmail(email) else { throw AuthError.invalidEmail }
        guard await prepareAuthenticatedSessionForLaunch() else {
            throw AuthError.guestRecoveryUnavailable
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let currentUser = Auth.auth().currentUser, isGuestUser(currentUser) {
                guard try await canReplaceAnonymousAccount(currentUser) else {
                    throw AuthError.accountMergeRequired
                }
                await revokeGuestRecoveryBeforeAccountReplacement()
            }
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
            print("Signed in with email")
        } catch {
            let mapped = Self.mapEmailAuthError(error)
            errorMessage = mapped.errorDescription
            throw mapped
        }
        analyticsSucceeded = true
    }

    private func canReplaceAnonymousAccount(_ user: User) async throws -> Bool {
        let userID = user.uid
        let context = PersistenceController.shared.container.viewContext
        let userRef = Firestore.firestore().collection("users").document(userID)
        let hasContent = try await AccountSwitchContentPolicy.hasContent(
            localMemoryCount: {
                let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
                request.predicate = NSPredicate(format: "firebaseUserId == %@", userID)
                request.fetchLimit = 1
                return try context.count(for: request)
            },
            remoteCollectionHasDocuments: { collection in
                let snapshot = try await userRef.collection(collection).limit(to: 1).getDocuments()
                return !snapshot.documents.isEmpty
            }
        )
        return !hasContent
    }

    /// Sends a password reset email. Errors are mapped the same way as sign-in/create.
    func sendPasswordReset(email: String) async throws {
        guard Self.isValidEmail(email) else { throw AuthError.invalidEmail }

        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            print("Sent password reset email")
        } catch {
            let mapped = Self.mapEmailAuthError(error)
            errorMessage = mapped.errorDescription
            throw mapped
        }
    }

    /// Maps Firebase Auth error codes from email/password flows to user-facing `AuthError`s.
    private static func mapEmailAuthError(_ error: Error) -> AuthError {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return .underlying(error.localizedDescription)
        }
        switch code {
        case .emailAlreadyInUse, .credentialAlreadyInUse, .accountExistsWithDifferentCredential:
            return .emailAlreadyInUse
        case .wrongPassword, .invalidCredential:
            return .wrongPassword
        case .userNotFound:
            return .userNotFound
        case .invalidEmail:
            return .invalidEmail
        case .tooManyRequests:
            return .tooManyRequests
        case .weakPassword:
            return .weakPassword
        default:
            return .underlying(error.localizedDescription)
        }
    }

    // MARK: - Delete Account

    /// Deletes the authenticated MemoirAI account through the trusted server, then
    /// clears this device and requests deletion of the CloudKit-backed local replica.
    /// Paid order records and their fulfillment PDFs may be retained.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notSignedIn
        }
        UserDefaults.standard.set(
            user.uid,
            forKey: AccountLocalCleanupCoordinator.pendingUserIDKey
        )

        isLoading = true
        isDeletingAccount = true
        errorMessage = nil
        defer {
            isLoading = false
            isDeletingAccount = false
        }

        do {
            let callable = Functions.functions().httpsCallable("deleteOwnAccount")
            callable.timeoutInterval = 330
            let result = try await callable.call()
            guard let payload = result.data as? [String: Any],
                  payload["status"] as? String == "complete" else {
                throw AuthError.invalidDeletionResponse
            }
            try? GuestRecoveryCoordinator.shared.discardLocalSecret()

            // Arm the cross-device barrier before any throwable local cleanup. A stale
            // device must not be able to restore profile or onboarding KVS payloads.
            let knownProfileIDs = AccountLocalDataCleaner.storedProfileIDs(
                firebaseUserID: user.uid
            )
            UserDefaults.standard.set(
                knownProfileIDs.map(\.uuidString).sorted(),
                forKey: AccountLocalCleanupCoordinator.pendingProfileIDsKey
            )
            iCloudManager.shared.resetAfterAccountDeletion(userID: user.uid)
            let localCleanupComplete = await AccountLocalCleanupCoordinator.run(
                firebaseUserID: user.uid,
                clearPersistence: {
                    try await PersistenceController.shared.deleteUserData(
                        firebaseUserId: user.uid,
                        knownProfileIDs: knownProfileIDs
                    )
                },
                clearFiles: { manifest in
                    try AccountLocalDataCleaner.clearUserFiles(
                        firebaseUserID: user.uid,
                        localFileURLs: manifest.localFileURLs
                    )
                },
                clearCaches: { [weak self] in
                    self?.clearLocalCaches()
                }
            )

            if Purchases.isConfigured {
                do {
                    _ = try await Purchases.shared.logOut()
                } catch {
                    print("Account deletion: RevenueCat logout failed: \(error.localizedDescription)")
                }
            }
            if Auth.auth().currentUser != nil {
                isSessionPrepared = false
                try Auth.auth().signOut()
            }
            guard localCleanupComplete else {
                throw AuthError.localCleanupPending
            }
            print("Deleted account and local user data")
        } catch {
            let mappedError = Self.mapAccountDeletionError(error)
            errorMessage = mappedError.localizedDescription
            throw mappedError
        }

    }

    static func mapAccountDeletionError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain,
           nsError.code == FunctionsErrorCode.failedPrecondition.rawValue {
            if let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
               let reason = details["reason"] as? String {
                if reason == "active-checkout" { return AuthError.activeCheckout }
                if reason == "active-storybook" { return AuthError.activeStorybook }
            }
            return AuthError.requiresRecentLogin
        }
        return error
    }

    // MARK: - Sign Out
    
    func signOut() async throws {
        do {
            await revokeGuestRecoveryBeforeAccountReplacement()
            PushTokenService.shared.unregisterCurrentUser()
            await MainActor.run {
                RCSubscriptionManager.shared.clearDeveloperSessionForAccountChange()
            }
            try Auth.auth().signOut()
            ProductAnalytics.shared.track("Signed Out")
            ProductAnalytics.shared.updateIdentity(userID: nil, isGuest: true)
            GIDSignIn.sharedInstance.signOut()
            clearLocalCaches()
            print("✅ Signed out successfully")
            
            // Sign back in anonymously so data keeps syncing
            isSessionPrepared = false
            Task {
                await prepareAuthenticatedSessionForLaunch()
            }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func clearLocalCaches() {
        PDFThumbnailCache.shared.removeAll()
        PDFThumbnailDiskCache.shared.removeAll()
        IllustrationImageDiskCache.shared.removeAll()
    }

    private func retireGuestRecoveryAfterAccountUpgrade() async {
        do {
            try await GuestRecoveryCoordinator.shared.revokeCurrentGuestRecovery()
        } catch {
            print("Guest recovery revocation after account link failed: \(error.localizedDescription)")
            try? GuestRecoveryCoordinator.shared.discardLocalSecret()
        }
        recoveredGuestUserID = nil
    }

    private func revokeGuestRecoveryBeforeAccountReplacement() async {
        do {
            try await GuestRecoveryCoordinator.shared.revokeCurrentGuestRecovery()
        } catch GuestRecoveryError.notAuthenticated {
            return
        } catch {
            print("Guest recovery revocation before account switch failed: \(error.localizedDescription)")
            try? GuestRecoveryCoordinator.shared.discardLocalSecret()
        }
        recoveredGuestUserID = nil
    }
    
    // MARK: - User Document Management
    
    func createOrUpdateUserDocument(profileName: String? = nil) async {
        guard let user = Auth.auth().currentUser else { return }

        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)

        let deviceFields: [String: Any] = [
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "buildNumber": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            "deviceModel": UIDevice.current.model,
            "osVersion": UIDevice.current.systemVersion,
            "rcUserId": UserDefaults.standard.string(forKey: "memoirai_rc_user_id") ?? ""
        ]

        do {
            let doc = try await userRef.getDocument()

            if doc.exists {
                var update = deviceFields
                update["lastActiveAt"] = FieldValue.serverTimestamp()
                update["isAnonymous"] = isGuestUser(user)
                update["authProvider"] = getAuthProvider(user)
                if let name = profileName, !name.isEmpty {
                    update["profileName"] = name
                }
                try await userRef.updateData(update)
            } else {
                var userData: [String: Any] = [
                    "email": user.email ?? "",
                    "displayName": user.displayName ?? "",
                    "authProvider": getAuthProvider(user),
                    "isAnonymous": isGuestUser(user),
                    "profileName": profileName ?? "",
                    "createdAt": FieldValue.serverTimestamp(),
                    "lastActiveAt": FieldValue.serverTimestamp(),
                    "profilePhotoURL": user.photoURL?.absoluteString ?? ""
                ]
                deviceFields.forEach { userData[$0.key] = $0.value }
                try await userRef.setData(userData)
                print("Created user document")
            }
        } catch {
            print("❌ Error managing user document: \(error)")
        }
    }

    func updateProfileNameInUserDoc(_ name: String) async {
        guard let uid = Auth.auth().currentUser?.uid, !name.isEmpty else { return }
        do {
            try await Firestore.firestore().collection("users").document(uid)
                .setData(["profileName": name], merge: true)
        } catch {
            print("❌ Failed to write profileName to user doc: \(error)")
        }
    }

    private func getAuthProvider(_ user: User) -> String {
        if isGuestUser(user) { return "anonymous" }
        for info in user.providerData {
            switch info.providerID {
            case "apple.com":
                return "apple"
            case "google.com":
                return "google"
            default:
                continue
            }
        }
        return "unknown"
    }
    
    // MARK: - Error Types
    
    enum AuthError: LocalizedError {
        case missingNonce
        case invalidCredential
        case missingClientID
        case noRootViewController
        case notSignedIn
        case invalidEmail
        case weakPassword
        case emailAlreadyInUse
        case wrongPassword
        case userNotFound
        case tooManyRequests
        case requiresRecentLogin
        case activeCheckout
        case activeStorybook
        case accountMergeRequired
        case localCleanupPending
        case invalidDeletionResponse
        case guestRecoveryUnavailable
        case providerLinkedToAnotherAccount
        case lastSignInMethod
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .missingNonce:
                return "Sign in failed. Please try again."
            case .invalidCredential:
                return "Invalid credentials received."
            case .missingClientID:
                return "Google Sign-In is not configured correctly."
            case .noRootViewController:
                return "Unable to present sign-in screen."
            case .notSignedIn:
                return "You're not signed in."
            case .invalidEmail:
                return "That email address doesn't look right."
            case .weakPassword:
                return "Password must be at least 8 characters."
            case .emailAlreadyInUse:
                return "That email already has an account. Sign in instead."
            case .wrongPassword:
                return "Incorrect email or password."
            case .userNotFound:
                return "No account found with that email."
            case .tooManyRequests:
                return "Too many attempts. Please wait a moment and try again."
            case .requiresRecentLogin:
                return "Please sign in again, then retry deleting your account."
            case .activeCheckout:
                return "Finish or cancel your open book checkout before deleting your account."
            case .activeStorybook:
                return "Wait for your storybook to finish before deleting your account."
            case .accountMergeRequired:
                return "This device has memories in its guest account. Create a new login for this guest account before signing in to a different account."
            case .localCleanupPending:
                return "Your online account was deleted, but this device could not finish removing its local data. Keep the app installed and reopen it to retry cleanup."
            case .invalidDeletionResponse:
                return "The deletion service returned an invalid response. Please try again."
            case .providerLinkedToAnotherAccount:
                return "This sign-in is already linked to another Memoir account. Your current account has not changed. Use a different Apple or Google account to connect it here."
            case .lastSignInMethod:
                return "Connect another sign-in method before disconnecting this one so you can still access your memories."
            case .guestRecoveryUnavailable:
                return "Memoir could not restore your private guest account. Check your connection and try again."
            case .underlying(let message):
                return message
            }
        }
    }
}

// MARK: - Apple Sign In Coordinator

class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    var onCompletion: ((Result<ASAuthorizationAppleIDCredential, Error>) -> Void)?
    private var fallbackWindow: UIWindow?
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return window
        }
        let window = UIWindow(frame: UIScreen.main.bounds)
        fallbackWindow = window
        return window
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            onCompletion?(.success(appleIDCredential))
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onCompletion?(.failure(error))
    }
}
