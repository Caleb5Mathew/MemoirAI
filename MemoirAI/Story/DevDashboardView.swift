import SwiftUI

struct DevDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = RCSubscriptionManager.shared
    @State private var lastUpdated = Date()

    var body: some View {
        ZStack {
            DevDashboardBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    headerCard

                    NavigationLink {
                        DevEstimatedCostsView()
                    } label: {
                        actionCard(
                            title: "Estimated Costs",
                            subtitle: "Telemetry-based spend, confidence band, and filters",
                            systemImage: "chart.pie.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DevBillingDashboardView()
                    } label: {
                        actionCard(
                            title: "Billing Reconciliation",
                            subtitle: "Provider and manual totals versus estimated deltas",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                    .buttonStyle(.plain)

                    if subscriptionManager.isPersistentDevMode {
                        Button {
                            subscriptionManager.disablePersistentDevMode()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 16, weight: .bold))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Disable persistent developer mode")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(DevDashboardPalette.primaryText)
                                    Text("Reverts to real subscription state after next RevenueCat refresh.")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(DevDashboardPalette.secondaryText)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                            }
                            .padding(18)
                            .devGlassCard(radius: 18, fillOpacity: 0.1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Dev Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 15, weight: .semibold))
                }
                .tint(DevDashboardPalette.primaryText)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            lastUpdated = Date()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cost Intelligence")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(DevDashboardPalette.primaryText)
            Text("Track API usage and financial signals across all users with developer-only controls.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DevDashboardPalette.secondaryText)

            Divider().overlay(Color.white.opacity(0.24))

            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DevDashboardPalette.accentA)
                Text("Last updated")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DevDashboardPalette.tertiaryText)
                Spacer()
                Text(Self.timestampFormatter.string(from: lastUpdated))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DevDashboardPalette.primaryText)
            }
        }
        .padding(20)
        .devGlassCard(radius: 20, fillOpacity: 0.12)
    }

    private func actionCard(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 14) {
            DevDashboardIconBadge(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DevDashboardPalette.primaryText)
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DevDashboardPalette.secondaryText)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DevDashboardPalette.primaryText)
        }
        .padding(18)
        .devGlassCard(radius: 18, fillOpacity: 0.1)
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [DevDashboardPalette.accentA.opacity(0.35), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
