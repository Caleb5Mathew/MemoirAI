import Foundation
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

    func uploadPhoto(_ jpeg: Data?, requestID: String, userID: String) async throws -> String? {
        guard let jpeg else { return nil }
        guard jpeg.count <= 5 * 1024 * 1024 else { throw OnboardingPreviewServiceError.photoTooLarge }
        let path = "users/\(userID)/onboardingPreviews/\(requestID)/subjectPhoto.jpg"
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await Storage.storage().reference(withPath: path).putDataAsync(jpeg, metadata: metadata)
        return path
    }

    func create(
        requestID: String,
        profileID: UUID,
        memoryID: UUID,
        profileName: String,
        storyText: String,
        storytellerRole: String = "subject",
        subjectPhotoStoragePath: String?
    ) async throws -> OnboardingPreviewResult {
        for attempt in 0..<OnboardingPreviewPollingPolicy.maximumAttempts {
            try Task.checkCancellation()
            let result = try await request(
                requestID: requestID, profileID: profileID, memoryID: memoryID,
                profileName: profileName, storyText: storyText, storytellerRole: storytellerRole,
                subjectPhotoStoragePath: subjectPhotoStoragePath
            )
            if result.status == .imageReady { return result }
            if attempt + 1 < OnboardingPreviewPollingPolicy.maximumAttempts {
                try await Task.sleep(for: .seconds(OnboardingPreviewPollingPolicy.delaySeconds))
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
        subjectPhotoStoragePath: String?
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
        callable.timeoutInterval = 125
        let response = try await callable.call(payload)
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
            let bytes = try await Storage.storage().reference(withPath: storagePath)
                .data(maxSize: OnboardingPreviewResponsePolicy.maximumImageBytes)
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
    case photoTooLarge
    case stillProcessing

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Your preview arrived incomplete. Please try again."
        case .photoTooLarge: return "Choose a smaller photo to create your page."
        case .stillProcessing: return "Your page is still being prepared. Try again to pick up the same preview."
        }
    }
}


enum OnboardingPreviewErrorPolicy {
    static func message(for error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return error.localizedDescription }
        switch ns.code {
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
