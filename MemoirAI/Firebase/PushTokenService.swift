import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Persists the FCM registration token on the signed-in user's doc so Cloud Functions
/// can push them (family access requests). Tokens can arrive before Firebase Auth has
/// restored the session, so the latest token is held and flushed on every auth change.
final class PushTokenService {
    static let shared = PushTokenService()

    private var latestToken: String?
    private var authListener: AuthStateDidChangeListenerHandle?

    private init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard user != nil else { return }
            self?.flush()
        }
    }

    func updateToken(_ token: String?) {
        let trimmed = (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        latestToken = trimmed
        flush()
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
