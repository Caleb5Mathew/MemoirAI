import Foundation
import FirebaseFirestore

enum DevCostProvider: String, CaseIterable, Codable {
    case openAI = "openai"
    case gemini = "gemini"
    case firebaseStorage = "firebase_storage"
}

enum DevCostOperation: String, CaseIterable, Codable {
    case openAIChat = "openai_chat"
    case openAIImage = "openai_image"
    case openAIFileUpload = "openai_file_upload"
    case geminiGenerate = "gemini_generate"
    case geminiEdit = "gemini_edit"
    case geminiOptimize = "gemini_optimize"
    case firebaseUpload = "firebase_upload"
}

struct DevCostEvent {
    let timestamp: Date
    let provider: DevCostProvider
    let operation: DevCostOperation
    let model: String
    let statusCode: Int?
    let success: Bool
    let durationMs: Double
    let promptCharacters: Int
    let inputTokens: Int
    let outputTokens: Int
    let inputImageCount: Int
    let outputImageCount: Int
    let uploadedBytes: Int
}

struct DevCostEstimate {
    let low: Double
    let base: Double
    let high: Double
    let confidence: Double
}

struct DevCostDailyRollup: Identifiable {
    let id: String
    let dayKey: String
    let date: Date
    let totalRequests: Int
    let successfulRequests: Int
    let failedRequests: Int
    let totalDurationMs: Double
    let estimatedCostLow: Double
    let estimatedCostBase: Double
    let estimatedCostHigh: Double
    let providerCounts: [String: Int]
    let providerCostBase: [String: Double]
    let modelCounts: [String: Int]
    let modelCostBase: [String: Double]
    let confidenceAverage: Double
    let lastUpdated: Date?

    static func fromDocument(_ doc: DocumentSnapshot) -> DevCostDailyRollup? {
        guard let data = doc.data() else { return nil }
        let date = (data["dateStart"] as? Timestamp)?.dateValue() ?? Date()
        let providerCountsRaw = data["providerCounts"] as? [String: Any] ?? [:]
        let providerCostRaw = data["providerCostBase"] as? [String: Any] ?? [:]
        let modelCountsRaw = data["modelCounts"] as? [String: Any] ?? [:]
        let modelCostRaw = data["modelCostBase"] as? [String: Any] ?? [:]
        let confidenceWeightedSum = (data["confidenceWeightedSum"] as? NSNumber)?.doubleValue ?? 0
        let totalRequests = (data["totalRequests"] as? NSNumber)?.intValue ?? 0

        return DevCostDailyRollup(
            id: doc.documentID,
            dayKey: data["dayKey"] as? String ?? doc.documentID,
            date: date,
            totalRequests: totalRequests,
            successfulRequests: (data["successfulRequests"] as? NSNumber)?.intValue ?? 0,
            failedRequests: (data["failedRequests"] as? NSNumber)?.intValue ?? 0,
            totalDurationMs: (data["totalDurationMs"] as? NSNumber)?.doubleValue ?? 0,
            estimatedCostLow: (data["estimatedCostLow"] as? NSNumber)?.doubleValue ?? 0,
            estimatedCostBase: (data["estimatedCostBase"] as? NSNumber)?.doubleValue ?? 0,
            estimatedCostHigh: (data["estimatedCostHigh"] as? NSNumber)?.doubleValue ?? 0,
            providerCounts: providerCountsRaw.reduce(into: [String: Int]()) { acc, item in
                acc[item.key] = (item.value as? NSNumber)?.intValue ?? 0
            },
            providerCostBase: providerCostRaw.reduce(into: [String: Double]()) { acc, item in
                acc[item.key] = (item.value as? NSNumber)?.doubleValue ?? 0
            },
            modelCounts: modelCountsRaw.reduce(into: [String: Int]()) { acc, item in
                acc[item.key] = (item.value as? NSNumber)?.intValue ?? 0
            },
            modelCostBase: modelCostRaw.reduce(into: [String: Double]()) { acc, item in
                acc[item.key] = (item.value as? NSNumber)?.doubleValue ?? 0
            },
            confidenceAverage: totalRequests > 0 ? max(0, min(1, confidenceWeightedSum / Double(totalRequests))) : 0,
            lastUpdated: (data["lastUpdated"] as? Timestamp)?.dateValue()
        )
    }
}

enum DevCostPeriod: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case custom = "Custom"

    var id: String { rawValue }
}

struct DevCostSummary {
    let totalRequests: Int
    let successfulRequests: Int
    let failedRequests: Int
    let estimatedCostLow: Double
    let estimatedCostBase: Double
    let estimatedCostHigh: Double
    let confidenceAverage: Double
    let providerCostBase: [String: Double]
    let modelCostBase: [String: Double]
    let lastUpdated: Date?
}

struct DevBillingEntry: Identifiable {
    let id: String
    let dayKey: String
    let date: Date
    let providerTotal: Double
    let manualTotal: Double
    let note: String
    let updatedAt: Date?

    var effectiveActualTotal: Double {
        providerTotal > 0 ? providerTotal : manualTotal
    }
}
