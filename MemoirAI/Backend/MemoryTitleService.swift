import Foundation

/// Service for generating memory titles via the `aiChatCompletion` Cloud Function.
actor MemoryTitleService {
    init() {}

    /// Generate a 1-2 word title for a memory based on its text content
    /// - Parameter memoryText: The text content of the memory
    /// - Returns: A short title (1-2 words), or nil if generation fails
    func generateTitle(from memoryText: String) async -> String? {
        guard !memoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // Truncate to first 500 characters to avoid token limits
        let truncatedText = String(memoryText.prefix(500))

        let systemPrompt = """
        You are a helpful assistant that creates concise, meaningful titles for personal memories.
        Generate a title that captures the essence of the memory in just 1-2 words.
        Examples: "Growing Up", "Wedding Day", "First Home", "Family Dinner", "College Friends"
        Return ONLY the title, nothing else. No quotes, no explanation.
        """

        let startedAt = Date()
        do {
            let result = try await AIProxyService.shared.chatCompletion(
                model: "gpt-5-mini",
                messages: [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": "Generate a 1-2 word title for this memory:\n\n\(truncatedText)"]
                ],
                temperature: 0.3,
                maxTokens: 20
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
                    promptCharacters: truncatedText.count,
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens,
                    inputImageCount: 0,
                    outputImageCount: 0,
                    uploadedBytes: 0
                )
            )

            // Clean up the title - remove quotes and extra whitespace
            let cleanedTitle = result.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")

            // Ensure it's not empty and not too long (safety check)
            guard !cleanedTitle.isEmpty, cleanedTitle.count <= 50 else {
                return nil
            }

            print("✅ Generated title: '\(cleanedTitle)'")
            return cleanedTitle

        } catch {
            print("⚠️ Title generation error: \(error.localizedDescription)")
            return nil
        }
    }
}
