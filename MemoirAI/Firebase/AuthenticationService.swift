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

/// Observable service for managing user authentication state
@MainActor
final class AuthenticationService: ObservableObject {
    
    static let shared = AuthenticationService()
    
    @Published var user: User?
    @Published var isSignedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // For Apple Sign In nonce
    private var currentNonce: String?
    
    private init() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isSignedIn = user != nil
                
                if let user = user {
                    print("✅ Auth state changed: signed in as \(user.email ?? user.uid)")
                    // Ensure user document exists in Firestore
                    await self?.createOrUpdateUserDocument()
                } else {
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
    
    /// Handle Apple Sign In credential
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let nonce = currentNonce else {
            throw AuthError.missingNonce
        }
        
        guard let appleIDToken = credential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }
        
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        
        do {
            let result = try await Auth.auth().signIn(with: firebaseCredential)
            print("✅ Signed in with Apple: \(result.user.uid)")
            
            // Save display name if provided (only available on first sign in)
            if let fullName = credential.fullName,
               let givenName = fullName.givenName {
                let displayName = [givenName, fullName.familyName].compactMap { $0 }.joined(separator: " ")
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Sign In with Google
    
    func signInWithGoogle() async throws {
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
            
            let authResult = try await Auth.auth().signIn(with: credential)
            print("✅ Signed in with Google: \(authResult.user.uid)")
            
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Anonymous Sign In
    
    /// Sign in anonymously - call this on app launch for automatic Firebase sync
    func signInAnonymouslyIfNeeded() async {
        // Already signed in (anonymous or with provider)
        if Auth.auth().currentUser != nil {
            print("✅ Already signed in: \(Auth.auth().currentUser?.uid ?? "unknown")")
            return
        }
        
        do {
            let result = try await Auth.auth().signInAnonymously()
            print("✅ Signed in anonymously: \(result.user.uid)")
        } catch {
            print("❌ Anonymous sign-in failed: \(error.localizedDescription)")
        }
    }
    
    /// Check if current user is anonymous (not linked to Google)
    var isAnonymous: Bool {
        Auth.auth().currentUser?.isAnonymous ?? true
    }
    
    // MARK: - Link Google Account (upgrade from anonymous)
    
    /// Link Google account to current anonymous user
    func linkGoogleAccount() async throws {
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
            
            // Link credential to current anonymous user
            if let currentUser = Auth.auth().currentUser, currentUser.isAnonymous {
                try await currentUser.link(with: credential)
                print("✅ Linked Google account to anonymous user")
            } else {
                // If not anonymous, just sign in
                try await Auth.auth().signIn(with: credential)
                print("✅ Signed in with Google")
            }
            
        } catch {
            // If linking fails (e.g., account already exists), try signing in instead
            if (error as NSError).code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                errorMessage = "This Google account is already linked to another user."
            } else {
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() throws {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
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
    
    // MARK: - User Document Management
    
    private func createOrUpdateUserDocument() async {
        guard let user = Auth.auth().currentUser else { return }
        
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)
        
        do {
            let doc = try await userRef.getDocument()
            
            if doc.exists {
                // Update last active time
                try await userRef.updateData([
                    "lastActiveAt": FieldValue.serverTimestamp()
                ])
            } else {
                // Create new user document
                let userData: [String: Any] = [
                    "email": user.email ?? "",
                    "displayName": user.displayName ?? "",
                    "authProvider": getAuthProvider(user),
                    "createdAt": FieldValue.serverTimestamp(),
                    "lastActiveAt": FieldValue.serverTimestamp(),
                    "profilePhotoURL": user.photoURL?.absoluteString ?? ""
                ]
                try await userRef.setData(userData)
                print("✅ Created user document for \(user.uid)")
            }
        } catch {
            print("❌ Error managing user document: \(error)")
        }
    }
    
    private func getAuthProvider(_ user: User) -> String {
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
