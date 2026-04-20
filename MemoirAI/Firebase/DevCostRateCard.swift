import Foundation

enum DevCostRateCard {
    // Approximate, configurable rates. Keep centralized for easy updates.
    static let openAIInputPer1M: Double = 0.30
    static let openAIOutputPer1M: Double = 2.50
    static let geminiInputPer1M: Double = 0.30
    static let geminiOutputPer1M: Double = 2.50

    static let fallbackOpenAIImageOutputTokens: Double = 1300
    static let fallbackGeminiImageOutputTokens: Double = 1300

    static func estimate(for event: DevCostEvent) -> DevCostEstimate {
        var base = 0.0
        let promptTokenApprox = max(0, event.promptCharacters / 4)

        switch event.provider {
        case .openAI:
            let inputTokens = max(event.inputTokens, promptTokenApprox)
            let outputTokens: Int
            if event.outputTokens > 0 {
                outputTokens = event.outputTokens
            } else if event.operation == .openAIImage {
                outputTokens = Int(Double(max(1, event.outputImageCount)) * fallbackOpenAIImageOutputTokens)
            } else {
                outputTokens = 0
            }
            base += (Double(inputTokens) / 1_000_000.0) * openAIInputPer1M
            base += (Double(outputTokens) / 1_000_000.0) * openAIOutputPer1M

        case .gemini:
            let inputTokens = max(event.inputTokens, promptTokenApprox + (event.inputImageCount * 1300))
            let outputTokens: Int
            if event.outputTokens > 0 {
                outputTokens = event.outputTokens
            } else {
                outputTokens = Int(Double(max(1, event.outputImageCount)) * fallbackGeminiImageOutputTokens)
            }
            base += (Double(inputTokens) / 1_000_000.0) * geminiInputPer1M
            base += (Double(outputTokens) / 1_000_000.0) * geminiOutputPer1M

        case .firebaseStorage:
            // Approximation: storage + transfer + ops are small per-image at current volume.
            // We model a tiny floor so uploads still show up in telemetry breakdown.
            base += Double(event.uploadedBytes) / 1_000_000_000.0 * 0.026
            base += event.uploadedBytes > 0 ? 0.00001 : 0
        }

        let confidence = confidenceForEvent(event)
        let spread = max(0.05, (1.0 - confidence) * 0.9)
        let low = max(0, base * (1.0 - spread))
        let high = base * (1.0 + spread)
        return DevCostEstimate(low: low, base: base, high: high, confidence: confidence)
    }

    private static func confidenceForEvent(_ event: DevCostEvent) -> Double {
        var confidence = 0.95
        if event.inputTokens == 0 && event.promptCharacters > 0 {
            confidence -= 0.15
        }
        if event.outputTokens == 0 && event.outputImageCount > 0 {
            confidence -= 0.20
        }
        if event.statusCode == nil {
            confidence -= 0.05
        }
        return max(0.50, min(0.99, confidence))
    }
}
