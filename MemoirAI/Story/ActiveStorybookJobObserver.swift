import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Single shared listener on `users/{uid}/storybookJobs` for the selected profile’s in-flight cloud job.
/// Used by `GlobalStorybookProgressBanner` so we never attach duplicate listeners (e.g. tab bar + root).
@MainActor
final class ActiveStorybookJobObserver: ObservableObject {
    static let shared = ActiveStorybookJobObserver()

    @Published private(set) var activeJob: FirestoreSyncService.ActiveStorybookCloudJob?

    private var listener: ListenerRegistration?
    private var boundProfileID: UUID?
    private var boundIsSignedIn = false

    private init() {}

    /// Re-attach the Firestore listener when auth or selected profile changes. Clears `activeJob` when signed out.
    func bind(profileID: UUID, isSignedIn: Bool) {
        boundProfileID = profileID
        boundIsSignedIn = isSignedIn
        attachListenerIfPossible()
    }

    private func attachListenerIfPossible() {
        listener?.remove()
        listener = nil
        activeJob = nil

        guard boundIsSignedIn, let uid = Auth.auth().currentUser?.uid, let profileID = boundProfileID else { return }

        let q = Firestore.firestore()
            .collection("users").document(uid)
            .collection("storybookJobs")
            .order(by: "createdAt", descending: true)
            .limit(to: 25)

        listener = q.addSnapshotListener { [weak self] snap, _ in
            guard let docs = snap?.documents else { return }

            let rows = docs.map { ($0.documentID, $0.data()) }
            let found = FirestoreSyncService.pickActiveStorybookCloudJob(profileId: profileID, rowsNewestFirst: rows)

            let captured = found
            Task { @MainActor [weak self] in
                self?.activeJob = captured
            }
        }
    }
}
