import Foundation
import FirebaseAuth
import FirebaseFunctions
import UIKit

/// Result of a chat completion request via the `aiChatCompletion` callable.
struct ChatResult {
    let text: String
    let inputTokens: Int
    let outputTokens: Int
}

/// User-facing errors surfaced by `AIProxyService` callable requests.
enum AIProxyError: LocalizedError {
    case notAuthenticated
    case badResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use AI features."
        case .badResponse:
            return "Invalid response from server."
        case .serverError(let message):
            return message
        }
    }
}

/// Wraps the `aiChatCompletion`, `aiGenerateCoverArt`, and `aiEditImage` Firebase callables.
/// All client-side OpenAI/Gemini API keys have been removed — every AI request now
/// routes through Cloud Functions so keys never ship in the app bundle.
actor AIProxyService {
    static let shared = AIProxyService()

    private init() {}

    /// Sends a chat/completion request to the `aiChatCompletion` callable.
    /// - Parameters:
    ///   - images: Optional images attached to the request; caller supplies raw bytes + mime type.
    ///   - jsonMode: When true, requests `responseFormat: "json"` so the model returns raw JSON text.
    func chatCompletion(
        provider: String = "openai",
        model: String,
        messages: [[String: String]],
        images: [(data: Data, mimeType: String)] = [],
        temperature: Double = 0.2,
        maxTokens: Int = 300,
        jsonMode: Bool = false
    ) async throws -> ChatResult {
        guard Auth.auth().currentUser != nil else {
            throw AIProxyError.notAuthenticated
        }

        var data: [String: Any] = [
            "provider": provider,
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "maxTokens": maxTokens
        ]
        if !images.isEmpty {
            data["images"] = images.map { image in
                ["base64": image.data.base64EncodedString(), "mimeType": image.mimeType]
            }
        }
        if jsonMode {
            data["responseFormat"] = "json"
        }

        let callable = Functions.functions().httpsCallable("aiChatCompletion")
        callable.timeoutInterval = 60

        do {
            let result = try await callable.call(data)
            guard let dict = result.data as? [String: Any],
                  let text = dict["text"] as? String else {
                throw AIProxyError.badResponse
            }
            let usage = dict["usage"] as? [String: Any]
            let inputTokens = (usage?["inputTokens"] as? Int) ?? (usage?["inputTokens"] as? NSNumber)?.intValue ?? 0
            let outputTokens = (usage?["outputTokens"] as? Int) ?? (usage?["outputTokens"] as? NSNumber)?.intValue ?? 0
            return ChatResult(text: text, inputTokens: inputTokens, outputTokens: outputTokens)
        } catch {
            throw Self.mapCallableError(error)
        }
    }

    /// Generates front/back cover art via the `aiGenerateCoverArt` callable, then downloads the resulting image.
    func generateCoverArt(
        kind: String,
        headshot: UIImage?,
        frontCoverArt: UIImage?,
        profileName: String,
        ethnicity: String? = nil,
        gender: String? = nil,
        memoryThemes: [String] = [],
        artStyle: String? = nil,
        customStyle: String? = nil,
        printTitle: String? = nil,
        protagonistCanonLine: String? = nil
    ) async throws -> UIImage? {
        guard Auth.auth().currentUser != nil else {
            throw AIProxyError.notAuthenticated
        }

        var data: [String: Any] = [
            "kind": kind,
            "profileName": profileName
        ]
        if let headshotData = headshot?.jpegData(compressionQuality: 0.85) {
            data["headshotBase64"] = headshotData.base64EncodedString()
        }
        if let frontCoverArtData = frontCoverArt?.jpegData(compressionQuality: 0.85) {
            data["frontCoverArtBase64"] = frontCoverArtData.base64EncodedString()
        }
        if let ethnicity, !ethnicity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["ethnicity"] = ethnicity
        }
        if let gender, !gender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["gender"] = gender
        }
        if !memoryThemes.isEmpty {
            data["memoryThemes"] = memoryThemes
        }
        if let artStyle, !artStyle.isEmpty {
            data["artStyle"] = artStyle
        }
        if let customStyle, !customStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["customStyle"] = customStyle
        }
        if let printTitle, !printTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["printTitle"] = printTitle
        }
        if let protagonistCanonLine, !protagonistCanonLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["protagonistCanonLine"] = protagonistCanonLine
        }

        let callable = Functions.functions().httpsCallable("aiGenerateCoverArt")
        callable.timeoutInterval = 300

        do {
            let result = try await callable.call(data)
            guard let dict = result.data as? [String: Any],
                  let urlString = dict["url"] as? String,
                  let url = URL(string: urlString) else {
                throw AIProxyError.badResponse
            }
            return try await Self.downloadImage(from: url)
        } catch {
            throw Self.mapCallableError(error)
        }
    }

    /// Edits an image via the `aiEditImage` callable, then downloads the resulting image.
    func editImage(
        image: UIImage,
        styleAnchor: UIImage?,
        editInstruction: String,
        size: String = "1792x1024",
        model: String
    ) async throws -> UIImage? {
        guard Auth.auth().currentUser != nil else {
            throw AIProxyError.notAuthenticated
        }
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw AIProxyError.badResponse
        }

        var data: [String: Any] = [
            "imageBase64": imageData.base64EncodedString(),
            "editInstruction": editInstruction,
            "size": size,
            "model": model
        ]
        if let styleAnchorData = styleAnchor?.jpegData(compressionQuality: 0.88) {
            data["styleAnchorBase64"] = styleAnchorData.base64EncodedString()
        }

        let callable = Functions.functions().httpsCallable("aiEditImage")
        callable.timeoutInterval = 240

        do {
            let result = try await callable.call(data)
            guard let dict = result.data as? [String: Any],
                  let urlString = dict["url"] as? String,
                  let url = URL(string: urlString) else {
                throw AIProxyError.badResponse
            }
            return try await Self.downloadImage(from: url)
        } catch {
            throw Self.mapCallableError(error)
        }
    }

    private static func downloadImage(from url: URL) async throws -> UIImage? {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AIProxyError.badResponse
        }
        return UIImage(data: data)
    }

    private static func mapCallableError(_ error: Error) -> Error {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return error }
        return AIProxyError.serverError(OrderService.userFacingCallableErrorMessage(error))
    }
}
