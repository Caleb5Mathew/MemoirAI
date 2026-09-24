import Foundation
import FirebaseAuth
import FirebaseFunctions
import FirebaseStorage

enum EnhancementVoiceTranscriptionError: LocalizedError {
    case notAuthenticated
    case invalidRecording
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to transcribe this answer."
        case .invalidRecording:
            return "This recording could not be read. Please record your answer again."
        case .invalidResponse:
            return "The transcription service returned an invalid response. Please try again."
        }
    }
}

enum EnhancementVoiceUploadPolicy {
    static let maximumBytes = 25 * 1024 * 1024

    static func path(userID: String, uploadID: UUID) -> String {
        "users/\(userID)/enhancementAudio/\(uploadID.uuidString).m4a"
    }

    static func isValidFile(byteCount: Int, pathExtension: String) -> Bool {
        byteCount > 0 && byteCount <= maximumBytes && pathExtension.lowercased() == "m4a"
    }
}

/// Transcribes a guided-enhancement answer with the same server-side model and
/// prompt used for saved memory recordings. The uploaded answer is temporary.
actor EnhancementVoiceTranscriptionService {
    static let shared = EnhancementVoiceTranscriptionService()

    private init() {}

    func transcribe(url: URL, glossary: [String], language: String = "en") async throws -> String {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw EnhancementVoiceTranscriptionError.notAuthenticated
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard EnhancementVoiceUploadPolicy.isValidFile(
            byteCount: byteCount,
            pathExtension: url.pathExtension
        ) else {
            throw EnhancementVoiceTranscriptionError.invalidRecording
        }

        let uploadID = UUID()
        let storagePath = EnhancementVoiceUploadPolicy.path(userID: userID, uploadID: uploadID)
        let reference = Storage.storage().reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "audio/mp4"

        _ = try await reference.putFileAsync(from: url, metadata: metadata)
        guard Auth.auth().currentUser?.uid == userID else {
            try? await reference.delete()
            throw EnhancementVoiceTranscriptionError.notAuthenticated
        }

        do {
            let callable = Functions.functions().httpsCallable("transcribeEnhancementAudio")
            callable.timeoutInterval = 330
            let result = try await callable.call([
                "uploadId": uploadID.uuidString,
                "language": language,
                "glossary": glossary
            ])
            guard
                let payload = result.data as? [String: Any],
                let text = payload["text"] as? String,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw EnhancementVoiceTranscriptionError.invalidResponse
            }
            try? await reference.delete()
            return text
        } catch {
            try? await reference.delete()
            throw error
        }
    }
}
