import Foundation
import FirebaseAuth
import FirebaseFirestore

actor DevCostTelemetryService {
    static let shared = DevCostTelemetryService()

    private let db = Firestore.firestore()
    private let userTelemetryCollection = "apiTelemetry"
    private let globalTelemetryCollection = "globalApiTelemetry"
    private let globalTotalsCollection = "globalApiTelemetryTotals"
    private let globalLifetimeDocument = "lifetime"
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private var disableTelemetryWrites = false

    private init() {}

    func logEvent(_ event: DevCostEvent) async {
        guard !disableTelemetryWrites else { return }
        guard let user = Auth.auth().currentUser else { return }

        let userId = user.uid
        let estimate = DevCostRateCard.estimate(for: event)
        let dayKey = dayFormatter.string(from: event.timestamp)
        let dayStart = Calendar.current.startOfDay(for: event.timestamp)
        let providerKey = Self.sanitizeKey(event.provider.rawValue)
        let modelKey = Self.sanitizeKey(event.model.isEmpty ? "unknown" : event.model)

        let payload: [String: Any] = [
            "dayKey": dayKey,
            "dateStart": Timestamp(date: dayStart),
            "totalRequests": FieldValue.increment(Int64(1)),
            "successfulRequests": FieldValue.increment(Int64(event.success ? 1 : 0)),
            "failedRequests": FieldValue.increment(Int64(event.success ? 0 : 1)),
            "totalDurationMs": FieldValue.increment(event.durationMs),
            "totalPromptCharacters": FieldValue.increment(Int64(event.promptCharacters)),
            "totalInputTokens": FieldValue.increment(Int64(event.inputTokens)),
            "totalOutputTokens": FieldValue.increment(Int64(event.outputTokens)),
            "totalInputImages": FieldValue.increment(Int64(event.inputImageCount)),
            "totalOutputImages": FieldValue.increment(Int64(event.outputImageCount)),
            "totalUploadedBytes": FieldValue.increment(Int64(event.uploadedBytes)),
            "estimatedCostLow": FieldValue.increment(estimate.low),
            "estimatedCostBase": FieldValue.increment(estimate.base),
            "estimatedCostHigh": FieldValue.increment(estimate.high),
            "confidenceWeightedSum": FieldValue.increment(estimate.confidence),
            "providerCounts.\(providerKey)": FieldValue.increment(Int64(1)),
            "providerCostBase.\(providerKey)": FieldValue.increment(estimate.base),
            "modelCounts.\(modelKey)": FieldValue.increment(Int64(1)),
            "modelCostBase.\(modelKey)": FieldValue.increment(estimate.base),
            "lastUpdated": FieldValue.serverTimestamp()
        ]

        let globalPayload: [String: Any] = payload.merging([
            "lastUserId": userId
        ]) { _, new in new }

        let lifetimePayload: [String: Any] = [
            "totalRequests": FieldValue.increment(Int64(1)),
            "successfulRequests": FieldValue.increment(Int64(event.success ? 1 : 0)),
            "failedRequests": FieldValue.increment(Int64(event.success ? 0 : 1)),
            "estimatedCostLow": FieldValue.increment(estimate.low),
            "estimatedCostBase": FieldValue.increment(estimate.base),
            "estimatedCostHigh": FieldValue.increment(estimate.high),
            "providerCounts.\(providerKey)": FieldValue.increment(Int64(1)),
            "providerCostBase.\(providerKey)": FieldValue.increment(estimate.base),
            "modelCounts.\(modelKey)": FieldValue.increment(Int64(1)),
            "modelCostBase.\(modelKey)": FieldValue.increment(estimate.base),
            "totalOutputImages": FieldValue.increment(Int64(event.outputImageCount)),
            "totalInputImages": FieldValue.increment(Int64(event.inputImageCount)),
            "totalUploadedBytes": FieldValue.increment(Int64(event.uploadedBytes)),
            "lastUpdated": FieldValue.serverTimestamp(),
            "lastUserId": userId
        ]

        let userDayRef = db.collection("users").document(userId)
            .collection(userTelemetryCollection)
            .document(dayKey)
        let globalDayRef = db.collection(globalTelemetryCollection).document(dayKey)
        let globalLifetimeRef = db.collection(globalTotalsCollection).document(globalLifetimeDocument)

        do {
            async let userWrite = userDayRef.setData(payload, merge: true)
            async let globalWrite = globalDayRef.setData(globalPayload, merge: true)
            async let lifetimeWrite = globalLifetimeRef.setData(lifetimePayload, merge: true)
            _ = try await (userWrite, globalWrite, lifetimeWrite)
        } catch {
            print("⚠️ DevCostTelemetryService log failed: \(error.localizedDescription)")
            let ns = error as NSError
            if ns.domain == FirestoreErrorDomain,
               ns.code == FirestoreErrorCode.permissionDenied.rawValue {
                // Prevent noisy repeated permission-denied retries in dev sessions.
                disableTelemetryWrites = true
                print("⚠️ DevCostTelemetryService disabled telemetry writes for this session due to permissionDenied.")
            }
        }
    }

    /// Global rollups across all users for the developer dashboard.
    func fetchDailyRollups(start: Date, end: Date) async -> [DevCostDailyRollup] {
        guard Auth.auth().currentUser != nil else { return [] }
        let startDay = Calendar.current.startOfDay(for: start)
        let endDay = Calendar.current.startOfDay(for: end)
        let query = db.collection(globalTelemetryCollection)
            .whereField("dateStart", isGreaterThanOrEqualTo: Timestamp(date: startDay))
            .whereField("dateStart", isLessThanOrEqualTo: Timestamp(date: endDay))
            .order(by: "dateStart", descending: true)

        do {
            let snapshot = try await query.getDocuments()
            return snapshot.documents.compactMap(DevCostDailyRollup.fromDocument)
        } catch {
            print("⚠️ DevCostTelemetryService fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    nonisolated static func extractOpenAIUsage(from data: Data) -> (inputTokens: Int, outputTokens: Int) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let usage = root["usage"] as? [String: Any]
        else {
            return (0, 0)
        }
        let input = (usage["prompt_tokens"] as? NSNumber)?.intValue ?? 0
        let output = (usage["completion_tokens"] as? NSNumber)?.intValue ?? 0
        return (input, output)
    }

    nonisolated static func sanitizeKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        return trimmed
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
