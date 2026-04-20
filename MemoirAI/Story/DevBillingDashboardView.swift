import SwiftUI

struct DevBillingDashboardView: View {
    @State private var period: DevCostPeriod = .daily
    @State private var rollups: [DevCostDailyRollup] = []
    @State private var billingEntries: [DevBillingEntry] = []
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var selectedDay: Date = Date()
    @State private var providerTotal: String = ""
    @State private var manualTotal: String = ""
    @State private var note: String = ""
    @State private var isLoading = false
    @State private var lastUpdated = Date()

    var body: some View {
        ZStack {
            DevDashboardBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    periodControl
                    if period == .custom {
                        customRangePicker
                    }
                    summaryCard
                    entryForm
                    entriesList
                    lastUpdatedCard
                }
            }
            .padding(16)
            .overlay {
                if isLoading {
                    ProgressView().tint(.white)
                }
            }
        }
        .navigationTitle("Billing Reconciliation")
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

    private var summaryCard: some View {
        let telemetrySummary = DevCostEstimator.summarize(rollups)
        let actualTotal = billingEntries.reduce(0.0) { $0 + $1.effectiveActualTotal }
        let delta = actualTotal - telemetrySummary.estimatedCostBase

        return VStack(alignment: .leading, spacing: 8) {
            Text("Estimated vs Actual")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DevDashboardPalette.secondaryText)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DevDashboardPalette.secondaryText)
                    Text(currency(telemetrySummary.estimatedCostBase))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DevDashboardPalette.primaryText)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Actual")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DevDashboardPalette.secondaryText)
                    Text(currency(actualTotal))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DevDashboardPalette.primaryText)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delta")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DevDashboardPalette.secondaryText)
                    Text(currency(delta))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(delta >= 0 ? .orange : .green.opacity(0.92))
                }
            }
        }
        .padding(16)
        .devGlassCard(radius: 16, fillOpacity: 0.12)
    }

    private var entryForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add/Update Billing Entry")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DevDashboardPalette.primaryText)
            DatePicker("Day", selection: $selectedDay, displayedComponents: [.date])
                .tint(DevDashboardPalette.accentA)
                .foregroundStyle(DevDashboardPalette.primaryText)
            TextField("Provider total (USD)", text: $providerTotal)
                .textFieldStyle(DevDashboardInputStyle())
                .keyboardType(.decimalPad)
            TextField("Manual total (USD)", text: $manualTotal)
                .textFieldStyle(DevDashboardInputStyle())
                .keyboardType(.decimalPad)
            TextField("Note", text: $note)
                .textFieldStyle(DevDashboardInputStyle())
            Button("Save Billing Entry") {
                Task { await saveEntry() }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(DevDashboardPalette.primaryText)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [DevDashboardPalette.accentB, DevDashboardPalette.accentA],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .buttonStyle(.plain)
        }
        .padding(14)
        .devGlassCard(radius: 14, fillOpacity: 0.1)
    }

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Entries")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DevDashboardPalette.primaryText)
            if billingEntries.isEmpty {
                Text("No billing entries for selected period.")
                    .font(.system(size: 13))
                    .foregroundStyle(DevDashboardPalette.secondaryText)
            } else {
                ForEach(billingEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(Self.dayFormatter.string(from: entry.date))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DevDashboardPalette.primaryText)
                            Spacer()
                            Text(currency(entry.effectiveActualTotal))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DevDashboardPalette.primaryText)
                        }
                        Text("Provider: \(currency(entry.providerTotal)) | Manual: \(currency(entry.manualTotal))")
                            .font(.system(size: 12))
                            .foregroundStyle(DevDashboardPalette.secondaryText)
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(.system(size: 12))
                                .foregroundStyle(DevDashboardPalette.tertiaryText)
                        }
                    }
                    .padding(10)
                    .devGlassCard(radius: 10, fillOpacity: 0.08)
                }
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
            Text(Self.timestampFormatter.string(from: lastUpdated))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DevDashboardPalette.primaryText)
        }
        .padding(14)
        .devGlassCard(radius: 14, fillOpacity: 0.1)
    }

    private func saveEntry() async {
        let provider = Double(providerTotal) ?? 0
        let manual = Double(manualTotal) ?? 0
        await DevBillingStore.shared.upsertEntry(
            day: selectedDay,
            providerTotal: provider,
            manualTotal: manual,
            note: note
        )
        providerTotal = ""
        manualTotal = ""
        note = ""
        await reload()
    }

    private func reload() async {
        isLoading = true
        let range = DevCostEstimator.dateRange(for: period, customStart: customStart, customEnd: customEnd)
        async let telemetry = DevCostTelemetryService.shared.fetchDailyRollups(start: range.0, end: range.1)
        async let billing = DevBillingStore.shared.fetchEntries(start: range.0, end: range.1)
        rollups = await telemetry
        billingEntries = await billing
        lastUpdated = Date()
        isLoading = false
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
