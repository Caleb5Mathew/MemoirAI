//
//  OrderBookView.swift
//  MemoirAI
//
//  Order a printed copy of a Kids Book via Stripe + Lulu.
//

import SwiftUI
import SafariServices

struct OrderBookView: View {
    let book: BookVersionRecord
    @Environment(\.dismiss) private var dismiss

    @State private var shipping = ShippingAddress()
    @State private var shippingLevel = "MAIL"
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showStripeCheckout = false
    @State private var checkoutURL: URL?
    @State private var lastCheckoutAttempt: Date?

    private let shippingOptions: [(id: String, label: String)] = [
        ("MAIL", "Standard Mail"),
        ("PRIORITY_MAIL", "Priority Mail"),
        ("GROUND", "Ground"),
        ("EXPEDITED", "Expedited"),
        ("EXPRESS", "Express")
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    bookPreviewSection
                    productDetailsSection
                    shippingFormSection
                    shippingSpeedSection
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    payButton
                }
                .padding(20)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Order Print")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showStripeCheckout) {
                if let url = checkoutURL {
                    SafariView(url: url) {
                        showStripeCheckout = false
                        checkoutURL = nil
                        dismiss()
                    }
                }
            }
        }
        .onAppear { loadLastAddress() }
        .onReceive(NotificationCenter.default.publisher(for: .orderComplete)) { _ in
            showStripeCheckout = false
            checkoutURL = nil
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .orderCancelled)) { _ in
            showStripeCheckout = false
            checkoutURL = nil
        }
    }

    private var bookPreviewSection: some View {
        HStack(spacing: 16) {
            if let coverURL = book.coverURL, let url = URL(string: coverURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        Color.gray.opacity(0.3)
                    default:
                        Color.gray.opacity(0.2)
                    }
                }
                .frame(width: 80, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 64)
                    .overlay(Image(systemName: "book.closed").foregroundColor(.gray))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(firstPageTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(book.pageCount) pages")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var firstPageTitle: String {
        book.pages.first?.title ?? "Story"
    }

    private var productDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Product")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text("\(book.pageWidth > book.pageHeight ? "11 x 8.5\"" : "8.5 x 11\"") Hardcover, Full Color, Matte Finish")
                .font(.subheadline)
        }
    }

    private var shippingFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shipping Address")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            TextField("Full Name", text: $shipping.name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
            TextField("Street Address", text: $shipping.street1)
                .textFieldStyle(.roundedBorder)
                .textContentType(.streetAddressLine1)
            HStack(spacing: 12) {
                TextField("City", text: $shipping.city)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.addressCity)
                TextField("State", text: $shipping.stateCode)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.addressState)
            }
            HStack(spacing: 12) {
                TextField("ZIP", text: $shipping.postcode)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.postalCode)
                TextField("Country", text: $shipping.countryCode)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.countryName)
            }
            TextField("Phone", text: $shipping.phone)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var shippingSpeedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shipping Speed")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Picker("Shipping", selection: $shippingLevel) {
                ForEach(shippingOptions, id: \.id) { opt in
                    Text(opt.label).tag(opt.id)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var payButton: some View {
        Button(action: startCheckout) {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "creditcard.fill")
                    Text("Pay with Stripe")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isSubmitting || !isFormValid || checkoutURL != nil)
    }

    private var isFormValid: Bool {
        !shipping.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !shipping.street1.trimmingCharacters(in: .whitespaces).isEmpty
            && !shipping.city.trimmingCharacters(in: .whitespaces).isEmpty
            && !shipping.stateCode.trimmingCharacters(in: .whitespaces).isEmpty
            && !shipping.postcode.trimmingCharacters(in: .whitespaces).isEmpty
            && !shipping.countryCode.trimmingCharacters(in: .whitespaces).isEmpty
            && !shipping.phone.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func loadLastAddress() {
        if let data = UserDefaults.standard.data(forKey: "order_last_shipping"),
           let decoded = try? JSONDecoder().decode(ShippingAddress.self, from: data) {
            shipping = decoded
        }
    }

    private func saveLastAddress() {
        if let data = try? JSONEncoder().encode(shipping) {
            UserDefaults.standard.set(data, forKey: "order_last_shipping")
        }
    }

    private func startCheckout() {
        if let last = lastCheckoutAttempt, Date().timeIntervalSince(last) < 3.0 {
            return
        }
        lastCheckoutAttempt = Date()
        errorMessage = nil
        isSubmitting = true

        Task {
            do {
                saveLastAddress()
                let (url, _) = try await OrderService.shared.createCheckoutSession(
                    bookVersionId: book.bookVersionId,
                    shippingAddress: shipping,
                    shippingLevel: shippingLevel
                )
                await MainActor.run {
                    checkoutURL = url
                    showStripeCheckout = true
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDismiss() }
    }
}

