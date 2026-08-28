import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage

enum SharedAccessGrantPolicy {
    static func grantsMemory(
        grantedMemoryID: String?,
        requestedMemoryID: UUID,
        revoked: Bool
    ) -> Bool {
        !revoked && grantedMemoryID == requestedMemoryID.uuidString
    }
}

enum SharedAccessDocumentID {
    static func requestOrGrant(requesterID: String, memoryID: UUID) -> String {
        "\(memoryID.uuidString)__\(requesterID)"
    }
}

enum SharedAudioAccessPolicy {
    static func audioFile(storagePath: String?, ownerID: String, memoryID: UUID) -> String? {
        guard let storagePath else { return nil }
        for fileExtension in ["m4a", "caf"] {
            let file = "\(memoryID.uuidString).\(fileExtension)"
            if storagePath == "users/\(ownerID)/audio/\(file)" {
                return file
            }
        }
        return nil
    }
}

/// Family and friends shared access. A scan of someone else's memory QR resolves the
/// owner through `memoryIndex/{memoryId}`, creates an access request under the owner's
/// account, and, once the owner approves, reads the shared memory remotely.
///
/// Data model (all rule-gated, see firestore.rules):
/// - `memoryIndex/{memoryId}` → `{ ownerId }`, written server-side only.
/// - `users/{ownerId}/accessRequests/{memoryId}__{requesterUid}` → created by the requester.
/// - `users/{ownerId}/accessGrants/{memoryId}__{requesterUid}` → written by the owner on approval.
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
        /// Composite Firestore request document ID.
        let id: String
        let requesterId: String
        let requesterDisplayName: String
        let memoryId: String?
        let createdAt: Date?
    }

    struct MemoryAccessGrant: Identifiable {
        let id: String
        let requesterId: String
        let memoryId: String
        let grantedAt: Date?
    }

    struct RemoteMemory {
        let id: String
        let prompt: String?
        let transcription: String?
        let audioStoragePath: String?
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

    func grantStatus(ownerId: String, memoryId: UUID) async -> GrantStatus {
        guard let uid = currentUid else { return .none }
        if uid == ownerId { return .owner }
        do {
            let documentID = SharedAccessDocumentID.requestOrGrant(
                requesterID: uid,
                memoryID: memoryId
            )
            let grant = try await db.collection("users").document(ownerId)
                .collection("accessGrants").document(documentID).getDocument()
            if grant.exists, SharedAccessGrantPolicy.grantsMemory(
                grantedMemoryID: grant.data()?["memoryId"] as? String,
                requestedMemoryID: memoryId,
                revoked: grant.data()?["revoked"] as? Bool ?? false
            ) {
                return .granted
            }
            let legacyGrant = try await db.collection("users").document(ownerId)
                .collection("accessGrants").document(uid).getDocument()
            if legacyGrant.exists, SharedAccessGrantPolicy.grantsMemory(
                grantedMemoryID: legacyGrant.data()?["memoryId"] as? String,
                requestedMemoryID: memoryId,
                revoked: legacyGrant.data()?["revoked"] as? Bool ?? false
            ) {
                return .granted
            }
        } catch {
            // Pre-grant reads can be denied by rules; fall through to the request doc.
        }
        do {
            let documentID = SharedAccessDocumentID.requestOrGrant(
                requesterID: uid,
                memoryID: memoryId
            )
            let request = try await db.collection("users").document(ownerId)
                .collection("accessRequests").document(documentID).getDocument()
            guard request.data()?["memoryId"] as? String == memoryId.uuidString else {
                return .none
            }
            switch request.data()?["status"] as? String {
            case "pending": return .pending
            case "denied": return .denied
            case "approved": return .none
            default: return .none
            }
        } catch {
            return .none
        }
    }

    func submitAccessRequest(ownerId: String, memoryId: UUID, displayName: String) async throws {
        guard let uid = currentUid else { throw SharedAccessError.notSignedIn }
        let documentID = SharedAccessDocumentID.requestOrGrant(requesterID: uid, memoryID: memoryId)
        try await db.collection("users").document(ownerId)
            .collection("accessRequests").document(documentID).setData([
                "requesterUid": uid,
                "requesterDisplayName": displayName,
                "status": "pending",
                "memoryId": memoryId.uuidString,
                "createdAt": FieldValue.serverTimestamp()
            ])
    }

    /// Live status of my own request under this owner; fires on every change while observed.
    func observeMyRequestStatus(
        ownerId: String,
        memoryId: UUID,
        onChange: @escaping (GrantStatus) -> Void
    ) -> ListenerRegistration? {
        guard let uid = currentUid else { return nil }
        let documentID = SharedAccessDocumentID.requestOrGrant(requesterID: uid, memoryID: memoryId)
        return db.collection("users").document(ownerId)
            .collection("accessRequests").document(documentID)
            .addSnapshotListener { snap, _ in
                guard snap?.data()?["memoryId"] as? String == memoryId.uuidString else {
                    onChange(.none)
                    return
                }
                switch snap?.data()?["status"] as? String {
                case "approved":
                    Task {
                        onChange(await self.grantStatus(ownerId: ownerId, memoryId: memoryId))
                    }
                case "denied": onChange(.denied)
                case "pending": onChange(.pending)
                default: onChange(.none)
                }
            }
    }

    func fetchSharedMemory(ownerId: String, memoryId: UUID) async throws -> RemoteMemory {
        let userRef = db.collection("users").document(ownerId)
        var snap = try await userRef
            .collection("sharedMemories").document(memoryId.uuidString).getDocument()
        if !snap.exists {
            // Existing App Store grants used requester-only document IDs before
            // redacted projections existed. Rules permit this fallback only for
            // those exact legacy grants; composite grants cannot read the source.
            snap = try await userRef.collection("memories").document(memoryId.uuidString).getDocument()
        }
        guard snap.exists, let data = snap.data() else { throw SharedAccessError.memoryUnavailable }
        return RemoteMemory(
            id: memoryId.uuidString,
            prompt: data["prompt"] as? String,
            transcription: data["transcription"] as? String,
            audioStoragePath: data["audioStoragePath"] as? String,
            profileName: data["profileName"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    func downloadSharedAudio(ownerId: String, memoryId: UUID, storagePath: String) async throws -> URL {
        let expectedPrefix = "users/\(ownerId)/audio/\(memoryId.uuidString)."
        guard storagePath.hasPrefix(expectedPrefix),
              ["m4a", "caf"].contains(URL(fileURLWithPath: storagePath).pathExtension.lowercased()) else {
            throw SharedAccessError.memoryUnavailable
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-\(UUID().uuidString).\(URL(fileURLWithPath: storagePath).pathExtension)")
        do {
            return try await withCheckedThrowingContinuation { continuation in
                Storage.storage().reference(withPath: storagePath).write(toFile: destination) { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: SharedAccessError.memoryUnavailable)
                    }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // MARK: - Owner side

    func fetchPendingRequests() async throws -> [MemoryAccessRequest] {
        guard let uid = currentUid else { throw SharedAccessError.notSignedIn }
        let qs = try await db.collection("users").document(uid)
            .collection("accessRequests")
            .whereField("status", isEqualTo: "pending")
            .limit(to: 100)
            .getDocuments()
        return qs.documents.map { doc in
            let data = doc.data()
            return MemoryAccessRequest(
                id: doc.documentID,
                requesterId: (data["requesterUid"] as? String) ?? doc.documentID,
                requesterDisplayName: (data["requesterDisplayName"] as? String) ?? "Someone",
                memoryId: data["memoryId"] as? String,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
            )
        }
    }

    func fetchActiveGrants() async throws -> [MemoryAccessGrant] {
        guard let uid = currentUid else { throw SharedAccessError.notSignedIn }
        let qs = try await db.collection("users").document(uid)
            .collection("accessGrants")
            .whereField("revoked", isEqualTo: false)
            .limit(to: 100)
            .getDocuments()
        var grants: [MemoryAccessGrant] = []
        for doc in qs.documents {
            let data = doc.data()
            guard let requesterId = data["requesterUid"] as? String else { continue }
            var memoryId = data["memoryId"] as? String
            if memoryId == nil {
                let request = try await db.collection("users").document(uid)
                    .collection("accessRequests").document(doc.documentID)
                    .getDocument()
                let requestData = request.data() ?? [:]
                guard requestData["requesterUid"] as? String == requesterId,
                      requestData["status"] as? String == "approved" else { continue }
                memoryId = requestData["memoryId"] as? String
            }
            guard let memoryId, UUID(uuidString: memoryId) != nil else { continue }
            grants.append(MemoryAccessGrant(
                id: doc.documentID,
                requesterId: requesterId,
                memoryId: memoryId,
                grantedAt: (data["grantedAt"] as? Timestamp)?.dateValue()
            ))
        }
        return grants
    }

    /// Approve atomically: mark the request approved and create the grant in one batch,
    /// so a crash between the two writes can never leave an approved request without a grant.
    func approve(requestDocumentId: String) async throws {
        guard let uid = currentUid else { throw SharedAccessError.notSignedIn }
        let userRef = db.collection("users").document(uid)
        let requestRef = userRef.collection("accessRequests").document(requestDocumentId)
        let requestSnapshot = try await requestRef.getDocument()
        guard let memoryId = requestSnapshot.data()?["memoryId"] as? String,
              let memoryUUID = UUID(uuidString: memoryId) else {
            throw SharedAccessError.memoryUnavailable
        }
        let requesterId = (requestSnapshot.data()?["requesterUid"] as? String) ?? requestDocumentId
        let grantDocumentID = SharedAccessDocumentID.requestOrGrant(
            requesterID: requesterId,
            memoryID: memoryUUID
        )
        let memorySnapshot = try await userRef.collection("memories").document(memoryId).getDocument()
        guard memorySnapshot.exists else { throw SharedAccessError.memoryUnavailable }
        let audioFile = SharedAudioAccessPolicy.audioFile(
            storagePath: memorySnapshot.data()?["audioStoragePath"] as? String,
            ownerID: uid,
            memoryID: memoryUUID
        )
        let batch = db.batch()
        batch.updateData(
            ["status": "approved", "respondedAt": FieldValue.serverTimestamp()],
            forDocument: requestRef
        )
        batch.setData(
            [
                "requesterUid": requesterId,
                "memoryId": memoryId,
                "grantedAt": FieldValue.serverTimestamp(),
                "revoked": false
            ],
            forDocument: userRef.collection("accessGrants").document(grantDocumentID)
        )
        let memoryData = memorySnapshot.data() ?? [:]
        var sharedMemoryData: [String: Any] = [
            "memoryId": memoryId,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        for key in ["prompt", "transcription", "profileName", "createdAt", "audioStoragePath"] {
            if let value = memoryData[key] {
                sharedMemoryData[key] = value
            }
        }
        batch.setData(
            sharedMemoryData,
            forDocument: userRef.collection("sharedMemories").document(memoryId),
            merge: true
        )
        if let audioFile {
            batch.setData(
                [
                    "requesterUid": requesterId,
                    "memoryId": memoryId,
                    "audioFile": audioFile,
                    "grantedAt": FieldValue.serverTimestamp(),
                    "revoked": false
                ],
                forDocument: userRef.collection("sharedAudioAccess")
                    .document("\(audioFile)__\(requesterId)")
            )
        }
        try await batch.commit()
    }

    func deny(requestDocumentId: String) async throws {
        guard let uid = currentUid else { throw SharedAccessError.notSignedIn }
        try await db.collection("users").document(uid)
            .collection("accessRequests").document(requestDocumentId)
            .updateData(["status": "denied", "respondedAt": FieldValue.serverTimestamp()])
    }

    func revoke(grant: MemoryAccessGrant) async throws {
        guard currentUid != nil else { throw SharedAccessError.notSignedIn }
        let callable = Functions.functions().httpsCallable("revokeSharedMemoryAccess")
        callable.timeoutInterval = 30
        _ = try await callable.call([
            "grantId": grant.id,
            "memoryId": grant.memoryId
        ])
    }
}
