import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Family and friends shared access. A scan of someone else's memory QR resolves the
/// owner through `memoryIndex/{memoryId}`, creates an access request under the owner's
/// account, and, once the owner approves, reads the shared memory remotely.
///
/// Data model (all rule-gated, see firestore.rules):
/// - `memoryIndex/{memoryId}` → `{ ownerId }`, written server-side only.
/// - `users/{ownerId}/accessRequests/{requesterUid}` → created by the requester.
/// - `users/{ownerId}/accessGrants/{requesterUid}` → written by the owner on approval.
final class SharedAccessService {
    static let shared = SharedAccessService()

    enum SharedAccessError: LocalizedError {
        case notSignedIn
        case memoryUnavailable

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "You need to be signed in to request access."
            case .memoryUnavailable: return "This memory is not available."
            }
        }
    }

    enum GrantStatus {
        case owner
        case granted
        case pending
        case denied
        case none
    }

    struct MemoryAccessRequest: Identifiable {
        /// Requester's uid — also the request doc ID, so one request per person.
        let id: String
        let requesterDisplayName: String
        let memoryId: String?
        let createdAt: Date?
    }

    struct RemoteMemory {
        let id: String
        let prompt: String?
        let transcription: String?
        let audioURL: URL?
        let profileName: String?
        let createdAt: Date?
    }

    private var db: Firestore { Firestore.firestore() }
    private var currentUid: String? { Auth.auth().currentUser?.uid }

    // MARK: - Owner resolution

    /// Returns the owning uid for a memory, or nil when the memory is not indexed
    /// (deleted, or created before the index backfill ran).
    func resolveOwner(memoryId: UUID) async throws -> String? {
        let snap = try await db.collection("memoryIndex").document(memoryId.uuidString).getDocument()
        guard snap.exists else { return nil }
        let ownerId = (snap.data()?["ownerId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (ownerId?.isEmpty == false) ? ownerId : nil
    }

    // MARK: - Requester side

    func grantStatus(ownerId: String) async -> GrantStatus {
        guard let uid = currentUid else { return .none }
        if uid == ownerId { return .owner }
        do {
            let grant = try await db.collection("users").document(ownerId)
                .collection("accessGrants").document(uid).getDocument()
            if grant.exists, (grant.data()?["revoked"] as? Bool) != true {
                return .granted
            }
        } catch {
            // Pre-grant reads can be denied by rules; fall through to the request doc.
        }
        do {
            let request = try await db.collection("users").document(ownerId)
                .collection("accessRequests").document(uid).getDocument()
            switch request.data()?["status"] as? String {
            case "pending": return .pending
            case "denied": return .denied
            case "approved": return .granted
            default: return .none
            }
        } catch {
            return .none
        }
    }

    func submitAccessRequest(ownerId: String, memoryId: UUID, displayName: String) async throws {
        guard let uid = currentUid else { throw SharedAccessError.notSignedIn }
        try await db.collection("users").document(ownerId)
            .collection("accessRequests").document(uid).setData([
                "requesterDisplayName": displayName,
                "status": "pending",
                "memoryId": memoryId.uuidString,
                "createdAt": FieldValue.serverTimestamp()
            ])
    }

    /// Live status of my own request under this owner; fires on every change while observed.
    func observeMyRequestStatus(ownerId: String, onChange: @escaping (GrantStatus) -> Void) -> ListenerRegistration? {
        guard let uid = currentUid else { return nil }
        return db.collection("users").document(ownerId)
            .collection("accessRequests").document(uid)
            .addSnapshotListener { snap, _ in
                switch snap?.data()?["status"] as? String {
                case "approved": onChange(.granted)
                case "denied": onChange(.denied)
                case "pending": onChange(.pending)
                default: onChange(.none)
                }
            }
    }

    func fetchSharedMemory(ownerId: String, memoryId: UUID) async throws -> RemoteMemory {
        let snap = try await db.collection("users").document(ownerId)
            .collection("memories").document(memoryId.uuidString).getDocument()
        guard snap.exists, let data = snap.data() else { throw SharedAccessError.memoryUnavailable }
        let audioURLString = (data["audioURL"] as? String) ?? ""
        return RemoteMemory(
            id: memoryId.uuidString,
            prompt: data["prompt"] as? String,
            transcription: data["transcription"] as? String,
            audioURL: URL(string: audioURLString),
            profileName: data["profileName"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    // MARK: - Owner side

    func fetchPendingRequests() async throws -> [MemoryAccessRequest] {
        guard let uid = currentUid else { throw SharedAccessError.notSignedIn }
        let qs = try await db.collection("users").document(uid)
            .collection("accessRequests")
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        return qs.documents.map { doc in
            let data = doc.data()
            return MemoryAccessRequest(
                id: doc.documentID,
                requesterDisplayName: (data["requesterDisplayName"] as? String) ?? "Someone",
                memoryId: data["memoryId"] as? String,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
            )
        }
    }

    /// Approve atomically: mark the request approved and create the grant in one batch,
    /// so a crash between the two writes can never leave an approved request without a grant.
    func approve(requesterId: String) async throws {
        guard let uid = currentUid else { throw SharedAccessError.notSignedIn }
        let userRef = db.collection("users").document(uid)
        let batch = db.batch()
        batch.updateData(
            ["status": "approved", "respondedAt": FieldValue.serverTimestamp()],
            forDocument: userRef.collection("accessRequests").document(requesterId)
        )
        batch.setData(
            ["requesterUid": requesterId, "grantedAt": FieldValue.serverTimestamp(), "revoked": false],
            forDocument: userRef.collection("accessGrants").document(requesterId)
        )
        try await batch.commit()
    }

    func deny(requesterId: String) async throws {
        guard let uid = currentUid else { throw SharedAccessError.notSignedIn }
        try await db.collection("users").document(uid)
            .collection("accessRequests").document(requesterId)
            .updateData(["status": "denied", "respondedAt": FieldValue.serverTimestamp()])
    }
}
