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
        fileManager: FileManager = .default
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
            completed = false
            print("Account deletion: Core Data cleanup failed: \(error.localizedDescription)")
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

/// Observable service for managing user authentication state
@MainActor
final class AuthenticationService: ObservableObject {
    
    static let shared = AuthenticationService()
    
    @Published var user: User?
    @Published var isSignedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published private(set) var isDeletingAccount: Bool = false
    @Published var errorMessage: String?
    
    // For Apple Sign In nonce
    private var currentNonce: String?
    
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
                        try await PersistenceController.shared.deleteUserData(
                            firebaseUserId: firebaseUserID
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
                    await self?.signInAnonymouslyIfNeeded()
                }
            }
        }

        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isSignedIn = user != nil
                
                if let user = user {
                    print("Auth state changed: signed in")
                    if !user.isAnonymous {
                        UserDefaults.standard.removeObject(forKey: MemoirPersistenceUserDefaults.suggestAccountLinkAfterBook)
                    }
                    await RCSubscriptionManager.shared.identify(firebaseUserID: user.uid)
                    // Ensure user document exists in Firestore
                    await self?.createOrUpdateUserDocument()
                } else {
                    RCSubscriptionManager.shared.clearIdentityState()
                    print("ℹ️ Auth state changed: signed out")
                }
            }
        }
    }
    
    // MARK: - Sign In with Apple
    
    /// Generate a random nonce for Apple Sign In
    func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
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
    func prepareAppleSignIn() -> String {
        let nonce = randomNonceString()
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
    
    /// Check if current user is anonymous (not linked to Google)
    var isAnonymous: Bool {
        Auth.auth().currentUser?.isAnonymous ?? true
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

    /// Links `credential` to the current anonymous user. If the credential already belongs to
    /// a different existing account (`credentialAlreadyInUse`), signs into that existing
    /// account instead using the updated credential Firebase supplies, so a returning user on
    /// a reinstall lands back in their real account instead of hitting a dead-end error.
    private func linkOrSignIn(with credential: AuthCredential) async throws -> AccountLinkOutcome {
        // Guarantee an anonymous session exists before deciding link-vs-sign-in. Without this,
        // a caller invoked before `signInAnonymouslyIfNeeded()` finishes (e.g. a very fast tap
        // on the first-launch welcome screen) would see `currentUser == nil`, fall through to
        // the "not anonymous" branch below, and mislabel a brand-new account as returning.
        if Auth.auth().currentUser == nil {
            await signInAnonymouslyIfNeeded()
        }

        guard let currentUser = Auth.auth().currentUser, currentUser.isAnonymous else {
            _ = try await Auth.auth().signIn(with: credential)
            return .signedInExistingAccount
        }

        do {
            try await currentUser.link(with: credential)
            return .linkedNewAccount
        } catch {
            let nsError = error as NSError
            if nsError.code == AuthErrorCode.credentialAlreadyInUse.rawValue,
               let updatedCredential = nsError.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential {
                guard try await canReplaceAnonymousAccount(currentUser) else {
                    throw AuthError.accountMergeRequired
                }
                _ = try await Auth.auth().signIn(with: updatedCredential)
                return .signedInExistingAccount
            }
            throw error
        }
    }

    /// Link Sign in with Apple to the current anonymous user (keeps `users/{uid}` data on reinstall when using the same Apple ID).
    /// Returns `.signedInExistingAccount` when this Apple ID already had an account elsewhere.
    @discardableResult
    func linkAppleAccount(credential: ASAuthorizationAppleIDCredential) async throws -> AccountLinkOutcome {
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
            outcome = try await linkOrSignIn(with: firebaseCredential)
            print(outcome == .linkedNewAccount ? "✅ Linked Apple account to anonymous user" : "✅ Signed in with Apple (existing account)")
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

        return outcome
    }

    /// Link Google account to current anonymous user. Returns `.signedInExistingAccount`
    /// when this Google account already had an account elsewhere.
    @discardableResult
    func linkGoogleAccount() async throws -> AccountLinkOutcome {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.noRootViewController
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.invalidCredential
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            let outcome = try await linkOrSignIn(with: credential)
            print(outcome == .linkedNewAccount ? "✅ Linked Google account to anonymous user" : "✅ Signed in with Google (existing account)")
            return outcome
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
        guard Self.isValidEmail(email) else { throw AuthError.invalidEmail }
        guard Self.isValidPassword(password) else { throw AuthError.weakPassword }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let credential = EmailAuthProvider.credential(withEmail: email, password: password)

        do {
            if let currentUser = Auth.auth().currentUser, currentUser.isAnonymous {
                try await currentUser.link(with: credential)
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
    }

    /// Signs in an existing email/password account. This never links — if the current session
    /// is anonymous it is replaced by the authenticated user (matching Firebase's default
    /// `signIn` behavior), which is correct for a returning user reclaiming their real account.
    func signInWithEmail(email: String, password: String) async throws {
        guard Self.isValidEmail(email) else { throw AuthError.invalidEmail }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let currentUser = Auth.auth().currentUser, currentUser.isAnonymous {
                guard try await canReplaceAnonymousAccount(currentUser) else {
                    throw AuthError.accountMergeRequired
                }
            }
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
            print("Signed in with email")
        } catch {
            let mapped = Self.mapEmailAuthError(error)
            errorMessage = mapped.errorDescription
            throw mapped
        }
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

            // Arm the cross-device barrier before any throwable local cleanup. A stale
            // device must not be able to restore profile or onboarding KVS payloads.
            iCloudManager.shared.resetAfterAccountDeletion(userID: user.uid)
            let localCleanupComplete = await AccountLocalCleanupCoordinator.run(
                firebaseUserID: user.uid,
                clearPersistence: {
                    try await PersistenceController.shared.deleteUserData(
                        firebaseUserId: user.uid
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
    
    func signOut() throws {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            clearLocalCaches()
            print("✅ Signed out successfully")
            
            // Sign back in anonymously so data keeps syncing
            Task {
                await signInAnonymouslyIfNeeded()
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
                if let name = profileName, !name.isEmpty {
                    update["profileName"] = name
                }
                try await userRef.updateData(update)
            } else {
                var userData: [String: Any] = [
                    "email": user.email ?? "",
                    "displayName": user.displayName ?? "",
                    "authProvider": getAuthProvider(user),
                    "isAnonymous": user.isAnonymous,
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
        if user.isAnonymous { return "anonymous" }
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
            case .underlying(let message):
                return message
            }
        }
    }
}

// MARK: - Apple Sign In Coordinator

class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    var onCompletion: ((Result<ASAuthorizationAppleIDCredential, Error>) -> Void)?
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available")
        }
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
