import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ActiveStorybookJobObserver: ObservableObject {
    static let shared = ActiveStorybookJobObserver()

    @Published private(set) var activeJob: FirestoreSyncService.ActiveStorybookCloudJob?

    private var listeners: [ListenerRegistration] = []
    private var scope: ProfileContentScope?
    private var rowsByField: [String: [(documentID: String, data: [String: Any])]] = [:]

    private init() {}

    func bind(profileID: UUID, isSignedIn: Bool) {
        let userID = isSignedIn ? Auth.auth().currentUser?.uid : nil
        if let scope, scope.userID == userID, scope.profileID == profileID { return }
        listeners.forEach { $0.remove() }
        listeners = []
        scope = nil
        rowsByField = [:]
        activeJob = nil
        guard let userID else { return }
        let requestedScope = ProfileContentScope(userID: userID, profileID: profileID)
        scope = requestedScope
        let collection = Firestore.firestore().collection("users").document(userID).collection("storybookJobs")
        let identifiers = [profileID.uuidString, profileID.uuidString.lowercased()]
        for field in ["profileId", "profileID"] {
            let listener = collection.whereField(field, in: identifiers).addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                let rows = snapshot.documents.map { (documentID: $0.documentID, data: $0.data()) }
                Task { @MainActor [weak self] in
                    guard let self, let currentScope = self.scope,
                          requestedScope.isCurrent(userID: Auth.auth().currentUser?.uid,
                                                   profileID: currentScope.profileID,
                                                   requestID: currentScope.requestID) else { return }
                    self.rowsByField[field] = rows
                    let normalized = ProfileCloudRowsPolicy.normalizedRows(
                        self.rowsByField.values.flatMap { $0 }, profileID: profileID
                    )
                    self.activeJob = FirestoreSyncService.pickActiveStorybookCloudJob(
                        profileId: profileID, rowsNewestFirst: normalized.map { ($0.documentID, $0.data) }
                    )
                }
            }
            listeners.append(listener)
        }
    }
}
