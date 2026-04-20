import SwiftUI

struct DevEstimatedCostsView: View {
    @State private var period: DevCostPeriod = .daily
    @State private var rollups: [DevCostDailyRollup] = []
    @State private var summary: DevCostSummary = DevCostSummary(
        totalRequests: 0,
        successfulRequests: 0,
        failedRequests: 0,
        estimatedCostLow: 0,
        estimatedCostBase: 0,
        estimatedCostHigh: 0,
        confidenceAverage: 0,
        providerCostBase: [:],
        modelCostBase: [:],
        lastUpdated: nil
    )
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var isLoading = false

    var body: some View {
        ZStack {
            DevDashboardBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    periodControl
                    if period == .custom {
                        customRangePicker
                    }
                    totalCard
                    circlesRow
                    metricsGrid
                    providerBreakdown
                    modelBreakdown
                    lastUpdatedCard
                }
            }
            .padding(16)
            .overlay {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .navigationTitle("Estimated Costs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await reload() }
        .onChange(of: period) { _, _ in
            Task { await reload() }
        }
        .onChange(of: customStart) { _, _ in
            guard period == .custom else { return }
            Task { await reload() }
        }
        .onChange(of: customEnd) { _, _ in
            guard period == .custom else { return }
            Task { await reload() }
        }
    }

    private var periodControl: some View {
        Picker("Period", selection: $period) {
            ForEach(DevCostPeriod.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .padding(10)
        .tint(DevDashboardPalette.accentA)
        .devGlassCard(radius: 14, fillOpacity: 0.12)
    }

    private var customRangePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Start", selection: $customStart, displayedComponents: [.date])
            DatePicker("End", selection: $customEnd, displayedComponents: [.date])
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(DevDashboardPalette.primaryText)
        .tint(DevDashboardPalette.accentA)
        .padding(14)
        .devGlassCard(radius: 14, fillOpacity: 0.1)
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total estimated cost")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DevDashboardPalette.secondaryText)
            Text(currency(summary.estimatedCostBase))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(DevDashboardPalette.primaryText)
            Text("95% band: \(currency(summary.estimatedCostLow)) - \(currency(summary.estimatedCostHigh))")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DevDashboardPalette.secondaryText)
            Text("Confidence score: \(Int(summary.confidenceAverage * 100))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DevDashboardPalette.accentA)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .devGlassCard(radius: 16, fillOpacity: 0.12)
    }

    private var circlesRow: some View {
        HStack(spacing: 12) {
            circularMetric(title: "Success", value: successRateText, progress: successRate)
            circularMetric(title: "Requests", value: "\(summary.totalRequests)", progress: requestProgress)
            circularMetric(title: "Avg/request", value: currency(avgCost), progress: min(1.0, avgCost / 0.01))
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricCell("Successful", "\(summary.successfulRequests)")
            metricCell("Failed", "\(summary.failedRequests)")
            metricCell("Daily docs", "\(rollups.count)")
            metricCell("Period", period.rawValue)
        }
    }

    private var providerBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Provider cost split")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DevDashboardPalette.primaryText)
            ForEach(sortedPairs(summary.providerCostBase), id: \.0) { key, value in
                HStack {
                    Text(key)
                        .foregroundStyle(DevDashboardPalette.secondaryText)
                    Spacer()
                    Text(currency(value))
                        .foregroundStyle(DevDashboardPalette.primaryText)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 13))
            }
            if summary.providerCostBase.isEmpty {
                Text("No provider data in selected period.")
                    .font(.system(size: 13))
                    .foregroundStyle(DevDashboardPalette.mutedText)
            }
        }
        .padding(14)
        .devGlassCard(radius: 14, fillOpacity: 0.1)
    }

    private var modelBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model cost split")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DevDashboardPalette.primaryText)
            ForEach(sortedPairs(summary.modelCostBase), id: \.0) { key, value in
                HStack {
                    Text(key)
                        .foregroundStyle(DevDashboardPalette.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(currency(value))
                        .foregroundStyle(DevDashboardPalette.primaryText)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 13))
            }
            if summary.modelCostBase.isEmpty {
                Text("No model data in selected period.")
                    .font(.system(size: 13))
                    .foregroundStyle(DevDashboardPalette.mutedText)
            }
        }
        .padding(14)
        .devGlassCard(radius: 14, fillOpacity: 0.1)
    }

    private var lastUpdatedCard: some View {
        HStack {
            Label("Last updated", systemImage: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DevDashboardPalette.secondaryText)
            Spacer()
            Text(Self.lastUpdatedFormatter.string(from: summary.lastUpdated ?? Date()))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DevDashboardPalette.primaryText)
        }
        .padding(14)
        .devGlassCard(radius: 14, fillOpacity: 0.1)
    }

    private func circularMetric(title: String, value: String, progress: Double) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: max(0.03, min(1, progress)))
                    .stroke(
                        LinearGradient(
                            colors: [DevDashboardPalette.accentA, DevDashboardPalette.accentB],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DevDashboardPalette.primaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 82, height: 82)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DevDashboardPalette.secondaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .devGlassCard(radius: 14, fillOpacity: 0.1)
    }

    private func metricCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DevDashboardPalette.secondaryText)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DevDashboardPalette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .devGlassCard(radius: 14, fillOpacity: 0.1)
    }

    private var successRate: Double {
        guard summary.totalRequests > 0 else { return 0 }
        return Double(summary.successfulRequests) / Double(summary.totalRequests)
    }

    private var successRateText: String {
        "\(Int(successRate * 100))%"
    }

    private var avgCost: Double {
        guard summary.totalRequests > 0 else { return 0 }
        return summary.estimatedCostBase / Double(summary.totalRequests)
    }

    private var requestProgress: Double {
        min(1.0, Double(summary.totalRequests) / 200.0)
    }

    private func reload() async {
        isLoading = true
        let range = DevCostEstimator.dateRange(for: period, customStart: customStart, customEnd: customEnd)
        let fetched = await DevCostTelemetryService.shared.fetchDailyRollups(start: range.0, end: range.1)
        rollups = fetched
        summary = DevCostEstimator.summarize(fetched)
        isLoading = false
    }

    private func sortedPairs(_ map: [String: Double]) -> [(String, Double)] {
        map.sorted { $0.value > $1.value }
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private static let lastUpdatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
