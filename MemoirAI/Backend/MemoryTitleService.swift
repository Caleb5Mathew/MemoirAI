import Foundation

/// Service for generating memory titles using OpenAI
actor MemoryTitleService {
    private let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
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
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Generate a 1-2 word title for this memory:\n\n\(truncatedText)"]
            ],
            "temperature": 0.3,
            "max_tokens": 20
        ]
        
        do {
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let startedAt = Date()
            let (data, response) = try await URLSession.shared.data(for: req)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let usage = DevCostTelemetryService.extractOpenAIUsage(from: data)
            await DevCostTelemetryService.shared.logEvent(
                DevCostEvent(
                    timestamp: Date(),
                    provider: .openAI,
                    operation: .openAIChat,
                    model: "gpt-4o-mini",
                    statusCode: statusCode,
                    success: (200...299).contains(statusCode ?? 0),
                    durationMs: Date().timeIntervalSince(startedAt) * 1000,
                    promptCharacters: truncatedText.count,
                    inputTokens: usage.inputTokens,
                    outputTokens: usage.outputTokens,
                    inputImageCount: 0,
                    outputImageCount: 0,
                    uploadedBytes: 0
                )
            )
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("⚠️ Title generation failed: Invalid response")
                return nil
            }
            
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg
            }
            struct Root: Decodable { let choices: [Choice] }
            
            let decoded = try JSONDecoder().decode(Root.self, from: data)
            guard let title = decoded.choices.first?.message.content else {
                return nil
            }
            
            // Clean up the title - remove quotes and extra whitespace
            let cleanedTitle = title
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









