
//  PromptGenerator.swift
//  MemoirAI
//
//  Created by user941803 on 5/9/25.
//  Re-built 21-May-2025 — cleaned Kid-Book clamp, safer range() usage,
//  and shorter API body construction.
//  Added automatic line-wrapping for page text.

import Foundation

/// One page worth of assets returned to SwiftUI.
struct StoryPageContent: Identifiable {
    let id = UUID()
    let imagePromptText: String   // final text sent to DALL·E
    let pageDisplayText: String   // verse or caption overlay, with embedded line breaks
}

/// Generates prompt blocks by calling the Chat Completions API, then
/// splits them with robust delimiter parsing.
actor PromptGenerator {

    private let apiKey: String
    private let session: URLSession

    // delimiter tokens — must match PromptTemplates output exactly
    private let ipStartTag = "IMAGE_PROMPT_START"
    private let ipEndTag   = "IMAGE_PROMPT_END"
    private let ptStartTag = "PAGE_TEXT_START"
    private let ptEndTag   = "PAGE_TEXT_END"
    private let dividerTag = "---SCENE_DIVIDER---"

    // Kid-Book guardrails - REMOVED LIMIT to prevent truncation
    // DALL-E 3 supports up to 4000 chars, so no need to truncate at 800
    private let kidsBookMax = 4000  // Raised to DALL-E 3's max to prevent truncation
    private let fluffWords: [String] = [
    ]

    init(apiKey: String, session: URLSession = .shared) {
        guard apiKey.hasPrefix("sk-") else {
            fatalError("🔑 Invalid OpenAI key provided to PromptGenerator")
        }
        self.apiKey  = apiKey
        self.session = session
        print("[PromptGenerator] API key OK, prefix \(apiKey.prefix(5))…")
    }

    /// Public entry: given a transcript and desired page count, returns
    /// up to `n` StoryPageContent items.
    func generatePrompts(from transcript: String,
                         pageCount n: Int,
                         chosenArtStyle: ArtStyle,
                         customArtStyleDetails: String?) async throws -> [StoryPageContent] {

        // 1. build messages
        let sys = PromptTemplates.systemPrompt(for: chosenArtStyle,
                                               customArtStyleDetails: customArtStyleDetails)
        let usr = PromptTemplates.userMessage(transcript: transcript,
                                              pageCount: n)

        // 2. call Chat API (stream=false)
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": sys],
                ["role": "user",   "content": usr]
            ],
            "temperature": 0.2 // Low temperature to prevent inventing details - stick to transcript only
        ]

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[PromptGenerator] 🔍 Sending ChatCompletions request…")
        let startedAt = Date()
        let (data, resp) = try await session.data(for: req)
        let statusCode = (resp as? HTTPURLResponse)?.statusCode
        await DevCostTelemetryService.shared.logEvent(
            DevCostEvent(
                timestamp: Date(),
                provider: .openAI,
                operation: .openAIChat,
                model: "gpt-4o",
                statusCode: statusCode,
                success: statusCode == 200,
                durationMs: Date().timeIntervalSince(startedAt) * 1000,
                promptCharacters: transcript.count,
                inputTokens: DevCostTelemetryService.extractOpenAIUsage(from: data).inputTokens,
                outputTokens: DevCostTelemetryService.extractOpenAIUsage(from: data).outputTokens,
                inputImageCount: 0,
                outputImageCount: 0,
                uploadedBytes: 0
            )
        )
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "(binary)"
            throw NSError(domain: "OpenAI", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Chat API failed", "body": raw])
        }

        // 3. decode JSON → rawContent
        struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
        struct Root: Decodable { let choices: [Choice] }
        let raw = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content ?? ""
        guard !raw.isEmpty else { return [] }

        // 4. split blocks & extract
        var pages: [StoryPageContent] = []
        for block in raw.components(separatedBy: dividerTag) {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // find ranges safely (Swift 5 signature: of:options:range:locale:)
            guard
                let ipStart = trimmed.range(of: ipStartTag),
                let ipEnd   = trimmed.range(of: ipEndTag,  options: [], range: ipStart.upperBound..<trimmed.endIndex),
                let ptStart = trimmed.range(of: ptStartTag, options: [], range: ipEnd.upperBound..<trimmed.endIndex),
                let ptEnd   = trimmed.range(of: ptEndTag,  options: [], range: ptStart.upperBound..<trimmed.endIndex)
            else {
                print("[PromptGenerator] ⚠️ delimiter mismatch, skipping block")
                continue
            }

            // Extract raw image prompt & page text - SAFE VERSION
            guard ipStart.upperBound <= ipEnd.lowerBound,
                  ptStart.upperBound <= ptEnd.lowerBound,
                  ipStart.upperBound >= trimmed.startIndex,
                  ipEnd.lowerBound <= trimmed.endIndex,
                  ptStart.upperBound >= trimmed.startIndex,
                  ptEnd.lowerBound <= trimmed.endIndex else {
                print("[PromptGenerator] ⚠️ Invalid string ranges, skipping block")
                continue
            }
            
            var img = String(trimmed[ipStart.upperBound..<ipEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawTxt = String(trimmed[ptStart.upperBound..<ptEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Kid-Book: drop fluff & clamp length
            if chosenArtStyle == .kidsBook {
                img = cleanedKidBookPrompt(img)
            }

            // Wrap the page text to insert real line breaks (~35 chars per line)
            let wrapped = wrap(rawTxt, maxChars: 35)

            pages.append(
                StoryPageContent(
                    imagePromptText: img,
                    pageDisplayText: wrapped
                )
            )
        }

        return Array(pages.prefix(n))
    }


    private func cleanedKidBookPrompt(_ raw: String) -> String {
        // 1. drop lines containing black-listed words
        let filtered = raw
            .components(separatedBy: .newlines)
            .filter { line in
                !fluffWords.contains { line.lowercased().contains($0) }
            }
            .joined(separator: " ")
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. NO TRUNCATION - DALL-E 3 supports up to 4000 chars, and we need the full narrative
        // The final prompt will be assembled as characterEnforcement + sanitizedImagePrompt,
        // so we need to preserve the full narrative here. Truncation will be handled at the
        // final assembly stage if needed (but DALL-E 3's 4000 char limit should be enough).
        return filtered
    }


    /// Inserts "\n" into `text` so that no line exceeds `maxChars` (splitting on spaces).
    private func wrap(_ text: String, maxChars: Int) -> String {
        var result = ""
        var line = ""
        for word in text.split(separator: " ") {
            let part = String(word)
            if line.count + part.count + 1 > maxChars {
                result += line + "\n"
                line = part
            } else {
                line += (line.isEmpty ? "" : " ") + part
            }
        }
        // append any remaining words
        if !line.isEmpty {
            result += line
        }
        return result
    }
}
