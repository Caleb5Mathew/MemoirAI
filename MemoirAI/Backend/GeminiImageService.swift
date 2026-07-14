import Foundation
import UIKit

actor GeminiImageService {
    enum Model {
        static let gemini3ProPreview = "gemini-3-pro-image-preview"
        static let gemini25FlashImage = "gemini-2.5-flash-image"
    }

    init() {}

    // MARK: - Cover Illustration Generation

    /// Generate style-aware cover illustration art for print cover composition via the `aiGenerateCoverArt` cloud callable.
    /// - Parameters:
    ///   - headshot: When present, used as reference for human likeness; when absent, the server renders a no-people cover.
    ///   - profileName: Display name (fallback segment for default title only).
    ///   - ethnicity / gender: Extra likeness guidance when `headshot` is present (ignored for no-people covers).
    ///   - memoryThemes: Themes from the book's memories (objects, places, motifs — not people when there is no headshot).
    ///   - artStyle: Visual style and composition tone.
    ///   - printTitle: **Rendered inside the image** by the model (exact characters); not overlaid by the app.
    /// - Returns: UIImage of the illustration, or nil on failure
    func generateCoverIllustration(
        headshot: UIImage?,
        profileName: String,
        ethnicity: String? = nil,
        gender: String? = nil,
        memoryThemes: [String] = [],
        artStyle: ArtStyle = .kidsBook,
        customStyle: String? = nil,
        printTitle: String? = nil,
        protagonistCanonLine: String? = nil
    ) async throws -> UIImage? {
        try await AIProxyService.shared.generateCoverArt(
            kind: "front",
            headshot: headshot,
            frontCoverArt: nil,
            profileName: profileName,
            ethnicity: ethnicity,
            gender: gender,
            memoryThemes: memoryThemes,
            artStyle: artStyle.firestoreKey,
            customStyle: customStyle,
            printTitle: printTitle,
            protagonistCanonLine: protagonistCanonLine
        )
    }

    /// Generate a thematically linked back-cover illustration using the front cover as a visual reference, via `aiGenerateCoverArt`.
    /// Artwork only (no readable text); `BookCoverRenderer` draws marketing copy on top.
    func generateBackCoverIllustration(
        frontCoverArt: UIImage,
        headshot: UIImage? = nil,
        profileName: String,
        ethnicity: String? = nil,
        gender: String? = nil,
        memoryThemes: [String] = [],
        artStyle: ArtStyle = .kidsBook,
        customStyle: String? = nil
    ) async throws -> UIImage? {
        try await AIProxyService.shared.generateCoverArt(
            kind: "back",
            headshot: headshot,
            frontCoverArt: frontCoverArt,
            profileName: profileName,
            ethnicity: ethnicity,
            gender: gender,
            memoryThemes: memoryThemes,
            artStyle: artStyle.firestoreKey,
            customStyle: customStyle,
            printTitle: nil,
            protagonistCanonLine: nil
        )
    }

    // MARK: - Back-cover pitch (plain text)

    /// Generates 2–3 sentence back-cover marketing copy. Returns nil on failure; caller should use `CoverCopyPolicy.fallbackBackCoverPitch`.
    func generateBackCoverPitch(prompt: String) async -> String? {
        do {
            let result = try await AIProxyService.shared.chatCompletion(
                provider: "gemini",
                model: "gemini-2.5-flash",
                messages: [["role": "user", "content": prompt]],
                temperature: 0.7,
                maxTokens: 256
            )
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            print("[GeminiImageService WARNING] Back-cover pitch generation failed: \(error)")
            return nil
        }
    }

    // MARK: - Image Editing (Nano Banana with Image Input)

    /// Edit an existing image using Gemini with image input + structured edit instruction (memory/character context + user revision), via `aiEditImage`.
    func editImage(
        image: UIImage,
        styleAnchor: UIImage? = nil,
        editInstruction: String,
        size: String = "1792x1024",
        model: String = Model.gemini3ProPreview
    ) async throws -> UIImage? {
        try await AIProxyService.shared.editImage(
            image: image,
            styleAnchor: styleAnchor,
            editInstruction: editInstruction,
            size: size,
            model: model
        )
    }
}
