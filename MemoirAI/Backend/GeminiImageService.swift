import Foundation
import UIKit

actor GeminiImageService {
    enum Model {
        static let gemini3ProPreview = "gemini-3-pro-image-preview"
        static let gemini25FlashImage = "gemini-2.5-flash-image"
    }

    let apiKey: String
    let session: URLSession

    private static let supportedAspectRatios: [String] = [
        "1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"
    ]
    
    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
        print("[GeminiImageService DEBUG] booted – key prefix: \(apiKey.prefix(5))…")
    }
    
    // MARK: - Step 1: The "Brain" (Prompt Optimization)
    
    func optimizePrompt(_ strictPrompt: String) async throws -> String {
        let startedAt = Date()
        var statusCode: Int?
        print("[GeminiImageService DEBUG] Optimizing prompt with Gemini 2.0 Flash Exp...")
        
        // Use gemini-2.0-flash-exp which is the latest available model
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return strictPrompt }
        
        let systemInstruction = """
        You are an expert AI Image Prompt Engineer.
        Your task is to convert the provided Structured Prompt into a **natural, fluid visual description** optimized for the Imagen 3 / Gemini Image Generation model.
        
        CRITICAL RULES:
        1. **INTEGRATE CHARACTERS:** Do not list characters (e.g. "Character 1: ..."). Instead, describe them naturally in the scene (e.g. "To the left, Caleb, a man with warm brown skin..., stands smiling.").
        2. **PRESERVE DETAILS:** You MUST keep every physical detail (hair, skin, clothes) EXACTLY as described. Do not change or omit them.
        3. **NO HALLUCINATIONS:** Do not add new objects, people, or major actions not present in the original scene description.
        4. **STYLE:** Incorporate the style instruction naturally into the description of the mood and rendering (e.g. "Rendered in a soft watercolor style...").
        
        Output ONLY the final prompt. No "Here is the prompt" or other text.
        """
        
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": systemInstruction + "\n\nSTRUCTURED PROMPT:\n" + strictPrompt]
                    ]
                ]
            ]
        ]
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, resp) = try await session.data(for: req)
            
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                statusCode = http.statusCode
                let errorRaw = String(data: data, encoding: .utf8) ?? ""
                print("[GeminiImageService WARNING] Optimization failed HTTP \(http.statusCode): \(errorRaw)")
                await DevCostTelemetryService.shared.logEvent(
                    DevCostEvent(
                        timestamp: Date(),
                        provider: .gemini,
                        operation: .geminiOptimize,
                        model: "gemini-2.0-flash-exp",
                        statusCode: http.statusCode,
                        success: false,
                        durationMs: Date().timeIntervalSince(startedAt) * 1000,
                        promptCharacters: strictPrompt.count,
                        inputTokens: 0,
                        outputTokens: 0,
                        inputImageCount: 0,
                        outputImageCount: 0,
                        uploadedBytes: 0
                    )
                )
                return strictPrompt
            }
            
            struct TextResponse: Decodable {
                struct Candidate: Decodable {
                    struct Content: Decodable {
                        struct Part: Decodable { let text: String? }
                        let parts: [Part]
                    }
                    let content: Content
                }
                let candidates: [Candidate]?
            }
            
            if let decoded = try? JSONDecoder().decode(TextResponse.self, from: data),
               let text = decoded.candidates?.first?.content.parts.first?.text {
                let optimized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[GeminiImageService DEBUG] Optimized prompt (\(optimized.count) chars)")
                await DevCostTelemetryService.shared.logEvent(
                    DevCostEvent(
                        timestamp: Date(),
                        provider: .gemini,
                        operation: .geminiOptimize,
                        model: "gemini-2.0-flash-exp",
                        statusCode: 200,
                        success: true,
                        durationMs: Date().timeIntervalSince(startedAt) * 1000,
                        promptCharacters: strictPrompt.count,
                        inputTokens: 0,
                        outputTokens: 0,
                        inputImageCount: 0,
                        outputImageCount: 0,
                        uploadedBytes: 0
                    )
                )
                return optimized
            }
        } catch {
            print("[GeminiImageService WARNING] Optimization error: \(error)")
            await DevCostTelemetryService.shared.logEvent(
                DevCostEvent(
                    timestamp: Date(),
                    provider: .gemini,
                    operation: .geminiOptimize,
                    model: "gemini-2.0-flash-exp",
                    statusCode: statusCode,
                    success: false,
                    durationMs: Date().timeIntervalSince(startedAt) * 1000,
                    promptCharacters: strictPrompt.count,
                    inputTokens: 0,
                    outputTokens: 0,
                    inputImageCount: 0,
                    outputImageCount: 0,
                    uploadedBytes: 0
                )
            )
        }
        
        return strictPrompt
    }

    private func aspectRatio(from size: String) -> String {
        let trimmed = size.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.supportedAspectRatios.contains(trimmed) {
            return trimmed
        }

        if trimmed == "1792x1024" {
            return "16:9"
        }
        if trimmed == "1024x1792" {
            return "9:16"
        }

        let cleaned = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
        let separators = ["x", ":"]
        for separator in separators {
            let parts = cleaned.split(separator: Character(separator), maxSplits: 1).map(String.init)
            if parts.count == 2,
               let first = Double(parts[0]),
               let second = Double(parts[1]),
               first > 0,
               second > 0 {
                let ratio = first / second
                let closest = Self.supportedAspectRatios.min { lhs, rhs in
                    func delta(_ aspect: String) -> Double {
                        let tokens = aspect.split(separator: ":").map(String.init)
                        guard tokens.count == 2,
                              let w = Double(tokens[0]),
                              let h = Double(tokens[1]),
                              h > 0 else { return .greatestFiniteMagnitude }
                        return abs((w / h) - ratio)
                    }
                    return delta(lhs) < delta(rhs)
                }
                return closest ?? "1:1"
            }
        }

        return "1:1"
    }
    
    // MARK: - Step 2: Image Generation (Nano Banana)
    
    /// Generate image using Gemini 2.5 Flash Image (Nano Banana)
    /// - Parameter allowTextInImage: When true, skip the anti-text guardrail (e.g. for cover title text)
    func generateImage(
        prompt: String,
        size: String = "1792x1024",
        model: String = Model.gemini3ProPreview,
        referenceImages: [UIImage] = [],
        allowTextInImage: Bool = false
    ) async throws -> UIImage? {
        let startedAt = Date()
        var statusCode: Int?
        let antiTextGuardrail = "Do not include any words, letters, numbers, captions, signs, logos, or typographic marks in the image."
        let lowerPrompt = prompt.lowercased()
        let promptForGeneration: String
        if allowTextInImage
            || lowerPrompt.contains("do not include any words")
            || lowerPrompt.contains("do not render any words")
            || lowerPrompt.contains("no text")
            || lowerPrompt.contains("do not include text")
            || lowerPrompt.contains("text rendering rule") {
            promptForGeneration = prompt
        } else {
            promptForGeneration = "\(prompt)\n\n\(antiTextGuardrail)"
            print("[GeminiImageService DEBUG] Applied anti-text guardrail clause to prompt.")
        }

        print("[GeminiImageService DEBUG] === GEMINI IMAGE GENERATION REQUEST ===")
        print("[GeminiImageService DEBUG] Model: \(model)")
        print("[GeminiImageService DEBUG] Prompt length: \(promptForGeneration.count) characters")
        print("[GeminiImageService DEBUG] Reference images attached: \(referenceImages.count)")

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Convert input size or ratio to a supported Gemini aspect ratio.
        let aspectRatio = aspectRatio(from: size)
        
        // Build content parts from optional image references + text prompt
        var parts: [[String: Any]] = []
        for image in referenceImages {
            if let imageData = image.jpegData(compressionQuality: 0.9) {
                parts.append([
                    "inline_data": [
                        "mime_type": "image/jpeg",
                        "data": imageData.base64EncodedString()
                    ]
                ])
            }
        }
        parts.append(["text": promptForGeneration])

        // Gemini image payload format
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": parts
                ]
            ],
            "generationConfig": [
                "responseModalities": ["IMAGE"],
                "imageConfig": [
                    "aspectRatio": aspectRatio
                ]
            ]
        ]
        
        // Log request
        if let jsonData = try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("[GeminiImageService DEBUG] Request body preview (first 200 chars): \(jsonString.prefix(200))...")
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 180.0
        
        let (data, resp) = try await session.data(for: req)
        
        if let http = resp as? HTTPURLResponse {
            print("[GeminiImageService DEBUG] HTTP status: \(http.statusCode)")
            statusCode = http.statusCode
            if http.statusCode != 200 {
                let errorRaw = String(data: data, encoding: .utf8) ?? ""
                print("[GeminiImageService ERROR] API Error Body: \(errorRaw)")
                await DevCostTelemetryService.shared.logEvent(
                    DevCostEvent(
                        timestamp: Date(),
                        provider: .gemini,
                        operation: .geminiGenerate,
                        model: model,
                        statusCode: http.statusCode,
                        success: false,
                        durationMs: Date().timeIntervalSince(startedAt) * 1000,
                        promptCharacters: promptForGeneration.count,
                        inputTokens: 0,
                        outputTokens: 0,
                        inputImageCount: referenceImages.count,
                        outputImageCount: 0,
                        uploadedBytes: 0
                    )
                )
                return nil
            }
        }
        
        // Decode Gemini response format
        struct Response: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let inlineData: InlineData?
                        let text: String?
                    }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]?
        }
        
        struct InlineData: Decodable {
            let mimeType: String
            let data: String // base64 encoded image
        }
        
        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            
            // Extract image from response
            if let candidates = decoded.candidates {
                for candidate in candidates {
                    for part in candidate.content.parts {
                        // Check for inline base64 image data
                        if let inlineData = part.inlineData,
                           inlineData.mimeType.hasPrefix("image/"),
                           let imageData = Data(base64Encoded: inlineData.data),
                           let image = UIImage(data: imageData) {
                            print("[GeminiImageService DEBUG] ✅ Successfully decoded Nano Banana image")
                            await DevCostTelemetryService.shared.logEvent(
                                DevCostEvent(
                                    timestamp: Date(),
                                    provider: .gemini,
                                    operation: .geminiGenerate,
                                    model: model,
                                    statusCode: statusCode ?? 200,
                                    success: true,
                                    durationMs: Date().timeIntervalSince(startedAt) * 1000,
                                    promptCharacters: promptForGeneration.count,
                                    inputTokens: 0,
                                    outputTokens: 0,
                                    inputImageCount: referenceImages.count,
                                    outputImageCount: 1,
                                    uploadedBytes: 0
                                )
                            )
                            return image
                        }
                    }
                }
            }
        } catch {
            print("[GeminiImageService ERROR] Failed to decode image: \(error)")
        }
        
        print("[GeminiImageService WARNING] No image found in response")
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .gemini,
                operation: .geminiGenerate,
                model: model,
                statusCode: statusCode,
                success: false,
                durationMs: Date().timeIntervalSince(startedAt) * 1000,
                promptCharacters: promptForGeneration.count,
                inputTokens: 0,
                outputTokens: 0,
                inputImageCount: referenceImages.count,
                outputImageCount: 0,
                uploadedBytes: 0
            )
        )
        return nil
    }
    
    // MARK: - Cover Illustration Generation

    /// Generate style-aware cover illustration art for print cover composition.
    /// - Parameters:
    ///   - headshot: When present, used as reference for human likeness; when absent, **no people** may appear in the art.
    ///   - profileName: Display name (fallback segment for default title only).
    ///   - ethnicity / gender: Extra likeness guidance when `headshot` is present (ignored for no-people covers).
    ///   - memoryThemes: Themes from the book’s memories (objects, places, motifs — not people when there is no headshot).
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
        printTitle: String? = nil
    ) async throws -> UIImage? {
        let trimmedThemes = memoryThemes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let topThemes = Array(trimmedThemes.prefix(3))
        let themeGuidance: String = {
            guard !topThemes.isEmpty else {
                return "Use a single strong focal idea with at most one subtle supporting motif."
            }
            return "Weave these recurring motifs into the scene (as settings, objects, weather, or symbolism — not as a list): \(topThemes.joined(separator: ", ")). One primary focal idea only; avoid collage or crowded montages."
        }()

        let resolvedTitle: String = {
            let t = printTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty { return t }
            let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Memoir" : "\(name)'s Memoir"
        }()

        /// Delimit title so punctuation/apostrophes survive verbatim instructions.
        let quotedTitle = "⟨\(resolvedTitle)⟩"

        let styleParagraph = artStyle.memoryIllustrationStyleDescription(customText: customStyle)
        let stylePreamble = """
        VISUAL STYLE (high priority, must follow):
        \(styleParagraph)

        \(ArtStyle.coverStyleBindingInstruction)
        """

        let prompt: String
        if headshot != nil {
            var identityLines: [String] = [
                "Include exactly one adult human narrator as the clear focal subject.",
                "Use the reference photo to preserve facial likeness, age cues, and recognizable features.",
                "Clothing and pose may be illustrative; the face must read as the same person as the reference."
            ]
            if let e = ethnicity?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
                identityLines.append("Ethnicity / heritage (for skin tone and features): \(e).")
            }
            if let g = gender?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
                identityLines.append("Gender presentation: \(g).")
            }
            let identityBlock = identityLines.joined(separator: "\n")

            prompt = """
            BOOK COVER ILLUSTRATION — full bleed, print ready.

            \(stylePreamble)

            TYPOGRAPHY (mandatory):
            • Paint or hand-letter the book title **inside the artwork** so it reads as part of the illustration (not a separate system font overlay).
            • The title must use **exactly** these characters, in this order, including spaces and punctuation: \(quotedTitle)
            • Do not substitute synonyms, fix spelling, change capitalization, add subtitles, or omit apostrophes.
            • Place the title in the **lower third**, large and legible; keep the area behind the letters relatively simple (low clutter) so the words read at small thumbnail size.
            • No other legible words, stray letters, captions, logos, barcodes, or watermarks anywhere on the cover.

            SUBJECT / LIKENESS:
            \(identityBlock)

            THEME:
            \(themeGuidance)

            COMPOSITION:
            • One clear focal subject; calm, jacket-worthy negative space.
            • Avoid clutter behind the title strokes; no fake “author name” lines unless they are unreadable texture only.

            STYLE REMINDER (must follow):
            \(styleParagraph)
            """
        } else {
            prompt = """
            BOOK COVER ILLUSTRATION — full bleed, print ready.

            \(stylePreamble)

            TYPOGRAPHY (mandatory):
            • Paint or hand-letter the book title **inside the artwork** as integrated art (not a system-font overlay).
            • The title must use **exactly** these characters, in this order, including spaces and punctuation: \(quotedTitle)
            • Do not substitute synonyms, change casing, or add other readable words, slogans, logos, or captions.
            • Place the title in the **lower third**, large and legible; simplify the background behind the lettering.

            NO-HUMANS RULE (strict):
            • Do not depict **any** humans, human faces, silhouettes, body parts, crowds, mannequins, statues that read as specific people, or reflections that show people.
            • Symbolize people only through objects, places, light, nature, doors, chairs, photographs-without-clear-faces, etc.
            • No anthropomorphic animals wearing “character” faces if it reads like a person.

            THEME / SETTING (non-figurative):
            \(themeGuidance)

            COMPOSITION:
            • Evocative, memoir-appropriate environment or symbolic still-life; one visual idea, uncluttered, professional dust-jacket quality.

            STYLE REMINDER (must follow):
            \(styleParagraph)
            """
        }

        return try await generateImage(
            prompt: prompt,
            size: "5:4",
            model: Model.gemini3ProPreview,
            referenceImages: headshot.map { [$0] } ?? [],
            allowTextInImage: true
        )
    }

    /// Generate a thematically linked back-cover illustration using the front cover as a visual reference.
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
        let trimmedThemes = memoryThemes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let topThemes = Array(trimmedThemes.prefix(4))
        let styleParagraph = artStyle.memoryIllustrationStyleDescription(customText: customStyle)
        let stylePreamble = """
        VISUAL STYLE (high priority, must follow):
        \(styleParagraph)

        \(ArtStyle.coverStyleBindingInstruction)
        """

        let themeGuidance: String = {
            guard !topThemes.isEmpty else {
                return "Use one coherent environmental motif that feels emotionally connected to the front cover."
            }
            return "Carry forward these memoir motifs while introducing fresh details: \(topThemes.joined(separator: ", ")). Keep one clear visual idea."
        }()

        let identityGuidance: String = {
            guard headshot != nil else {
                return """
                If people appear, keep them distant, silhouette-level, or implied through objects and setting. Do not show clear readable faces.
                """
            }
            var lines: [String] = [
                "If a person appears, preserve continuity with the front cover subject identity and age cues from references.",
                "This is a back-cover support scene: avoid close-up portraits; keep character presence secondary to environment."
            ]
            if let e = ethnicity?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
                lines.append("Maintain coherent ethnicity cues: \(e).")
            }
            if let g = gender?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
                lines.append("Maintain coherent gender presentation: \(g).")
            }
            return lines.joined(separator: "\n")
        }()

        let prompt = """
        BACK COVER ILLUSTRATION — full bleed, print ready.

        \(stylePreamble)

        CONTINUITY:
        • The first reference image is the FRONT COVER art. Match its world, palette temperature, lighting logic, era, and emotional tone.
        • Create a complementary continuation scene (same story universe), not a duplicate of the front.
        • Add at least one new narrative detail that was not dominant on the front cover.

        TEXT SAFETY (strict):
        • No readable words, letters, logos, signage, watermarks, or captions anywhere.
        • Keep the upper-left back-panel area visually calmer (lower contrast, less clutter) so overlay copy remains readable.

        THEME:
        \(themeGuidance)

        SUBJECT RULES:
        \(identityGuidance)

        COMPOSITION:
        • Professional dust-jacket quality, uncluttered, cohesive with front cover.
        • Favor broad shapes and gentle gradients where back-cover marketing text would typically sit.

        STYLE REMINDER (must follow):
        \(styleParagraph)
        """

        var references: [UIImage] = [frontCoverArt]
        if let headshot {
            references.append(headshot)
        }

        return try await generateImage(
            prompt: prompt,
            size: "5:4",
            model: Model.gemini3ProPreview,
            referenceImages: references,
            allowTextInImage: false
        )
    }

    // MARK: - Back-cover pitch (plain text)

    /// Generates 2–3 sentence back-cover marketing copy. Returns nil on failure; caller should use `CoverCopyPolicy.fallbackBackCoverPitch`.
    func generateBackCoverPitch(prompt: String) async -> String? {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return nil }

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 256
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            struct TextResponse: Decodable {
                struct Candidate: Decodable {
                    struct Content: Decodable {
                        struct Part: Decodable { let text: String? }
                        let parts: [Part]
                    }
                    let content: Content
                }
                let candidates: [Candidate]?
            }
            if let decoded = try? JSONDecoder().decode(TextResponse.self, from: data),
               let text = decoded.candidates?.first?.content.parts.first?.text {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        } catch {
            print("[GeminiImageService WARNING] Back-cover pitch generation failed: \(error)")
        }
        return nil
    }

    // MARK: - Step 3: Image Editing (Nano Banana with Image Input)
    
    /// Edit an existing image using Gemini with image input + structured edit instruction (memory/character context + user revision).
    func editImage(
        image: UIImage,
        editInstruction: String,
        size: String = "1792x1024",
        model: String = Model.gemini3ProPreview
    ) async throws -> UIImage? {
        let startedAt = Date()
        var statusCode: Int?
        print("[GeminiImageService DEBUG] === GEMINI IMAGE EDIT REQUEST ===")
        print("[GeminiImageService DEBUG] Model: \(model)")
        print("[GeminiImageService DEBUG] Edit instruction chars: \(editInstruction.count)")
        print("[GeminiImageService DEBUG] Edit instruction (preview): \(String(editInstruction.prefix(400)))…")

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Gemini", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "Gemini", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }
        let base64Image = imageData.base64EncodedString()
        
        // Convert input size or ratio to a supported Gemini aspect ratio.
        let aspectRatio = aspectRatio(from: size)
        
        // Full instruction is assembled by StoryPageViewModel (memory + characters + revision).
        let fullPrompt = """
        The first part of this request includes an INPUT IMAGE (inline image data). Edit that image according to the instructions below.
        
        \(editInstruction)
        """
        
        // Gemini payload with image input
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        ["text": fullPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "responseModalities": ["IMAGE"],
                "imageConfig": [
                    "aspectRatio": aspectRatio
                ]
            ]
        ]
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 180.0
        
        let (data, resp) = try await session.data(for: req)
        
        if let http = resp as? HTTPURLResponse {
            print("[GeminiImageService DEBUG] HTTP status: \(http.statusCode)")
            statusCode = http.statusCode
            if http.statusCode != 200 {
                let errorRaw = String(data: data, encoding: .utf8) ?? ""
                print("[GeminiImageService ERROR] API Error Body: \(errorRaw)")
                await DevCostTelemetryService.shared.logEvent(
                    DevCostEvent(
                        timestamp: Date(),
                        provider: .gemini,
                        operation: .geminiEdit,
                        model: model,
                        statusCode: http.statusCode,
                        success: false,
                        durationMs: Date().timeIntervalSince(startedAt) * 1000,
                        promptCharacters: editInstruction.count,
                        inputTokens: 0,
                        outputTokens: 0,
                        inputImageCount: 1,
                        outputImageCount: 0,
                        uploadedBytes: imageData.count
                    )
                )
                return nil
            }
        }
        
        // Decode Gemini response format (same as generateImage)
        struct Response: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let inlineData: InlineData?
                        let text: String?
                    }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]?
        }
        
        struct InlineData: Decodable {
            let mimeType: String
            let data: String // base64 encoded image
        }
        
        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            
            // Extract image from response
            if let candidates = decoded.candidates {
                for candidate in candidates {
                    for part in candidate.content.parts {
                        // Check for inline base64 image data
                        if let inlineData = part.inlineData,
                           inlineData.mimeType.hasPrefix("image/"),
                           let imageData = Data(base64Encoded: inlineData.data),
                           let editedImage = UIImage(data: imageData) {
                            print("[GeminiImageService DEBUG] ✅ Successfully decoded edited image")
                            await DevCostTelemetryService.shared.logEvent(
                                DevCostEvent(
                                    timestamp: Date(),
                                    provider: .gemini,
                                    operation: .geminiEdit,
                                    model: model,
                                    statusCode: statusCode ?? 200,
                                    success: true,
                                    durationMs: Date().timeIntervalSince(startedAt) * 1000,
                                    promptCharacters: editInstruction.count,
                                    inputTokens: 0,
                                    outputTokens: 0,
                                    inputImageCount: 1,
                                    outputImageCount: 1,
                                    uploadedBytes: imageData.count
                                )
                            )
                            return editedImage
                        }
                    }
                }
            }
        } catch {
            print("[GeminiImageService ERROR] Failed to decode edited image: \(error)")
        }
        
        print("[GeminiImageService WARNING] No edited image found in response")
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .gemini,
                operation: .geminiEdit,
                model: model,
                statusCode: statusCode,
                success: false,
                durationMs: Date().timeIntervalSince(startedAt) * 1000,
                promptCharacters: editInstruction.count,
                inputTokens: 0,
                outputTokens: 0,
                inputImageCount: 1,
                outputImageCount: 0,
                uploadedBytes: imageData.count
            )
        )
        return nil
    }
}
