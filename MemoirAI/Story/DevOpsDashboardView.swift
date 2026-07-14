//
//  DevOpsDashboardView.swift
//  MemoirAI
//
//  In-app print-order ops dashboard. Presented from Settings behind the developer unlock,
//  but authorization is entirely server-side — see `Firebase/AdminOpsService.swift`.
//

import SwiftUI

/// Drives `DevOpsDashboardView`. Owns all Firebase calls; the view only renders `phase`/`orders`.
@MainActor
final class DevOpsDashboardViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        /// Server rejected the call — signed-in account isn't an admin (or no one is signed in).
        case notAdmin
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var orders: [AdminPrintOrder] = []
    @Published private(set) var actionInFlightOrderId: String?
    @Published var actionErrorMessage: String?
    @Published private(set) var lastActionMessage: String?

    private let service = AdminOpsService.shared
    private var lastActionMessageToken = UUID()

    /// Loads once per sheet presentation; `.task` re-invokes this on every appearance, but we only
    /// want the very first appearance to trigger the initial fetch (pull-to-refresh handles the rest).
    func loadIfNeeded() async {
        guard phase == .idle else { return }
        phase = .loading
        await performRefresh()
    }

    /// Retry button in the error/not-admin states, and pull-to-refresh in the loaded state.
    func refresh() async {
        await performRefresh()
    }

    private func performRefresh() async {
        do {
            let summary = try await service.listPrintOrders()
            orders = summary.orders
            phase = .loaded
        } catch let error as AdminOpsError {
            if case .notAdmin = error {
                phase = .notAdmin
            } else {
                phase = .error(error.errorDescription ?? "Something went wrong.")
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func syncFromLulu(_ order: AdminPrintOrder) async {
        guard actionInFlightOrderId == nil else { return }
        actionInFlightOrderId = order.orderId
        actionErrorMessage = nil
        do {
            try await service.syncOrderFromLulu(orderId: order.orderId, userId: order.userId)
            announce("Synced order \(Self.shortId(order.orderId)) from Lulu.")
            await performRefresh()
        } catch {
            actionErrorMessage = Self.message(for: error)
        }
        actionInFlightOrderId = nil
    }

    func fulfill(_ order: AdminPrintOrder) async {
        guard actionInFlightOrderId == nil else { return }
        actionInFlightOrderId = order.orderId
        actionErrorMessage = nil
        do {
            let result = try await service.fulfillOrder(orderId: order.orderId, userId: order.userId)
            let jobDescription = result.luluJobId.map { "job \($0)" } ?? "no job id yet"
            announce("Sent order \(Self.shortId(order.orderId)) to Lulu (\(jobDescription)).")
            await performRefresh()
        } catch {
            actionErrorMessage = Self.message(for: error)
        }
        actionInFlightOrderId = nil
    }

    /// Sets a transient success banner that clears itself after a few seconds.
    private func announce(_ message: String) {
        lastActionMessage = message
        let token = UUID()
        lastActionMessageToken = token
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if lastActionMessageToken == token {
                lastActionMessage = nil
            }
        }
    }

    private static func message(for error: Error) -> String {
        if let opsError = error as? AdminOpsError {
            return opsError.errorDescription ?? "Something went wrong."
        }
        return error.localizedDescription
    }

    static func shortId(_ orderId: String) -> String {
        String(orderId.prefix(8))
    }
}

/// Print-order queue for Caleb (owner). Access to the *screen* is gated by the existing developer
/// unlock in Settings; access to the *data* is enforced entirely by the `assertMemoirAdmin` check
/// inside `adminListPrintOrders` / `adminSyncOrderFromLulu` / `fulfillOrder` on the server.
struct DevOpsDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = DevOpsDashboardViewModel()
    @State private var pendingFulfillOrder: AdminPrintOrder?

    var body: some View {
        content
            .navigationTitle("Print Ops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .confirmationDialog(
                "Send to printer?",
                isPresented: Binding(
                    get: { pendingFulfillOrder != nil },
                    set: { isPresented in
                        if !isPresented { pendingFulfillOrder = nil }
                    }
                ),
                titleVisibility: .visible,
                presenting: pendingFulfillOrder
            ) { order in
                Button("Send to Lulu", role: .destructive) {
                    Task { await viewModel.fulfill(order) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This creates a real Lulu print job.")
            }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { viewModel.actionErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented { viewModel.actionErrorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.actionErrorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            ProgressView("Loading orders…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notAdmin:
            notAdminView
        case .error(let message):
            errorView(message)
        case .loaded:
            ordersList
        }
    }

    // MARK: - Not-admin state

    private var notAdminView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Admin Access Required")
                .font(.headline)
            Text("This dashboard needs your admin account. Link/sign in as caleb5mathew@gmail.com (Google) in Settings → Account, then come back.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Error state

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Couldn't load orders")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Loaded state

    private var ordersList: some View {
        List {
            Section {
                summaryChipsRow
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                if let message = viewModel.lastActionMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(.green)
                }
            }

            Section {
                if viewModel.orders.isEmpty {
                    Text("No print orders yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.orders) { order in
                        orderCard(order)
                    }
                }
            } header: {
                Text("\(viewModel.orders.count) orders")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var summaryChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                summaryChip(
                    title: "Awaiting fulfillment",
                    count: viewModel.orders.filter(\.needsPrintAction).count,
                    color: .blue
                )
                summaryChip(
                    title: "Failed",
                    count: viewModel.orders.filter(\.isLuluFailed).count,
                    color: .red
                )
                summaryChip(
                    title: "On hold",
                    count: viewModel.orders.filter(\.isOnHold).count,
                    color: .orange
                )
                summaryChip(
                    title: "In production",
                    count: viewModel.orders.filter(\.isInProduction).count,
                    color: .purple
                )
                summaryChip(
                    title: "Shipped",
                    count: viewModel.orders.filter(\.isShipped).count,
                    color: .teal
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func summaryChip(title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(width: 100, alignment: .leading)
        .background(color.opacity(0.12))
        .cornerRadius(10)
    }

    private func orderCard(_ order: AdminPrintOrder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(order.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                statusBadge(order)
            }

            HStack(spacing: 6) {
                if order.isLuluFailed {
                    FlagBadgeView(text: "FAILED", color: .red)
                }
                if order.disputeStatus == "disputed" {
                    FlagBadgeView(text: "DISPUTED", color: .red)
                }
                if order.refundStatus == "refunded" {
                    FlagBadgeView(text: "REFUNDED", color: .red)
                } else if order.refundStatus == "partially_refunded" {
                    FlagBadgeView(text: "PARTIAL REFUND", color: .orange)
                }
                if order.fulfillmentHold {
                    FlagBadgeView(text: "HOLD", color: .orange)
                }
            }

            Text("#\(DevOpsDashboardViewModel.shortId(order.orderId))… · \(order.createdAt.map { Self.dateFormatter.string(from: $0) } ?? "Unknown date")")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(Self.priceText(order)) · \(order.productTitle ?? "Print") · qty \(order.quantity) · \(order.shippingLevel ?? "MAIL")")
                .font(.caption)
                .foregroundColor(.secondary)

            if let city = order.shippingAddress?.cityStateLine, !city.isEmpty {
                Label(city, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let email = order.customerEmail, !email.isEmpty {
                Text(email)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let luluError = order.luluError, !luluError.isEmpty {
                Text(luluError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let jobId = order.luluPrintJobId {
                HStack(spacing: 8) {
                    Text("Lulu job \(jobId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let trackingUrl = order.luluTrackingUrl, let url = URL(string: trackingUrl) {
                        Link("Tracking", destination: url)
                            .font(.caption)
                    }
                }
            }

            actionRow(order)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actionRow(_ order: AdminPrintOrder) -> some View {
        let isBusy = viewModel.actionInFlightOrderId == order.orderId
        HStack(spacing: 12) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                if order.needsPrintAction && !order.isOnHold {
                    Button("Fulfill") {
                        pendingFulfillOrder = order
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                if order.luluPrintJobId != nil {
                    Button("Sync from Lulu") {
                        Task { await viewModel.syncFromLulu(order) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Spacer()
        }
        .disabled(viewModel.actionInFlightOrderId != nil && !isBusy)
    }

    private func statusBadge(_ order: AdminPrintOrder) -> some View {
        Text(order.statusDisplay)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Self.statusColor(order.status).opacity(0.15))
            .foregroundColor(Self.statusColor(order.status))
            .clipShape(Capsule())
    }

    private static func statusColor(_ status: String?) -> Color {
        switch status {
        case "paid": return .blue
        case "pending_fulfillment": return .indigo
        case "submitted_to_printer", "printing": return .purple
        case "shipped": return .teal
        case "delivered": return .green
        case "lulu_failed": return .red
        default: return .gray
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func priceText(_ order: AdminPrintOrder) -> String {
        guard let cents = order.totalCents else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = order.currency.uppercased()
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "—"
    }
}

/// Small colored capsule used for refund/dispute/hold flags on an order card.
private struct FlagBadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

struct DevOpsDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DevOpsDashboardView()
        }
    }
}
