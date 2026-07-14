//
//  OrderHistoryView.swift
//  MemoirAI
//
//  Displays past print orders with status and full detail view.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct OrderHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var orders: [OrderRecord] = []
    @State private var listener: ListenerRegistration?
    @State private var selectedOrder: OrderRecord?

    var body: some View {
        NavigationView {
            Group {
                if orders.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(orders) { order in
                            Button {
                                selectedOrder = order
                            } label: {
                                OrderRowView(order: order)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Print Orders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                startListening()
                OrderService.markOrdersSeen()
            }
            .onDisappear { listener?.remove() }
            .sheet(item: $selectedOrder) { order in
                OrderDetailView(order: order)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox")
                .font(.system(size: 56))
                .foregroundColor(.gray.opacity(0.5))
            Text("No orders yet")
                .font(.title2)
                .fontWeight(.medium)
            Text("Order a printed copy of your book from the library reader.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        listener = OrderService.shared.ordersListener(userId: userId) { newOrders in
            orders = newOrders
            OrderService.markOrdersSeen()
        }
    }
}

// MARK: - Order Row

struct OrderRowView: View {
    let order: OrderRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Order \(order.orderId.suffix(8))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if let pill = order.specialStatusPill {
                    specialPill(pill)
                }
                statusBadge
            }
            if let addr = order.shippingAddress {
                Text("\(addr.city), \(addr.stateCode) \(addr.postcode)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let (cents, currency) = order.pricing {
                Text(formatPrice(cents: cents, currency: currency))
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding(.vertical, 4)
    }

    var statusBadge: some View {
        Text(order.statusDisplay)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }

    var statusColor: Color {
        switch order.status {
        case OrderStatus.paid.rawValue, OrderStatus.pendingFulfillment.rawValue: return .purple
        case OrderStatus.delivered.rawValue: return .green
        case OrderStatus.shipped.rawValue: return .blue
        case OrderStatus.printing.rawValue, OrderStatus.submittedToPrinter.rawValue: return .orange
        case OrderStatus.failed.rawValue, OrderStatus.luluFailed.rawValue: return .red
        default: return .gray
        }
    }

    /// Renders a refund/dispute/hold pill using the same capsule styling as `statusBadge`.
    func specialPill(_ pill: (text: String, color: Color)) -> some View {
        Text(pill.text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(pill.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(pill.color.opacity(0.15))
            .clipShape(Capsule())
    }

    func formatPrice(cents: Int, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$\(cents / 100).\((cents % 100))"
    }
}

// MARK: - Order Detail View

struct OrderDetailView: View {
    let order: OrderRecord
    @Environment(\.dismiss) private var dismiss
    @State private var copiedOrderId = false
    @State private var showSupportCopiedAlert = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status banner
                    statusBannerSection

                    // Order ID
                    orderIdSection

                    // Tracking (if available)
                    if let trackingUrl = order.luluTrackingUrl, let url = URL(string: trackingUrl) {
                        trackingSection(url: url)
                    }

                    // Shipping address
                    if let addr = order.shippingAddress {
                        shippingSection(addr: addr)
                    }

                    // Price
                    if let (cents, currency) = order.pricing {
                        priceSection(cents: cents, currency: currency)
                    }

                    // Status history
                    if !order.luluStatusHistory.isEmpty {
                        statusHistorySection
                    }

                    // Order date
                    if let createdAt = order.createdAt {
                        detailRow(label: "Order placed", value: createdAt.formatted(date: .long, time: .shortened))
                    }

                    contactSupportSection
                }
                .padding(20)
            }
            .refreshable {
                do {
                    try await OrderService.shared.syncOrderFromLulu(orderId: order.orderId)
                } catch {
                    // Quiet failure by design: the live Firestore listener keeps showing cached state.
                    print("⚠️ syncOrderFromLulu failed for \(order.orderId): \(error.localizedDescription)")
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Order Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Email Copied", isPresented: $showSupportCopiedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("We couldn't open Mail, so we copied \(SupportContact.email) to your clipboard.")
            }
        }
    }

    private var statusBannerSection: some View {
        let rowView = OrderRowView(order: order)
        return VStack(spacing: 8) {
            HStack {
                Spacer()
                rowView.statusBadge
                    .scaleEffect(1.2)
                Spacer()
            }
            if let pill = order.specialStatusPill {
                HStack {
                    Spacer()
                    rowView.specialPill(pill)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var contactSupportSection: some View {
        Button {
            SupportContact.contact(subject: "Order #\(order.orderId)") {
                showSupportCopiedAlert = true
            }
        } label: {
            HStack {
                Image(systemName: "envelope.fill")
                Text("Contact Support")
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .font(.subheadline)
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var orderIdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Order ID")
            HStack {
                Text(order.orderId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    UIPasteboard.general.string = order.orderId
                    copiedOrderId = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedOrderId = false
                    }
                } label: {
                    Label(copiedOrderId ? "Copied!" : "Copy", systemImage: copiedOrderId ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(copiedOrderId ? .green : .accentColor)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func trackingSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tracking")
            Link(destination: url) {
                HStack {
                    Image(systemName: "shippingbox.fill")
                    Text("Track your shipment")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func shippingSection(addr: ShippingAddress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Ships To")
            VStack(alignment: .leading, spacing: 3) {
                Text(addr.name).font(.subheadline).fontWeight(.medium)
                Text(addr.street1).font(.subheadline).foregroundColor(.secondary)
                Text("\(addr.city), \(addr.stateCode) \(addr.postcode)").font(.subheadline).foregroundColor(.secondary)
                Text(addr.countryCode).font(.subheadline).foregroundColor(.secondary)
                if !addr.phone.isEmpty {
                    Text(addr.phone).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func priceSection(cents: Int, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Payment")
            HStack {
                Text("Total paid")
                    .font(.subheadline)
                Spacer()
                Text(OrderRowView(order: order).formatPrice(cents: cents, currency: currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Status History")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(order.luluStatusHistory.reversed().enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry["status"] as? String ?? "Unknown")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let ts = entry["timestamp"] as? String {
                                Text(ts)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}
