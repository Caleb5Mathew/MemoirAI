import Foundation
import UIKit

actor ImageContext {

    init() {
        print("[ImageContext] init")
    }

    // MODIFICATION 1: Added 'gender' to the function signature
    func faceDescriptor(fileID: String, jpegData: Data? = nil, race: String? = nil, gender: String? = nil) async throws -> String {

        // --- DYNAMIC PROMPT LOGIC (MODIFIED) ---
        // Build a context string from user-provided details
        var contextClauses: [String] = []
        if let userRace = race, !userRace.trimmingCharacters(in: .whitespaces).isEmpty {
            contextClauses.append("is identified as \(userRace)")
        }
        if let userGender = gender, !userGender.trimmingCharacters(in: .whitespaces).isEmpty {
            contextClauses.append("presents as \(userGender)")
        }

        let contextString = contextClauses.isEmpty ? "" : "The main subject \(contextClauses.joined(separator: " and "))."

        let promptText: String
        if !contextClauses.isEmpty {
            // Context was provided. Instruct the AI to use it.
            promptText = """
            For a fictional story, describe this person's physical appearance in ONE short, comma-separated sentence.
            \(contextString)

            Based on the image and this context, detail their gender presentation, prominent facial features, skin tone, and hair.
            Do not use the word "individual". Use a gendered term like "man" or "woman" as appropriate.
            Absolutely NO words or hints about age (e.g. young, old, adult, child).
            """
        } else {
            // No context was provided. Fall back to guessing.
            promptText = """
            For a fictional story, describe this person's physical appearance in ONE short, comma-separated sentence.
            1.  First, identify their apparent gender (e.g. "a man", "a woman"). Do not use the word "individual".
            2.  Then, detail their prominent facial features, skin tone, hair color, and hair texture.
            3.  Based *only* on those visual traits, suggest what geographic regions their ancestry might be associated with.

            Use descriptive and suggestive language for ancestry, but be definitive about the gender presentation.
            Absolutely NO percentages and NO words or hints about age (e.g. young, old, adult, child).
            """
        }
        // --- END OF DYNAMIC PROMPT LOGIC ---

        guard let bytes = jpegData else {
            throw NSError(domain: "MemoirAI",
                          code: -44,
                          userInfo: [NSLocalizedDescriptionKey: "Face descriptor requires JPEG image data"])
        }

        let startedAt = Date()
        let result = try await AIProxyService.shared.chatCompletion(
            model: "gpt-5-mini",
            messages: [["role": "user", "content": promptText]],
            images: [(data: bytes, mimeType: "image/jpeg")],
            temperature: 0.2,
            maxTokens: 100
        )
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .openAI,
                operation: .openAIChat,
                model: "gpt-5-mini",
                statusCode: 200,
                success: true,
                durationMs: Date().timeIntervalSince(startedAt) * 1000,
                promptCharacters: promptText.count,
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens,
                inputImageCount: 1,
                outputImageCount: 0,
                uploadedBytes: bytes.count
            )
        )

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw NSError(domain: "MemoirAI",
                          code: -42,
                          userInfo: [NSLocalizedDescriptionKey: "Vision descriptor empty / bad JSON"])
        }

        let withoutAge = removingAgeMarkers(from: text)
        let final = removingExpressions(from: withoutAge)
        print("✅ Final descriptor:", final)
        return final
    }

    func enrichPrompts(prompts: [ImagePrompt], withPhotos photos: [UIImage]) async throws -> [ImagePrompt] {
        // … your existing enrichment code …
        return prompts
    }
}

private func removingAgeMarkers(from raw: String) -> String {
    let pattern = #"\b(elderly|old|young|teenager|teen|middle[- ]?aged|child|baby|infant|adult|aged|senior|youthful)\b"#
    let cleaned = raw.replacingOccurrences(of: pattern,
                                         with: "",
                                         options: [.regularExpression, .caseInsensitive])
                         .replacingOccurrences(of: #"[, ]{2,}"#,                // collapse doubles
                                         with: ", ",
                                         options: [.regularExpression])
                         .trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespacesAndNewlines))
    return cleaned
}

private func removingExpressions(from raw: String) -> String {
    let expressionPatterns = [
        // Existing patterns - expressions
        #"displaying a \w+ expression"#,
        #"with a \w+ expression"#,
        #"looking \w+"#,  // looking surprised, looking happy
        #"\w+ expression"#,
        #"bright smile"#,
        #"smiling"#,
        #"frowning"#,
        // NEW: Mouth positions (transient states from photo)
        #"mouth open"#,
        #"open mouth"#,
        #"lips parted"#,
        #"mouth closed"#,
        // NEW: Clothing from photo (should use character details instead)
        #"wearing [^,.]+"#,
        #"dressed in [^,.]+"#
    ]
    var cleaned = raw
    for pattern in expressionPatterns {
        cleaned = cleaned.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    // Clean up punctuation artifacts
    cleaned = cleaned.replacingOccurrences(of: #"[, ]{2,}"#, with: ", ", options: .regularExpression)
    return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespacesAndNewlines))
}

struct ImagePrompt: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let referenceImageIDs: [String]
}
