import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

enum PushTokenOwnershipPolicy {
    static func shouldClear(storedToken: String?, localToken: String?) -> Bool {
        let stored = (storedToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let local = (localToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !stored.isEmpty && stored == local
    }
}

/// Persists the FCM registration token on the signed-in user's doc so Cloud Functions
/// can push them (family access requests). Tokens can arrive before Firebase Auth has
/// restored the session, so the latest token is held and flushed on every auth change.
@MainActor
final class PushTokenService {
    static let shared = PushTokenService()
    private static let pendingRotationDefaultsKey = "memoirai_pending_push_token_rotation"

    private var latestToken: String?
    private var authListener: AuthStateDidChangeListenerHandle?

    private init() {
        if UserDefaults.standard.bool(forKey: Self.pendingRotationDefaultsKey) {
            Task { @MainActor [weak self] in
                do {
                    try await Messaging.messaging().deleteToken()
                    self?.latestToken = nil
                    UserDefaults.standard.removeObject(forKey: Self.pendingRotationDefaultsKey)
                } catch {
                    print("[Push] deferred device token rotation failed: \(error.localizedDescription)")
                }
            }
        }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard user != nil else { return }
            self?.flush()
        }
    }

    func updateToken(_ token: String?) {
        let trimmed = (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        latestToken = trimmed
        guard !UserDefaults.standard.bool(forKey: Self.pendingRotationDefaultsKey) else { return }
        flush()
    }

    func unregisterCurrentUser() {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        let capturedToken = latestToken
        UserDefaults.standard.set(true, forKey: Self.pendingRotationDefaultsKey)
        Task { @MainActor in
            if latestToken == capturedToken {
                do {
                    try await Messaging.messaging().deleteToken()
                    if latestToken == capturedToken {
                        latestToken = nil
                    }
                    UserDefaults.standard.removeObject(forKey: Self.pendingRotationDefaultsKey)
                } catch {
                    print("[Push] device token rotation failed: \(error.localizedDescription)")
                }
            }

            let userRef = Firestore.firestore().collection("users").document(uid)
            do {
                try await Firestore.firestore().runTransaction { transaction, errorPointer in
                    do {
                        let snapshot = try transaction.getDocument(userRef)
                        if PushTokenOwnershipPolicy.shouldClear(
                            storedToken: snapshot.data()?["fcmToken"] as? String,
                            localToken: capturedToken
                        ) {
                            transaction.updateData([
                                "fcmToken": FieldValue.delete(),
                                "fcmTokenUpdatedAt": FieldValue.delete()
                            ], forDocument: userRef)
                        }
                        return nil
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                }
            } catch {
                print("[Push] old-account token cleanup deferred: \(error.localizedDescription)")
            }
        }
    }

    private func flush() {
        guard let token = latestToken,
              let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).setData(
            ["fcmToken": token, "fcmTokenUpdatedAt": FieldValue.serverTimestamp()],
            merge: true
        ) { error in
            if let error {
                print("[Push] fcmToken save failed: \(error.localizedDescription)")
            } else {
                print("[Push] fcmToken saved for uid \(uid.prefix(8))…")
            }
        }
    }
}
