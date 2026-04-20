import Foundation

enum DevCostEstimator {
    static func summarize(_ rollups: [DevCostDailyRollup]) -> DevCostSummary {
        let totalRequests = rollups.reduce(0) { $0 + $1.totalRequests }
        let successfulRequests = rollups.reduce(0) { $0 + $1.successfulRequests }
        let failedRequests = rollups.reduce(0) { $0 + $1.failedRequests }
        let estimatedCostLow = rollups.reduce(0) { $0 + $1.estimatedCostLow }
        let estimatedCostBase = rollups.reduce(0) { $0 + $1.estimatedCostBase }
        let estimatedCostHigh = rollups.reduce(0) { $0 + $1.estimatedCostHigh }

        let providerCostBase = rollups.reduce(into: [String: Double]()) { acc, rollup in
            for (key, value) in rollup.providerCostBase {
                acc[key, default: 0] += value
            }
        }
        let modelCostBase = rollups.reduce(into: [String: Double]()) { acc, rollup in
            for (key, value) in rollup.modelCostBase {
                acc[key, default: 0] += value
            }
        }
        let confidenceAverage: Double
        if totalRequests > 0 {
            let weighted = rollups.reduce(0.0) { $0 + ($1.confidenceAverage * Double($1.totalRequests)) }
            confidenceAverage = max(0, min(1, weighted / Double(totalRequests)))
        } else {
            confidenceAverage = 0
        }

        let lastUpdated = rollups.compactMap(\.lastUpdated).max()

        return DevCostSummary(
            totalRequests: totalRequests,
            successfulRequests: successfulRequests,
            failedRequests: failedRequests,
            estimatedCostLow: estimatedCostLow,
            estimatedCostBase: estimatedCostBase,
            estimatedCostHigh: estimatedCostHigh,
            confidenceAverage: confidenceAverage,
            providerCostBase: providerCostBase,
            modelCostBase: modelCostBase,
            lastUpdated: lastUpdated
        )
    }

    static func dateRange(for period: DevCostPeriod, customStart: Date, customEnd: Date, now: Date = Date()) -> (Date, Date) {
        let cal = Calendar.current
        let end = now
        switch period {
        case .daily:
            let start = cal.startOfDay(for: now)
            return (start, end)
        case .weekly:
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? cal.startOfDay(for: now)
            return (start, end)
        case .monthly:
            let start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now)) ?? cal.startOfDay(for: now)
            return (start, end)
        case .custom:
            let start = min(customStart, customEnd)
            let rangeEnd = max(customStart, customEnd)
            return (cal.startOfDay(for: start), rangeEnd)
        }
    }
}
