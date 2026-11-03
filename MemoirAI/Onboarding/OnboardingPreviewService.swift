import Foundation
import FirebaseAuth
import FirebaseFunctions
import FirebaseStorage
import UIKit

enum OnboardingPreviewStatus: String {
    case generating
    case imageReady
}

struct OnboardingPreviewResult {
    let status: OnboardingPreviewStatus
    let requestID: String
    let title: String?
    let readingText: String?
    let illustration: UIImage?
    let storagePath: String?
    let cached: Bool
}

enum OnboardingPreviewResponsePolicy {
    static let maximumImageBytes: Int64 = 8 * 1024 * 1024

    static func status(from value: Any?) -> OnboardingPreviewStatus? {
        guard let raw = value as? String else { return nil }
        return OnboardingPreviewStatus(rawValue: raw)
    }

    static func decodedImage(from value: Any?) -> UIImage? {
        guard let encoded = value as? String,
              let data = Data(base64Encoded: encoded),
              data.count <= maximumImageBytes else { return nil }
        return UIImage(data: data)
    }
}

actor OnboardingPreviewService {
    static let shared = OnboardingPreviewService()

    func warmUp() async -> Bool {
        let callable = Functions.functions(region: "us-central1").httpsCallable("createOnboardingPreview")
        callable.timeoutInterval = 15
        do {
            let result = try await callable.call(["warmup": true])
            return (result.data as? [String: Any])?["status"] as? String == "ready"
        } catch {
            return false
        }
    }

    func create(
        expectedUserID: String,
        requestID: String,
        profileID: UUID,
        memoryID: UUID,
        profileName: String,
        storyText: String,
        storytellerRole: String = "subject",
        subjectPhotoStoragePath: String?
    ) async throws -> OnboardingPreviewResult {
        let deadline = ProcessInfo.processInfo.systemUptime + OnboardingPreviewRetryBudget.maximumDuration
        var retryBudget = OnboardingPreviewRetryBudget(deadline: deadline)
        let validateOwnership = {
            guard Auth.auth().currentUser?.uid == expectedUserID else {
                throw OnboardingPreviewServiceError.accountChanged
            }
        }
        for attempt in 0..<OnboardingPreviewPollingPolicy.maximumAttempts {
            try Task.checkCancellation()
            let result = try await retryBudget.perform(validateOwnership: validateOwnership) {
                try await self.request(
                    requestID: requestID, profileID: profileID, memoryID: memoryID,
                    profileName: profileName, storyText: storyText, storytellerRole: storytellerRole,
                    subjectPhotoStoragePath: subjectPhotoStoragePath,
                    deadline: deadline, validateOwnership: validateOwnership
                )
            }
            if result.status == .imageReady { return result }
            if attempt + 1 < OnboardingPreviewPollingPolicy.maximumAttempts {
                try validateOwnership()
                let delay = min(OnboardingPreviewPollingPolicy.delaySeconds, retryBudget.remainingTime)
                guard delay > 0 else { throw OnboardingPreviewServiceError.stillProcessing }
                try await Task.sleep(for: .seconds(delay))
            }
        }
        throw OnboardingPreviewServiceError.stillProcessing
    }

    private func request(
        requestID: String,
        profileID: UUID,
        memoryID: UUID,
        profileName: String,
        storyText: String,
        storytellerRole: String = "subject",
        subjectPhotoStoragePath: String?,
        deadline: TimeInterval,
        validateOwnership: () throws -> Void
    ) async throws -> OnboardingPreviewResult {
        var payload: [String: Any] = [
            "requestId": requestID,
            "profileId": profileID.uuidString.lowercased(),
            "memoryId": memoryID.uuidString.lowercased(),
            "profileName": profileName,
            "storyText": storyText,
            "storytellerRole": storytellerRole
        ]
        if let subjectPhotoStoragePath {
            payload["subjectPhotoStoragePath"] = subjectPhotoStoragePath
        }

        let callable = Functions.functions(region: "us-central1")
            .httpsCallable("createOnboardingPreview")
        try validateOwnership()
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { throw OnboardingPreviewServiceError.stillProcessing }
        callable.timeoutInterval = min(125, remaining)
        let response: HTTPSCallableResult = try await OnboardingPreviewCallbackDeadline<HTTPSCallableResult>.run(timeout: remaining) { completion in
            callable.call(payload) { result, error in
                if let error { completion(.failure(error)) }
                else if let result { completion(.success(result)) }
                else { completion(.failure(OnboardingPreviewServiceError.invalidResponse)) }
            }
            // Callable work may finish on the server after the client deadline.
            // The fixed request ID lets a later retry retrieve that same result.
            return {}
        }
        try validateOwnership()
        try Task.checkCancellation()
        guard deadline > ProcessInfo.processInfo.systemUptime else { throw OnboardingPreviewServiceError.stillProcessing }
        guard let data = response.data as? [String: Any],
              let status = OnboardingPreviewResponsePolicy.status(from: data["status"]),
              let responseRequestID = data["requestId"] as? String,
              responseRequestID == requestID else {
            throw OnboardingPreviewServiceError.invalidResponse
        }
        if status == .generating {
            return OnboardingPreviewResult(
                status: status,
                requestID: requestID,
                title: nil,
                readingText: nil,
                illustration: nil,
                storagePath: nil,
                cached: false
            )
        }

        let title = data["title"] as? String
        let storagePath = data["illustrationStoragePath"] as? String
        var image = OnboardingPreviewResponsePolicy.decodedImage(from: data["imageDataBase64"])
        if image == nil, let storagePath {
            try validateOwnership()
            let reference = Storage.storage().reference(withPath: storagePath)
            let bytes = try await OnboardingPreviewDownload.run(timeout: deadline - ProcessInfo.processInfo.systemUptime) { completion in
                let task = reference.getData(maxSize: OnboardingPreviewResponsePolicy.maximumImageBytes) { data, error in
                    if let error { completion(.failure(error)) }
                    else if let data { completion(.success(data)) }
                    else { completion(.failure(OnboardingPreviewServiceError.invalidResponse)) }
                }
                return { task.cancel() }
            }
            try validateOwnership()
            image = UIImage(data: bytes)
        }
        guard let title, !title.isEmpty, image != nil else {
            throw OnboardingPreviewServiceError.invalidResponse
        }
        return OnboardingPreviewResult(
            status: status,
            requestID: requestID,
            title: title,
            readingText: data["readingText"] as? String,
            illustration: image,
            storagePath: storagePath,
            cached: data["cached"] as? Bool ?? false
        )
    }
}

enum OnboardingPreviewServiceError: LocalizedError {
    case invalidResponse
    case stillProcessing
    case accountChanged

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Your preview arrived incomplete. Please try again."
        case .stillProcessing: return "Your page is still being prepared. Try again to pick up the same preview."
        case .accountChanged: return "Your account changed. Reconnect before opening this preview."
        }
    }
}


enum OnboardingPreviewRecovery: Equatable {
    case retry, reconnect, continueWithoutPreview, cancelled
}

/// One budget spans all polling requests, so an unstable connection cannot
/// multiply the retry allowance at every poll. The request payload stays fixed.
struct OnboardingPreviewRetryBudget {
    static let maximumRetries = 2
    static let maximumDuration: TimeInterval = 150
    private(set) var retriesUsed = 0
    private let deadline: TimeInterval
    private let now: () -> TimeInterval

    init(deadline: TimeInterval? = nil, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        self.deadline = deadline ?? now() + Self.maximumDuration
    }

    var remainingTime: TimeInterval { max(0, deadline - now()) }

    mutating func perform<Value>(
        validateOwnership: () throws -> Void = {},
        sleep: (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        operation: () async throws -> Value
    ) async throws -> Value {
        while true {
            try Task.checkCancellation()
            try validateOwnership()
            guard remainingTime > 0 else { throw OnboardingPreviewServiceError.stillProcessing }
            do {
                let value = try await operation()
                try Task.checkCancellation()
                try validateOwnership()
                guard remainingTime > 0 else { throw OnboardingPreviewServiceError.stillProcessing }
                return value
            } catch {
                try Task.checkCancellation()
                try validateOwnership()
                guard remainingTime > 0 else { throw OnboardingPreviewServiceError.stillProcessing }
                guard retriesUsed < Self.maximumRetries,
                      OnboardingPreviewErrorPolicy.isTransient(error) else { throw error }
                let delay = Double(retriesUsed + 1)
                guard remainingTime > delay else { throw OnboardingPreviewServiceError.stillProcessing }
                retriesUsed += 1
                try await sleep(delay)
            }
        }
    }
}

enum OnboardingPreviewErrorPolicy {
    static func stage(for error: Error) -> String? {
        if error is MemoryCreationError || error is CloudTranscriptionError { return "preflight" }
        switch (error as NSError).domain {
        case FunctionsErrorDomain: return "generation"
        case StorageErrorDomain: return "image_download"
        default: return nil
        }
    }

    static func recovery(for error: Error) -> OnboardingPreviewRecovery {
        if case CloudTranscriptionError.notAuthenticated = error { return .reconnect }
        if case OnboardingPreviewServiceError.accountChanged = error { return .reconnect }
        if error is CancellationError || (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled {
            return .cancelled
        }
        let ns = error as NSError
        if ns.domain == StorageErrorDomain {
            switch ns.code {
            case StorageErrorCode.objectNotFound.rawValue, StorageErrorCode.unauthorized.rawValue:
                return .continueWithoutPreview
            case StorageErrorCode.unauthenticated.rawValue: return .reconnect
            case StorageErrorCode.cancelled.rawValue: return .cancelled
            default: return .retry
            }
        }
        guard ns.domain == FunctionsErrorDomain else { return .retry }
        switch ns.code {
        case FunctionsErrorCode.cancelled.rawValue: return .cancelled
        case FunctionsErrorCode.unauthenticated.rawValue: return .reconnect
        case FunctionsErrorCode.alreadyExists.rawValue,
             FunctionsErrorCode.permissionDenied.rawValue,
             FunctionsErrorCode.failedPrecondition.rawValue: return .continueWithoutPreview
        case FunctionsErrorCode.resourceExhausted.rawValue:
            let reason = (ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any])?["reason"] as? String
            return ["preview-quota-used", "preview-attempts-exhausted"].contains(reason ?? "") ? .continueWithoutPreview : .retry
        default: return .retry
        }
    }

    static func reason(for error: Error) -> String {
        if case CloudTranscriptionError.notAuthenticated = error { return "authentication" }
        if recovery(for: error) == .cancelled { return "cancelled" }
        if case OnboardingPreviewServiceError.accountChanged = error { return "account_changed" }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return "network" }
        if ns.domain == StorageErrorDomain {
            switch ns.code {
            case StorageErrorCode.objectNotFound.rawValue: return "image_missing"
            case StorageErrorCode.unauthenticated.rawValue: return "authentication"
            case StorageErrorCode.unauthorized.rawValue: return "permission_denied"
            case StorageErrorCode.retryLimitExceeded.rawValue: return "network"
            default: return "image_download"
            }
        }
        guard ns.domain == FunctionsErrorDomain else {
            if error is OnboardingPreviewServiceError { return "preview_response" }
            if error is MemoryCreationError || error is CloudTranscriptionError { return "memory_preparation" }
            return "unknown"
        }
        switch ns.code {
        case FunctionsErrorCode.unauthenticated.rawValue: return "authentication"
        case FunctionsErrorCode.permissionDenied.rawValue: return "permission_denied"
        case FunctionsErrorCode.failedPrecondition.rawValue: return "precondition"
        case FunctionsErrorCode.alreadyExists.rawValue: return "request_conflict"
        case FunctionsErrorCode.resourceExhausted.rawValue:
            let reason = (ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any])?["reason"] as? String
            if reason == "preview-quota-used" { return "quota_used" }
            if reason == "preview-attempts-exhausted" { return "attempts_exhausted" }
            return "rate_limited"
        case FunctionsErrorCode.unavailable.rawValue: return "unavailable"
        case FunctionsErrorCode.deadlineExceeded.rawValue: return "timeout"
        default: return "server_error"
        }
    }

    static func isTransient(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain {
            return [FunctionsErrorCode.unavailable.rawValue, FunctionsErrorCode.deadlineExceeded.rawValue].contains(ns.code)
        }
        return ns.domain == NSURLErrorDomain && [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet].contains(ns.code)
    }

    static func message(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == StorageErrorDomain {
            switch StorageErrorCode(rawValue: ns.code) {
            case .objectNotFound:
                return "The preview image couldn’t be opened. You can continue to your saved memory."
            case .unauthenticated:
                return "Reconnect to Memoir to open your preview."
            case .unauthorized:
                return "This preview isn’t available for this account."
            case .cancelled:
                return "Your preview download was paused. Try again to continue."
            default:
                return "Your preview image couldn’t be downloaded. Check your connection and try again."
            }
        }
        guard ns.domain == FunctionsErrorDomain else { return error.localizedDescription }
        switch ns.code {
        case FunctionsErrorCode.permissionDenied.rawValue:
            return "This preview isn’t available for this account."
        case FunctionsErrorCode.failedPrecondition.rawValue:
            return "This preview can’t continue right now."
        case FunctionsErrorCode.alreadyExists.rawValue:
            return "This preview was requested with different details. You can continue without recreating it."
        case FunctionsErrorCode.resourceExhausted.rawValue:
            let reason = (ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any])?["reason"] as? String
            switch reason {
            case "preview-quota-used":
                return "Your free preview has already been used. Your saved memory is still available in your memoir."
            case "preview-attempts-exhausted":
                return "We couldn’t create this preview after several attempts. Your saved memory is still available in your memoir."
            default:
                return "This preview can’t continue right now. Your saved memory is still available in your memoir."
            }
        case FunctionsErrorCode.unauthenticated.rawValue:
            return "Your connection to Memoir expired. Reopen the app to reconnect to your saved memory."
        case FunctionsErrorCode.unavailable.rawValue, FunctionsErrorCode.deadlineExceeded.rawValue:
            return "The connection took too long. Try again to continue the same page."
        default:
            return "We couldn’t finish your page this time. Your memory is saved. Try again to continue."
        }
    }
}

/// Resolves the callback once even if cancellation races an SDK completion.
typealias OnboardingPreviewDownload = OnboardingPreviewCallbackDeadline<Data>

final class OnboardingPreviewCallbackDeadline<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var cancelOperation: (() -> Void)?

    static func run(
        timeout: TimeInterval,
        start: (@escaping (Result<Value, Error>) -> Void) -> (() -> Void)
    ) async throws -> Value {
        guard timeout > 0 else { throw OnboardingPreviewServiceError.stillProcessing }
        let gate = OnboardingPreviewCallbackDeadline<Value>()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                let timer = DispatchWorkItem {
                    gate.finish(.failure(OnboardingPreviewServiceError.stillProcessing))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let cancel = start { result in
                    timer.cancel()
                    gate.finish(result)
                }
                gate.installCancellation {
                    timer.cancel()
                    cancel()
                }
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }

    private func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func installCancellation(_ cancel: @escaping () -> Void) {
        lock.lock()
        let finished = result != nil
        if !finished { cancelOperation = cancel }
        lock.unlock()
        if finished { cancel() }
    }

    private func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let cancel = cancelOperation
        cancelOperation = nil
        lock.unlock()
        cancel?()
        continuation?.resume(with: result)
    }
}
