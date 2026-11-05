import Foundation
import FirebaseAuth
import FirebaseFunctions

enum CloudTranscriptionError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case alreadyProcessing
    case accountChanged
    case memoryUnavailable
    case failure(TranscriptionIssue)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to transcribe a recording."
        case .invalidResponse: return "The transcription service returned an invalid response."
        case .alreadyProcessing: return "This recording is already being transcribed."
        case .accountChanged: return "Your account changed. Open the memory again to retry."
        case .memoryUnavailable: return "This memory is no longer available in the selected profile."
        case .failure(let issue): return issue.message
        }
    }
}

enum MemoryTranscriptionSyncMode: Equatable {
    case resetForNewAudio
    case writeEditedText(String)
    case writeLegacyText(String)
    case preserveServer
}

enum MemoryTranscriptionTextPolicy {
    static func validUserEdit(_ text: String?) -> String? {
        guard let text else { return nil }
        if !text.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return text
    }

    static func displayText(edited: String?, canonical: String?, raw: String?) -> String {
        if let edited = validUserEdit(edited) { return edited }
        if let canonical, !canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return canonical
        }
        return raw ?? ""
    }
}

enum MemoryTranscriptionSyncPolicy {
    static func mode(
        audioChanged: Bool,
        isM4A: Bool,
        status: String?,
        editedText: String?,
        text: String
    ) -> MemoryTranscriptionSyncMode {
        if audioChanged && isM4A && status?.lowercased() == "queued" { return .resetForNewAudio }
        if let editedText = MemoryTranscriptionTextPolicy.validUserEdit(editedText) {
            return .writeEditedText(editedText)
        }
        if !isM4A || status == nil { return .writeLegacyText(text) }
        return .preserveServer
    }
}

enum TranscriptionRetryPolicy {
    static let processingTimeout: TimeInterval = 6 * 60

    static func shouldRequest(
        status: String?,
        audioFileExtension: String?,
        updatedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard audioFileExtension?.lowercased() == "m4a" else { return false }
        switch status?.lowercased() {
        case "queued", "failed":
            return true
        case "processing":
            guard let updatedAt else { return true }
            return now.timeIntervalSince(updatedAt) >= processingTimeout
        default:
            return false
        }
    }
}

enum BookTranscriptionPreflightPolicy {
    static func hasUsableText(_ text: String?) -> Bool {
        !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func shouldRequestTranscription(
        text: String?,
        audioFileURL: String?,
        status: String?,
        updatedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard !hasUsableText(text) else { return false }
        return TranscriptionRetryPolicy.shouldRequest(
            status: status,
            audioFileExtension: URL(string: audioFileURL ?? "")?.pathExtension,
            updatedAt: updatedAt,
            now: now
        )
    }
}

enum TranscriptionFailurePolicy {
    static func status(for errorDescription: String) -> String {
        let message = errorDescription.lowercased()
        let permanentPhrases = [
            "too large",
            "could not be read",
            "no speech was detected",
            "format is unsupported",
            "record it again",
            "re-recorded"
        ]
        return permanentPhrases.contains(where: message.contains) ? "needsRerecording" : "failed"
    }
}

enum RecordingDurationPolicy {
    static let providerMaximumDuration: TimeInterval = 60 * 60
    static let finalizationSafetyMargin: TimeInterval = 5
    static let maximumRecordingDuration = providerMaximumDuration - finalizationSafetyMargin
    static let warningThreshold = maximumRecordingDuration - 30
    static let countdownStart = maximumRecordingDuration - 3

    static func remainingDuration(after elapsed: TimeInterval) -> TimeInterval {
        max(0, maximumRecordingDuration - max(0, elapsed))
    }

    static func shouldStop(elapsed: TimeInterval) -> Bool {
        elapsed >= maximumRecordingDuration
    }
}

enum RecordingStartErrorPolicy {
    static func message(detail: String? = nil) -> String {
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return "Memoir could not start recording. Check your microphone and try again."
        }
        return "Memoir could not start recording. \(trimmed)"
    }
}

enum CloudTranscriptionDisclosure {
    private static let acceptedVersionKey = "memoirai_cloud_transcription_disclosure_version"
    private static let currentVersion = 1

    static let title = "Audio & Transcription Privacy"
    static let message = "Saved voice memories are uploaded to your private MemoirAI account and sent to our transcription provider to create transcripts. You can delete a memory and its transcript at any time."

    static func isAccepted(defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: acceptedVersionKey) >= currentVersion
    }

    static func accept(defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: acceptedVersionKey)
    }
}


enum TranscriptionIssue: String, CaseIterable {
    case authentication, permissionDenied, uploadNotReady, rateLimited, dailyLimit
    case network, timeout, processing, rerecord, accountChanged, cancelled, unknown

    var message: String {
        switch self {
        case .authentication: return "Sign in again to transcribe this recording. Your audio is saved."
        case .permissionDenied: return "Memoir could not access this recording. Sign in again, then retry."
        case .uploadNotReady: return "The recording has not finished uploading. Check your connection and retry."
        case .rateLimited: return "The transcription service is busy. Wait a minute, then retry."
        case .dailyLimit: return "Today's transcription capacity has been reached. Your audio is saved; try again tomorrow."
        case .network: return "The transcript could not finish because the connection was interrupted. Check your connection and retry."
        case .timeout: return "Transcription timed out. Your audio is saved; retry to finish it."
        case .processing: return "This recording is already being transcribed."
        case .rerecord: return "This recording could not be read. Record it again or write the story instead."
        case .accountChanged: return "Your account changed. Open the memory again to retry."
        case .cancelled: return "Transcription was interrupted. Your audio is saved; retry to finish it."
        case .unknown: return "The transcript could not be created. Your audio is saved; retry or write the story instead."
        }
    }

    var analyticsReason: String {
        switch self {
        case .authentication: return "authentication"
        case .permissionDenied: return "permission_denied"
        case .uploadNotReady, .rerecord: return "precondition"
        case .rateLimited: return "rate_limited"
        case .dailyLimit: return "quota_used"
        case .network: return "network"
        case .timeout: return "timeout"
        case .processing: return "request_conflict"
        case .accountChanged: return "account_changed"
        case .cancelled: return "cancelled"
        case .unknown: return "unknown"
        }
    }

    static func classify(_ error: Error) -> Self {
        if error is CancellationError { return .cancelled }
        if let error = error as? CloudTranscriptionError {
            switch error {
            case .notAuthenticated: return .authentication
            case .alreadyProcessing: return .processing
            case .accountChanged: return .accountChanged
            case .memoryUnavailable: return .permissionDenied
            case .failure(let issue): return issue
            case .invalidResponse: return .unknown
            }
        }
        let error = error as NSError
        if error.domain == NSURLErrorDomain {
            if error.code == NSURLErrorCancelled { return .cancelled }
            return error.code == NSURLErrorTimedOut ? .timeout : .network
        }
        let message = error.localizedDescription.lowercased()
        if error.domain == FunctionsErrorDomain {
            switch FunctionsErrorCode(rawValue: error.code) {
            case .unauthenticated: return .authentication
            case .permissionDenied: return .permissionDenied
            case .resourceExhausted: return message.contains("today") || message.contains("tomorrow") ? .dailyLimit : .rateLimited
            case .deadlineExceeded: return .timeout
            case .unavailable: return .network
            case .notFound: return .uploadNotReady
            case .aborted: return .accountChanged
            case .failedPrecondition:
                return TranscriptionFailurePolicy.status(for: message) == "needsRerecording" ? .rerecord : .uploadNotReady
            default: break
            }
        }
        return TranscriptionFailurePolicy.status(for: message) == "needsRerecording" ? .rerecord : .unknown
    }
}

enum TranscriptionPresentationPolicy {
    static func isActive(status: String?, updatedAt: Date?, isInFlight: Bool = false, now: Date = Date()) -> Bool {
        if isInFlight { return true }
        guard status == "processing", let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) < TranscriptionRetryPolicy.processingTimeout
    }

    static func canRetry(status: String?, updatedAt: Date?, audioURL: String?, now: Date = Date()) -> Bool {
        guard URL(string: audioURL ?? "")?.pathExtension.lowercased() == "m4a" else { return false }
        switch status {
        case "failed", nil: return true
        case "queued": return updatedAt.map { now.timeIntervalSince($0) >= 30 } ?? true
        case "processing": return !isActive(status: status, updatedAt: updatedAt, now: now)
        default: return false
        }
    }
}

enum TranscriptionFailureStore {
    static func key(memoryID: UUID, userID: String) -> String {
        "memoirai.transcription.failure.\(userID).\(memoryID.uuidString.lowercased())"
    }

    static func record(_ issue: TranscriptionIssue, memoryID: UUID, userID: String, now: Date = Date(), defaults: UserDefaults = .standard) {
        let delay: TimeInterval
        switch issue {
        case .dailyLimit:
            let nextUTCDay = floor(now.timeIntervalSince1970 / 86_400 + 1) * 86_400
            delay = nextUTCDay - now.timeIntervalSince1970
        case .rateLimited: delay = 60
        case .authentication, .permissionDenied, .rerecord: delay = 300
        default: delay = 30
        }
        defaults.set(["reason": issue.rawValue, "retryAt": now.addingTimeInterval(delay).timeIntervalSince1970], forKey: key(memoryID: memoryID, userID: userID))
    }

    static func issue(memoryID: UUID?, userID: String?, defaults: UserDefaults = .standard) -> TranscriptionIssue? {
        guard let memoryID, let userID,
              let raw = defaults.dictionary(forKey: key(memoryID: memoryID, userID: userID))?["reason"] as? String else { return nil }
        return TranscriptionIssue(rawValue: raw)
    }

    static func canAutomaticallyRetry(memoryID: UUID, userID: String, now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard let timestamp = defaults.dictionary(forKey: key(memoryID: memoryID, userID: userID))?["retryAt"] as? Double else { return true }
        return now.timeIntervalSince1970 >= timestamp
    }

    static func clear(memoryID: UUID, userID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(memoryID: memoryID, userID: userID))
    }
}

enum MemoryCloudAudioPolicy {
    static func isM4A(uploadURL: URL?, existingAudioURL: String?, remoteStoragePath: String?) -> Bool {
        if let uploadURL { return uploadURL.pathExtension.lowercased() == "m4a" }
        if let remoteStoragePath, !remoteStoragePath.isEmpty {
            return (remoteStoragePath as NSString).pathExtension.lowercased() == "m4a"
        }
        return URL(string: existingAudioURL ?? "")?.pathExtension.lowercased() == "m4a"
    }
}

actor CloudTranscriptionService {
    static let shared = CloudTranscriptionService()
    private var activeMemoryIDs = Set<UUID>()

    private init() {}

    func transcribe(memoryID: UUID, profile: Profile, language: String = "en") async throws -> String {
        try await transcribe(
            memoryID: memoryID,
            glossary: Self.glossary(for: profile),
            language: language
        )
    }

    func transcribe(memoryID: UUID, glossary: [String], language: String = "en") async throws -> String {
        guard let expectedUserID = Auth.auth().currentUser?.uid else { throw CloudTranscriptionError.notAuthenticated }
        guard activeMemoryIDs.insert(memoryID).inserted else {
            throw CloudTranscriptionError.alreadyProcessing
        }
        defer { activeMemoryIDs.remove(memoryID) }
        let expectedAudioFileURL = try await MainActor.run {
            guard let entry = PersistenceController.shared.entry(id: memoryID),
                  entry.firebaseUserId == expectedUserID else { throw CloudTranscriptionError.memoryUnavailable }
            return entry.audioFileURL
        }
        let startedAt = Date()
        await MainActor.run {
            ProductAnalytics.shared.track("Memory Transcription Started")
        }
        await updateLocalState(memoryID: memoryID, status: "processing", expectedUserID: expectedUserID)
        guard Auth.auth().currentUser?.uid == expectedUserID else { throw CloudTranscriptionError.accountChanged }
        let callable = Functions.functions().httpsCallable("transcribeMemoryAudio")
        // Allow the 300-second server deadline plus callable transport overhead.
        callable.timeoutInterval = 330
        do {
            let result = try await callable.call([
                "memoryId": memoryID.uuidString,
                "language": language,
                "glossary": glossary
            ])
            guard let payload = result.data as? [String: Any] else {
                throw CloudTranscriptionError.invalidResponse
            }
            if payload["status"] as? String == "processing" {
                throw CloudTranscriptionError.alreadyProcessing
            }
            guard
                  let text = payload["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudTranscriptionError.invalidResponse
            }
            let rawText = (payload["rawText"] as? String).flatMap {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
            } ?? text
            try await saveCompletedTranscription(
                text,
                rawText: rawText,
                memoryID: memoryID,
                language: language,
                expectedAudioFileURL: expectedAudioFileURL,
                expectedUserID: expectedUserID
            )
            await MainActor.run {
                TranscriptionFailureStore.clear(memoryID: memoryID, userID: expectedUserID)
                ProductAnalytics.shared.track("Memory Transcription Completed", ["duration_ms": max(0, Int(Date().timeIntervalSince(startedAt) * 1000))])
            }
            return text
        } catch {
            if case CloudTranscriptionError.alreadyProcessing = error {
                throw error
            }
            let issue = TranscriptionIssue.classify(error)
            await updateLocalState(
                memoryID: memoryID,
                status: issue == .rerecord ? "needsRerecording" : "failed",
                expectedAudioFileURL: expectedAudioFileURL,
                expectedUserID: expectedUserID
            )
            await MainActor.run {
                guard Auth.auth().currentUser?.uid == expectedUserID,
                      let entry = PersistenceController.shared.entry(id: memoryID),
                      entry.firebaseUserId == expectedUserID,
                      entry.audioFileURL == expectedAudioFileURL else { return }
                TranscriptionFailureStore.record(issue, memoryID: memoryID, userID: expectedUserID)
                ProductAnalytics.shared.track("Memory Transcription Failed", ["failure_stage": "transcription", "failure_reason": issue.analyticsReason, "duration_ms": max(0, Int(Date().timeIntervalSince(startedAt) * 1000))])
            }
            switch issue {
            case .authentication: throw CloudTranscriptionError.notAuthenticated
            case .accountChanged: throw CloudTranscriptionError.accountChanged
            case .cancelled: throw CancellationError()
            default: throw CloudTranscriptionError.failure(issue)
            }
        }
    }

    static func glossary(for profile: Profile) -> [String] {
        var seen = Set<String>()
        let unsupportedCharacters = CharacterSet(charactersIn: "<>\r\n")
        let terms = ([profile.name] + profile.childNames + profile.transcriptionGlossary)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty &&
                $0.count <= 80 &&
                $0.rangeOfCharacter(from: unsupportedCharacters) == nil &&
                seen.insert($0.lowercased()).inserted
            }
        return Array(terms.prefix(40))
    }

    private func saveCompletedTranscription(
        _ text: String,
        rawText: String,
        memoryID: UUID,
        language: String,
        expectedAudioFileURL: String?,
        expectedUserID: String
    ) async throws {
        try await MainActor.run {
            guard Auth.auth().currentUser?.uid == expectedUserID else { throw CloudTranscriptionError.accountChanged }
            guard let entry = PersistenceController.shared.entry(id: memoryID), entry.firebaseUserId == expectedUserID else { throw CloudTranscriptionError.memoryUnavailable }
            guard entry.audioFileURL == expectedAudioFileURL else { throw CloudTranscriptionError.accountChanged }
            entry.transcriptionRawText = rawText
            entry.transcriptionStatus = "completed"
            entry.transcriptionLanguage = language
            entry.transcriptionModel = "gpt-transcribe"
            entry.transcriptionVersion += 1
            entry.transcriptionUpdatedAt = Date()
            if MemoryTranscriptionTextPolicy.validUserEdit(entry.transcriptionEditedText) == nil {
                entry.transcriptionEditedText = nil
                entry.text = text
            }
            try entry.managedObjectContext?.save()
            NotificationCenter.default.post(name: .memorySaved, object: nil)
        }
    }

    private func updateLocalState(
        memoryID: UUID,
        status: String,
        expectedAudioFileURL: String? = nil,
        expectedUserID: String
    ) async {
        await MainActor.run {
            guard Auth.auth().currentUser?.uid == expectedUserID,
                  let entry = PersistenceController.shared.entry(id: memoryID), entry.firebaseUserId == expectedUserID else { return }
            if let expectedAudioFileURL, entry.audioFileURL != expectedAudioFileURL { return }
            entry.transcriptionStatus = status
            entry.transcriptionUpdatedAt = Date()
            do {
                try entry.managedObjectContext?.save()
                NotificationCenter.default.post(name: .memorySaved, object: nil)
            } catch {
                print("⚠️ Could not save transcription status: \(error.localizedDescription)")
            }
        }
    }
}
