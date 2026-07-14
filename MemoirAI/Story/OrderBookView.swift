//
//  OrderBookView.swift
//  MemoirAI
//
//  Order a printed copy via Stripe + Lulu, with live Lulu estimate and Google Places address search.
//

import SwiftUI
import SafariServices
import MapKit
import FirebaseAuth
import AuthenticationServices

@MainActor
private final class LocalAddressAutocomplete: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var completions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(query: String) {
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
        print("📦 local autocomplete failed: \(error.localizedDescription)")
    }
}

struct OrderBookView: View {
    private struct PrintProductOption: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let minPages: Int
        let maxPages: Int
        let podPackageId: String

        var requirementsText: String {
            "Page requirement: \(minPages)-\(maxPages)"
        }
    }
    private struct ShippingOptionDisplay: Identifiable {
        let id: String
        let label: String
        let etaText: String?
        /// Lulu `/shipping-options/` cost when present (informational; cart total uses separate whole-order calc).
        let shippingPriceCents: Int?
    }

    let book: BookVersionRecord
    @Environment(\.dismiss) private var dismiss

    @State private var shipping = ShippingAddress()
    @State private var shippingLevel = "MAIL"
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showStripeCheckout = false
    @State private var checkoutURL: URL?
    @State private var lastCheckoutAttempt: Date?
    /// Shown after a successful Stripe return instead of silently dismissing (see `.orderComplete`).
    @State private var showOrderConfirmation = false
    /// Session-only dismissal for the anonymous-account purchase-protection nudge on the review step.
    @State private var accountLinkBannerDismissed = false
    /// Server `book{N}` id for fast checkout resume (`createCartCheckoutSessionFast`).
    @State private var fastCheckoutInstanceId: String?
    /// Dev-only diagnistics for Firebase callable failures (see `OrderService.debugCallableErrorFootnote`).
    @State private var checkoutErrorDebugFootnote: String?

    @State private var placesSessionToken = UUID().uuidString
    @State private var addressPredictions: [AddressPrediction] = []
    @State private var isEstimating = false
    @State private var estimateTask: Task<Void, Never>?
    @State private var autocompleteTask: Task<Void, Never>?

    private enum ActiveField: Hashable {
        case street
    }
    private enum CheckoutStep: Int, CaseIterable {
        case formatQuantity
        case shipping
        case cart
        case review

        var title: String {
            switch self {
            case .formatQuantity: return "Format"
            case .shipping: return "Shipping"
            case .cart: return "Cart"
            case .review: return "Review"
            }
        }

        /// Short description under the progress header for the active step.
        var detailSubtitle: String {
            switch self {
            case .formatQuantity: return "Choose binding and how many copies to add."
            case .shipping: return "Enter where your books should be delivered."
            case .cart: return "Adjust quantity or remove the line before paying."
            case .review: return "Confirm the live Lulu estimate, then pay with Stripe."
            }
        }
    }
    @FocusState private var focusedField: ActiveField?
    @StateObject private var localAutocomplete = LocalAddressAutocomplete()
    @State private var localCompletionById: [String: MKLocalSearchCompletion] = [:]
    @State private var useLocalAutocompleteFallback = false
    /// Superseded-request guard so only the latest typing burst hits the Places callable (reduces fetcher churn).
    @State private var autocompleteRequestSerial = 0
    /// Cache placeId -> resolved address so ZIP can fill immediately on selection.
    @State private var resolvedAddressByPlaceId: [String: ShippingAddress] = [:]
    /// Superseded-request guard for background prefetch of place details.
    @State private var detailsPrefetchSerial = 0

    @State private var coverPreviewCandidateIndex = 0
    @State private var selectedProductOptionId: String?
    @ObservedObject private var orderCart = OrderCartStore.shared
    @State private var lineQuantity = 1
    @State private var cartEstimate: CartCheckoutEstimate?
    @State private var activeStep: CheckoutStep = .formatQuantity

    private let defaultShippingOptions: [(id: String, label: String)] = [
        ("MAIL", "Standard Mail"),
        ("PRIORITY_MAIL", "Priority Mail"),
        ("GROUND_HD", "Ground (Home)"),
        ("GROUND_BUS", "Ground (Business)"),
        ("GROUND", "Ground"),
        ("EXPEDITED", "Expedited"),
        ("EXPRESS", "Express")
    ]
    
    private var cardBackground: Color { Color(UIColor.systemBackground) }
    private var cardStroke: Color { Color.black.opacity(0.08) }
    private var fieldBackground: Color { Color(UIColor.secondarySystemGroupedBackground) }
    private var accentColor: Color { Color(red: 0.17, green: 0.42, blue: 0.78) }
    private var mutedTextColor: Color { Color.secondary.opacity(0.9) }
    private var isLandscapeBook: Bool { book.pageWidth > book.pageHeight }

    private var productOptions: [PrintProductOption] {
        Self.printProductOptions(isLandscape: isLandscapeBook)
    }

    /// Shared catalog for cart line validation (page count vs format).
    private static func printProductOptions(isLandscape: Bool) -> [PrintProductOption] {
        if isLandscape {
            return [
                PrintProductOption(
                    id: "kids_hardcover_casewrap",
                    title: "Hardcover (Casewrap)",
                    subtitle: "Premium keepsake with matte hard cover",
                    minPages: 24,
                    maxPages: 800,
                    podPackageId: "1100X0850FCSTDCW080CW444MXX"
                ),
                PrintProductOption(
                    id: "kids_coil_bound",
                    title: "Coil Bound",
                    subtitle: "Best for short books and activity-style flipping",
                    minPages: 2,
                    maxPages: 470,
                    podPackageId: "1100X0850FCSTDCO080CW444MXX"
                ),
                PrintProductOption(
                    id: "kids_paperback_perfect",
                    title: "Paperback",
                    subtitle: "Softcover perfect bound",
                    minPages: 32,
                    maxPages: 250,
                    podPackageId: "1100X0850FCSTDPB080CW444MXX"
                )
            ]
        }
        return [
            PrintProductOption(
                id: "portrait_hardcover_casewrap",
                title: "Hardcover (Casewrap)",
                subtitle: "Premium keepsake with matte hard cover",
                minPages: 24,
                maxPages: 800,
                podPackageId: "0850X1100FCSTDCW080CW444MXX"
            )
        ]
    }

    var body: some View {
        bodyWithAllHandlers
    }

    private var bodyContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    compactOrderSummaryCard
                    wizardProgressHeader
                    wizardStepPanel
                    if let msg = errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(msg)
                                .font(.footnote)
                                .foregroundColor(.red)
                            #if DEBUG
                            if let dbg = checkoutErrorDebugFootnote {
                                Text(dbg)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            #endif
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Text("Secure checkout powered by Stripe. Printing fulfilled by Lulu.")
                        .font(.caption)
                        .foregroundColor(mutedTextColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                wizardBottomActionBar
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(UIColor.systemGroupedBackground)
                            .ignoresSafeArea(edges: .bottom)
                            .shadow(color: Color.black.opacity(0.06), radius: 8, y: -2)
                    )
            }
            .navigationTitle("Order Print")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showStripeCheckout) {
                if let url = checkoutURL {
                    SafariView(url: url) {
                        showStripeCheckout = false
                        checkoutURL = nil
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showOrderConfirmation) {
                OrderConfirmationView {
                    showOrderConfirmation = false
                    dismiss()
                }
            }
        }
    }

    private var bodyWithLifecycleHandlers: some View {
        bodyContent
            .onAppear {
                placesSessionToken = UUID().uuidString
                coverPreviewCandidateIndex = 0
                lineQuantity = 1
                loadLastAddress()
                ensureValidProductSelection()
                scheduleEstimate()
            }
            .onDisappear {
                focusedField = nil
                estimateTask?.cancel()
                autocompleteTask?.cancel()
            }
    }

    private var bodyWithFieldHandlers: some View {
        bodyWithLifecycleHandlers
            .onChange(of: shipping.name) { _, _ in scheduleEstimate() }
            .onChange(of: shipping.street1) { _, newVal in
                scheduleAutocomplete(query: newVal)
                scheduleEstimate()
            }
            .onChange(of: shipping.city) { _, _ in scheduleEstimate() }
            .onChange(of: shipping.stateCode) { _, _ in scheduleEstimate() }
            .onChange(of: shipping.postcode) { _, _ in scheduleEstimate() }
            .onChange(of: shipping.countryCode) { _, _ in scheduleEstimate() }
            .onChange(of: shipping.phone) { _, _ in scheduleEstimate() }
            .onChange(of: shippingLevel) { _, _ in scheduleEstimate() }
            .onChange(of: orderCart.totalLineCount) { _, _ in scheduleEstimate() }
    }

    private var bodyWithModelHandlers: some View {
        bodyWithFieldHandlers
            .onChange(of: book.bookVersionId) { _, _ in
                coverPreviewCandidateIndex = 0
                ensureValidProductSelection()
                scheduleEstimate()
            }
            .onChange(of: selectedProductOptionId) { _, _ in
                scheduleEstimate()
            }
            .onChange(of: lineQuantity) { _, _ in
                scheduleEstimate()
            }
            .onChange(of: cartEstimate?.shippingMethods.map(\.level) ?? []) { _, levels in
                guard !levels.isEmpty else { return }
                if !levels.contains(shippingLevel), let first = levels.first {
                    shippingLevel = first
                }
            }
    }

    private var bodyWithAllHandlers: some View {
        bodyWithModelHandlers
            .onReceive(NotificationCenter.default.publisher(for: .orderComplete)) { _ in
                showStripeCheckout = false
                checkoutURL = nil
                fastCheckoutInstanceId = nil
                orderCart.clear()
                showOrderConfirmation = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .orderCancelled)) { _ in
                showStripeCheckout = false
                checkoutURL = nil
                fastCheckoutInstanceId = nil
            }
            .onChange(of: localAutocomplete.completions) { _, comps in
                guard useLocalAutocompleteFallback else { return }
                let transformed: [(AddressPrediction, MKLocalSearchCompletion)] = comps.prefix(8).enumerated().map { idx, c in
                    let id = "local::\(idx)::\(c.title)|\(c.subtitle)"
                    let description = c.subtitle.isEmpty ? c.title : "\(c.title), \(c.subtitle)"
                    return (AddressPrediction(placeId: id, description: description), c)
                }
                addressPredictions = transformed.map(\.0)
                localCompletionById = Dictionary(uniqueKeysWithValues: transformed.map { ($0.0.placeId, $0.1) })
            }
            .onChange(of: addressPredictions.map(\.id)) { _, _ in
                prefetchResolvedAddresses(for: addressPredictions)
            }
    }

    /// Single summary card: book preview + cart status + one-line trust copy (replaces stacked header + preview).
    private var compactOrderSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                orderCoverThumbnail(urls: coverPreviewURLs, pdfURL: coverPDFURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayBookTitle)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(book.pageCount) pages · \(isLandscapeBook ? "11 × 8.5\"" : "8.5 × 11\"")")
                        .font(.subheadline)
                        .foregroundColor(mutedTextColor)
                    Text(selectedProductOption?.title ?? "Choose a print format")
                        .font(.caption)
                        .foregroundColor(mutedTextColor)
                    if orderCart.totalLineCount > 0, activeStep == .cart || activeStep == .review {
                        Text("\(orderCart.totalLineCount) in cart")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(accentColor)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption2)
                    .foregroundColor(accentColor)
                Text("Secure checkout · Stripe · Lulu")
                    .font(.caption2)
                    .foregroundColor(mutedTextColor)
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var wizardProgressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let total = CGFloat(CheckoutStep.allCases.count)
                let filled = CGFloat(activeStep.rawValue + 1) / total
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(UIColor.secondarySystemFill))
                        .frame(height: 4)
                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(4, geo.size.width * filled), height: 4)
                }
            }
            .frame(height: 4)
            HStack(alignment: .firstTextBaseline) {
                Text(activeStep.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(activeStep.rawValue + 1)/\(CheckoutStep.allCases.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(mutedTextColor)
            }
            Text(activeStep.detailSubtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var wizardStepPanel: some View {
        switch activeStep {
        case .formatQuantity:
            VStack(alignment: .leading, spacing: 14) {
                printOptionsSection
                lineQuantitySection
            }
        case .shipping:
            VStack(alignment: .leading, spacing: 14) {
                shippingFormSection
                shippingSpeedSection
            }
        case .cart:
            cartSummarySection
        case .review:
            VStack(alignment: .leading, spacing: 14) {
                if showAccountLinkBanner {
                    accountLinkNudgeBanner
                }
                pricingEstimateSection
            }
        }
    }

    private var isAnonymousUser: Bool {
        Auth.auth().currentUser?.isAnonymous == true
    }

    private var showAccountLinkBanner: Bool {
        isAnonymousUser && !accountLinkBannerDismissed
    }

    /// Non-blocking nudge so an anonymous-auth purchase isn't lost if the device is lost. Reuses the
    /// exact Apple/Google linking mechanism from `MainTabView.bookBackupBanner` — no new auth flow.
    private var accountLinkNudgeBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Protect your purchase")
                        .font(.subheadline.weight(.semibold))
                    Text("Back up your account so your order history is never lost.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    accountLinkBannerDismissed = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                SignInWithAppleButton(.signIn) { request in
                    request.nonce = AuthenticationService.shared.prepareAppleSignIn()
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                        Task { await linkAppleAccountFromReview(credential: credential) }
                    case .failure(let error):
                        print("❌ Apple sign-in failed (order review nudge): \(error.localizedDescription)")
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button(action: linkGoogleAccountFromReview) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Color.white).frame(width: 18, height: 18)
                            Text("G").font(.system(size: 10, weight: .bold)).foregroundColor(.blue)
                        }
                        Text("Google")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.white)
                    .foregroundColor(Color.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private func linkAppleAccountFromReview(credential: ASAuthorizationAppleIDCredential) async {
        do {
            try await AuthenticationService.shared.linkAppleAccount(credential: credential)
        } catch {
            print("❌ Link Apple failed (order review nudge): \(error.localizedDescription)")
        }
    }

    private func linkGoogleAccountFromReview() {
        Task {
            do {
                try await AuthenticationService.shared.linkGoogleAccount()
            } catch {
                print("❌ Link Google failed (order review nudge): \(error.localizedDescription)")
            }
        }
    }

    private var wizardBottomActionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = wizardPrimaryDisabledHint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 12) {
                if activeStep != .formatQuantity {
                    Button("Back") { goToPreviousWizardStep() }
                        .font(.body.weight(.semibold))
                        .foregroundColor(accentColor)
                }
                wizardPrimaryButton
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var wizardPrimaryButton: some View {
        switch activeStep {
        case .formatQuantity:
            Button(action: addCurrentBookToCart) {
                Label("Add to cart & continue", systemImage: "cart.badge.plus")
                    .labelStyle(.titleAndIcon)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canAddToCart ? accentColor : Color(UIColor.secondarySystemFill))
                    .foregroundColor(canAddToCart ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canAddToCart)
        case .shipping:
            Button {
                activeStep = .cart
            } label: {
                Text("Continue to cart")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isFormValid ? accentColor : Color(UIColor.secondarySystemFill))
                    .foregroundColor(isFormValid ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!isFormValid)
        case .cart:
            Button {
                activeStep = .review
            } label: {
                Text("Continue to review")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canProceedFromCartToReview ? accentColor : Color(UIColor.secondarySystemFill))
                    .foregroundColor(canProceedFromCartToReview ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canProceedFromCartToReview)
        case .review:
            reviewCheckoutPrimaryButton
        }
    }

    @ViewBuilder
    private var reviewCheckoutPrimaryButton: some View {
        Button(action: startCartCheckout) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "creditcard.fill")
                    if let ce = cartEstimate {
                        Text("Checkout — \(formatMoney(cents: ce.estimatedTotalCents))")
                    } else {
                        Text("Checkout")
                    }
                }
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canInvokeCheckout ? accentColor : Color(UIColor.secondarySystemFill))
            .foregroundColor(canInvokeCheckout ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(
                color: canInvokeCheckout ? Color.black.opacity(0.12) : .clear,
                radius: 6,
                x: 0,
                y: 3
            )
        }
        .disabled(!canInvokeCheckout)
    }

    private var canProceedFromCartToReview: Bool {
        !orderCart.items.isEmpty && !cartHasInvalidLines
    }

    /// Review primary enabled when there is something to pay for and gated checkout is allowed.
    private var canInvokeCheckout: Bool {
        !orderCart.items.isEmpty
            && !isSubmitting
            && canCheckoutCart
            && checkoutURL == nil
    }

    private var wizardPrimaryDisabledHint: String? {
        switch activeStep {
        case .formatQuantity:
            if canAddToCart { return nil }
            if !hasAnyEligibleProductOption {
                return "No print formats match this book’s page count yet."
            }
            if !selectedProductIsEligible {
                return "Pick an available print format, then set quantity."
            }
            return "Choose a valid quantity (1–99)."
        case .shipping:
            return isFormValid ? nil : "Complete all required shipping fields to continue."
        case .cart:
            if orderCart.items.isEmpty { return "Add this book to your cart on the Format step." }
            if cartHasInvalidLines { return "Fix or remove the cart line so it matches the print format." }
            return nil
        case .review:
            if canInvokeCheckout || isSubmitting { return nil }
            if orderCart.items.isEmpty { return "Your cart is empty. Go back to Format to add a print line." }
            if cartHasInvalidLines { return "Fix or remove the invalid cart line before checkout." }
            if !isFormValid { return "Complete a valid shipping address before checkout." }
            if isEstimating { return "Getting price from Lulu…" }
            if cartEstimate == nil {
                return "Enter a complete address and wait for a price estimate."
            }
            return "Unable to checkout yet. Check warnings above or try again in a moment."
        }
    }

    private func goToPreviousWizardStep() {
        switch activeStep {
        case .formatQuantity: break
        case .shipping: activeStep = .formatQuantity
        case .cart: activeStep = .shipping
        case .review: activeStep = .cart
        }
    }

    private var displayBookTitle: String {
        book.bookCatalogDisplayTitle
    }

    /// Remote URLs to try for the order card thumbnail (cover, then page art / renders).
    private var coverPreviewURLCandidates: [String] {
        var ordered: [String] = []
        if let u = book.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            ordered.append(u)
        }
        let sortedPages = book.pages.sorted { $0.pageIndex < $1.pageIndex }
        for p in sortedPages {
            if let u = p.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                ordered.append(u)
            }
            if let u = p.renderedPageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                ordered.append(u)
            }
        }
        var seen = Set<String>()
        return ordered.filter { seen.insert($0).inserted }
    }

    /// Real print-cover artifact URL when Firebase `coverURL` / `coverStoragePath` indicate `cover.pdf`.
    private var coverPDFURL: URL? {
        book.printCoverPDFURL
    }

    private var coverPreviewURLs: [URL] {
        var urls: [URL] = []
        var seenAbsolute = Set<String>()
        for s in coverPreviewURLCandidates {
            guard shouldAttemptRemoteCoverImage(urlString: s), let url = URL(string: s) else { continue }
            if seenAbsolute.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    private func shouldAttemptRemoteCoverImage(urlString: String) -> Bool {
        let lower = urlString.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        if isLikelyPDF(urlString: lower) { return false }
        return true
    }

    private func isLikelyPDF(urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.contains(".pdf")
    }

    @ViewBuilder
    private func orderCoverThumbnail(urls: [URL], pdfURL: URL?) -> some View {
        if let pdfURL {
            RemotePDFThumbnailView(
                url: pdfURL,
                targetSize: CGSize(width: 160, height: 128),
                layout: book.coverFlatLayoutKind,
                panel: .front,
                cacheRevision: book.coverThumbnailCacheRevision,
                cacheIdentity: book.coverStoragePath ?? ""
            ) {
                orderCoverPlaceholder
            }
            .frame(width: 80, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        } else if urls.isEmpty {
            orderCoverPlaceholder
        } else {
            let safeIdx = min(max(0, coverPreviewCandidateIndex), urls.count - 1)
            let url = urls[safeIdx]
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    ZStack {
                        Color(UIColor.tertiarySystemFill)
                        ProgressView()
                    }
                case .failure:
                    Color(UIColor.tertiarySystemFill)
                        .onAppear {
                            if coverPreviewCandidateIndex < urls.count - 1 {
                                coverPreviewCandidateIndex += 1
                            }
                        }
                @unknown default:
                    Color(UIColor.tertiarySystemFill)
                }
            }
            .frame(width: 80, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var orderCoverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        Color(UIColor.tertiarySystemFill),
                        Color(UIColor.secondarySystemFill)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 80, height: 64)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
    }

    private var productDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Product")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text("\(isLandscapeBook ? "11 x 8.5\"" : "8.5 x 11\"") \(selectedProductOption?.title ?? "Hardcover (Casewrap)"), Full Color, Matte Finish")
                .font(.subheadline)
        }
    }

    private var printOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Print Format Options")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(mutedTextColor)
            ForEach(productOptions) { option in
                let availability = optionAvailability(option)
                let isSelected = selectedProductOptionId == option.id
                Button {
                    guard availability.available else { return }
                    selectedProductOptionId = option.id
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(availability.available ? .primary : .secondary)
                            if isSelected {
                                Text("Selected")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(accentColor.opacity(0.15))
                                    .foregroundColor(accentColor)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }
                        Text(option.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(option.requirementsText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let reason = availability.reason {
                            Text(reason)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(availability.available ? fieldBackground : Color(UIColor.tertiarySystemFill))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? accentColor : cardStroke,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
                    .opacity(availability.available ? 1.0 : 0.65)
                }
                .buttonStyle(.plain)
                .disabled(!availability.available)
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var lineQuantitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quantity (this book)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(mutedTextColor)
            if !hasAnyEligibleProductOption {
                Text("No print formats match \(book.pageCount) pages yet.")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if !selectedProductIsEligible {
                Text("Choose an available print format, then set how many copies to add.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Stepper(value: $lineQuantity, in: 1...99) {
                    Text("Copies to add: \(lineQuantity)")
                        .font(.subheadline)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var cartSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if orderCart.items.isEmpty {
                Text("Nothing in your cart yet. Tap Back, then on Format use Add to cart & continue.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(orderCart.items) { item in
                    cartLineRow(item)
                }
                if cartHasInvalidLines {
                    Text("Fix or remove invalid lines before checkout (page count may have changed since the item was added).")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func cartLineRow(_ item: OrderCartItem) -> some View {
        let status = cartLineAvailability(item)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                cartLineThumbnail(item: item)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text("\(item.productTitle) • \(item.snapshotPageCount) p.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !status.available, let reason = status.reason {
                        Text(reason)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.orange)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    orderCart.remove(itemId: item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.medium))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from cart")
            }
            HStack {
                Text("Qty")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Stepper(value: Binding(
                    get: { item.quantity },
                    set: { orderCart.updateQuantity(itemId: item.id, quantity: $0) }
                ), in: 1...99) {
                    Text("\(item.quantity)")
                        .font(.subheadline.monospacedDigit())
                        .frame(minWidth: 28, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func cartLineThumbnail(item: OrderCartItem) -> some View {
        let pdfURL = remotePDFURL(from: item.coverPDFURL ?? item.coverURL)
        let urls = cartThumbnailImageURLs(for: item)
        if let pdfURL {
            let layout: BookCoverFlatLayoutKind = item.isLandscape
                ? .kidsBook(pageCount: max(1, item.snapshotPageCount))
                : .portraitCasewrap(pageCount: item.snapshotPageCount)
            RemotePDFThumbnailView(
                url: pdfURL,
                targetSize: CGSize(width: 88, height: 112),
                layout: layout,
                panel: .front,
                cacheRevision: item.coverThumbnailCacheRevision ?? "",
                cacheIdentity: ""
            ) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.tertiarySystemFill))
            }
            .frame(width: 44, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        } else if let u = urls.first {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    ZStack {
                        Color(UIColor.tertiarySystemFill)
                        ProgressView()
                    }
                case .failure:
                    Color(UIColor.tertiarySystemFill)
                        .overlay(
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(.secondary)
                        )
                @unknown default:
                    Color(UIColor.tertiarySystemFill)
                }
            }
            .frame(width: 44, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.tertiarySystemFill))
                .frame(width: 44, height: 56)
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.secondary)
                )
        }
    }

    private func remotePDFURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw.lowercased().hasPrefix("http"),
              raw.lowercased().contains(".pdf"),
              let url = URL(string: raw) else {
            return nil
        }
        return url
    }

    private func cartThumbnailImageURLs(for item: OrderCartItem) -> [URL] {
        let candidates = [item.coverURL, item.fallbackImageURL, item.fallbackRenderedURL]
        var seen = Set<String>()
        return candidates.compactMap { raw in
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  trimmed.lowercased().hasPrefix("http"),
                  !trimmed.lowercased().contains(".pdf"),
                  let url = URL(string: trimmed) else {
                return nil
            }
            guard seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
    }

    @ViewBuilder
    private var pricingEstimateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Estimate (this book × quantity)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(mutedTextColor)
            if activeStep == .review {
                Text("Total includes printing and shipping to your address.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isEstimating {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Getting price from Lulu…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if orderCart.items.isEmpty {
                emptyCartPricingCopy
                if let ce = cartEstimate {
                    cartEstimateBreakdown(ce)
                }
            } else {
                if cartHasInvalidLines {
                    Text("Shipping estimate is hidden until all cart lines pass format checks.")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if let ce = cartEstimate {
                    cartEstimateBreakdown(ce)
                } else if isFormValid {
                    Text("Enter a complete address to refresh your cart estimate.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Fill out shipping to see cart pricing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let ce = cartEstimate {
                estimateAddressWarnings(ce.warnings, suggested: ce.suggestedAddress)
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var emptyCartPricingCopy: some View {
        if !hasAnyEligibleProductOption {
            Text("This book has \(book.pageCount) pages. None of the listed print formats support that page count yet.")
                .font(.caption)
                .foregroundColor(.orange)
        } else if !selectedProductIsEligible {
            Text("Pick one of the available print formats to view pricing.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if cartEstimate == nil {
            if isFormValid {
                Text("Enter a complete address to see your estimate.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Fill out shipping to see pricing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func cartEstimateBreakdown(_ ce: CartCheckoutEstimate) -> some View {
        let booksSubtotal = ce.booksSubtotalCents
        let shippingSubtotal = ce.orderShippingCents
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(ce.lines.enumerated()), id: \.offset) { _, line in
                let title = line.productTitle.isEmpty ? "Book" : line.productTitle
                let bookLineCents = line.lineBookBaseCents
                estimateRow(
                    label: "\(title) ×\(line.quantity) (printing)",
                    amountCents: bookLineCents
                )
            }
            Divider()
            estimateRow(label: "Books subtotal", amountCents: booksSubtotal)
            estimateRow(
                label: "Shipping (\(selectedShippingLevelLabel))",
                amountCents: shippingSubtotal
            )
            Divider()
            estimateRow(
                label: "Estimated total",
                amountCents: ce.estimatedTotalCents,
                emphasized: true
            )
            if ce.fallback {
                Text("Live Lulu estimate is temporarily unavailable for one or more lines. Total may adjust at checkout.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private func estimateAddressWarnings(_ warnings: [LuluEstimateWarning], suggested: SuggestedShippingAddress?) -> some View {
        let addressWarnings = warnings.filter { warning in
            !warning.message.isEmpty && warning.type != "lulu_error"
        }
        if !addressWarnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Address validation")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                ForEach(Array(addressWarnings.enumerated()), id: \.offset) { _, w in
                    if !w.message.isEmpty {
                        Text(w.message)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
                if let sug = suggested, suggestedAddressIsUsable(sug) {
                    Button("Use Lulu’s suggested address") {
                        applyLuluSuggested(sug)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(.top, 4)
        }
    }

    private func estimateRow(label: String, amountCents: Int, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .body.weight(.semibold) : .subheadline)
            Spacer()
            Text(formatMoney(cents: amountCents))
                .font(emphasized ? .body.weight(.bold) : .subheadline)
        }
    }

    private func formatMoney(cents: Int) -> String {
        let v = Double(cents) / 100.0
        return String(format: "$%.2f", v)
    }

    /// Label for the selected shipping level; includes Lulu ETA in parentheses when the API returned window fields/chips.
    private var selectedShippingLevelLabel: String {
        if let methods = cartEstimate?.shippingMethods,
           let match = methods.first(where: { $0.level == shippingLevel }) {
            if let eta = shippingArrivalText(for: match) {
                return "\(match.label) (\(eta))"
            }
            return match.label
        }
        return defaultShippingOptions.first(where: { $0.id == shippingLevel })?.label ?? shippingLevel
    }

    private var hasLiveShippingMethodEstimates: Bool {
        !(cartEstimate?.shippingMethods.isEmpty ?? true)
    }

    private var shippingOptionsForPicker: [ShippingOptionDisplay] {
        if let methods = cartEstimate?.shippingMethods, !methods.isEmpty {
            return methods.map { method in
                let cents = method.shippingCents
                return ShippingOptionDisplay(
                    id: method.level,
                    label: method.label,
                    etaText: shippingArrivalText(for: method),
                    shippingPriceCents: cents > 0 ? cents : nil
                )
            }
        }
        return defaultShippingOptions.map {
            ShippingOptionDisplay(id: $0.id, label: $0.label, etaText: nil, shippingPriceCents: nil)
        }
    }

    private func shippingArrivalText(for method: ShippingMethodEstimate) -> String? {
        if let minDays = method.estimatedArrivalMinDays, let maxDays = method.estimatedArrivalMaxDays {
            if minDays == maxDays {
                return "\(minDays) business day\(minDays == 1 ? "" : "s")"
            }
            return "\(minDays)–\(maxDays) business days"
        }
        if let minDateRaw = method.estimatedArrivalMinDate,
           let maxDateRaw = method.estimatedArrivalMaxDate,
           let minDate = parseISODate(minDateRaw),
           let maxDate = parseISODate(maxDateRaw) {
            let cal = Calendar.current
            let startOfToday = cal.startOfDay(for: Date())
            let startMin = cal.startOfDay(for: minDate)
            let startMax = cal.startOfDay(for: maxDate)
            if let minOffset = cal.dateComponents([.day], from: startOfToday, to: startMin).day,
               let maxOffset = cal.dateComponents([.day], from: startOfToday, to: startMax).day,
               minOffset >= 0, maxOffset >= minOffset {
                if minOffset == maxOffset {
                    return "\(minOffset) day\(minOffset == 1 ? "" : "s")"
                }
                return "\(minOffset)-\(maxOffset) days"
            }
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            if Calendar.current.isDate(minDate, inSameDayAs: maxDate) {
                return fmt.string(from: minDate)
            }
            return "\(fmt.string(from: minDate))-\(fmt.string(from: maxDate))"
        }
        return nil
    }

    private func parseISODate(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let fullDate = iso.date(from: value) {
            return fullDate
        }
        let dayOnly = DateFormatter()
        dayOnly.calendar = Calendar(identifier: .gregorian)
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.dateFormat = "yyyy-MM-dd"
        return dayOnly.date(from: value)
    }

    private var shippingFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shipping Address")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(mutedTextColor)
                Text("Used for delivery and live price estimate")
                    .font(.caption)
                    .foregroundColor(mutedTextColor)
            }

            TextField("Full Name", text: $shipping.name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(cardStroke, lineWidth: 1)
                )
                .textContentType(.name)

            VStack(alignment: .leading, spacing: 0) {
                TextField("Street Address (search)", text: $shipping.street1)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(cardStroke, lineWidth: 1)
                    )
                    .textContentType(.streetAddressLine1)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .street)

                if focusedField == .street, !addressPredictions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(addressPredictions) { pred in
                            Button {
                                selectPrediction(pred)
                            } label: {
                                HStack {
                                    Text(pred.description)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(cardStroke, lineWidth: 1)
                    )
                    .padding(.top, 6)
                }
            }

            HStack(spacing: 12) {
                TextField("City", text: $shipping.city)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(cardStroke, lineWidth: 1)
                    )
                    .textContentType(.addressCity)
                TextField("State", text: $shipping.stateCode)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(cardStroke, lineWidth: 1)
                    )
                    .textContentType(.addressState)
            }
            HStack(spacing: 12) {
                TextField("ZIP", text: $shipping.postcode)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(cardStroke, lineWidth: 1)
                    )
                    .textContentType(.postalCode)
                TextField("Country (e.g. US)", text: $shipping.countryCode)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(cardStroke, lineWidth: 1)
                    )
                    .textContentType(.countryName)
                    .textInputAutocapitalization(.characters)
            }
            TextField("Phone", text: $shipping.phone)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(cardStroke, lineWidth: 1)
                )
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)

            if !shippingValidationIssues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before pricing, fix:")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    ForEach(Array(shippingValidationIssues.enumerated()), id: \.offset) { _, issue in
                        Text("• \(issue)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var shippingSpeedSection: some View {
        let options = shippingOptionsForPicker
        return VStack(alignment: .leading, spacing: 12) {
            shippingSpeedHeader

            if !isFormValid {
                Text("Complete your address to see delivery estimates.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isEstimating && cartEstimate == nil {
                shippingSpeedLoadingRow
            } else {
                shippingSpeedOptionsList(options)
            }

            shippingSpeedFooter
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var shippingSpeedHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Shipping speed")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(mutedTextColor)
            Text("Choose after your address is complete — options refresh with Lulu delivery windows and indicative rates.")
                .font(.caption)
                .foregroundColor(mutedTextColor)
        }
    }

    private var shippingSpeedLoadingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Fetching delivery windows from Lulu…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var shippingSpeedFooter: some View {
        if isFormValid {
            if hasLiveShippingMethodEstimates {
                Text("Estimates and indicative prices come from Lulu for your full cart. The Review step shows the live total (books + shipping — each book ships in its own package) for your selection.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if !isEstimating {
                Text("Shipping cost and delivery windows appear after Lulu returns data for this address.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func shippingSpeedOptionsList(_ options: [ShippingOptionDisplay]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                shippingSpeedOptionRow(opt)
                if idx < options.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func shippingSpeedOptionRow(_ opt: ShippingOptionDisplay) -> some View {
        let title = opt.etaText.map { "\(opt.label) (\($0))" } ?? opt.label
        return Button {
            shippingLevel = opt.id
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: shippingLevel == opt.id ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundColor(shippingLevel == opt.id ? accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    if let c = opt.shippingPriceCents {
                        Text(formatMoney(cents: c) + " (Lulu rate for this cart)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isFormValid: Bool {
        shippingValidationIssues.isEmpty
    }

    private var selectedProductOption: PrintProductOption? {
        productOptions.first(where: { $0.id == selectedProductOptionId })
    }

    private var hasAnyEligibleProductOption: Bool {
        productOptions.contains { optionAvailability($0).available }
    }

    private var selectedProductIsEligible: Bool {
        guard let selectedProductOption else { return false }
        return optionAvailability(selectedProductOption).available
    }

    private var canAddToCart: Bool {
        hasAnyEligibleProductOption && selectedProductIsEligible && lineQuantity >= 1 && lineQuantity <= 99
    }

    private var cartHasInvalidLines: Bool {
        orderCart.items.contains { !cartLineAvailability($0).available }
    }

    /// Cart checkout only after live estimate and all lines remain valid for stored page counts.
    private var canCheckoutCart: Bool {
        !orderCart.items.isEmpty
            && !cartHasInvalidLines
            && isFormValid
            && cartEstimate != nil
            && !isEstimating
    }

    private func cartLineAvailability(_ item: OrderCartItem) -> (available: Bool, reason: String?) {
        let opts = Self.printProductOptions(isLandscape: item.isLandscape)
        guard let opt = opts.first(where: { $0.id == item.productOptionId }) else {
            return (false, "This print format isn’t recognized. Remove the line and add the book again.")
        }
        return optionAvailability(opt, pageCount: item.snapshotPageCount)
    }

    private func optionAvailability(_ option: PrintProductOption) -> (available: Bool, reason: String?) {
        optionAvailability(option, pageCount: book.pageCount)
    }

    private func optionAvailability(_ option: PrintProductOption, pageCount: Int) -> (available: Bool, reason: String?) {
        if option.id == "kids_coil_bound" {
            return (false, "Coil binding is temporarily unavailable while we finalize cover templates for Lulu.")
        }
        if pageCount < option.minPages {
            return (false, "Add \(option.minPages - pageCount) more page(s) to unlock this format.")
        }
        if pageCount > option.maxPages {
            return (false, "This format supports up to \(option.maxPages) pages.")
        }
        return (true, nil)
    }

    private func ensureValidProductSelection() {
        if let selected = selectedProductOption, optionAvailability(selected).available {
            return
        }
        if let preferredHardcover = productOptions.first(where: {
            $0.id.contains("hardcover") && optionAvailability($0).available
        }) {
            selectedProductOptionId = preferredHardcover.id
            return
        }
        if let firstAvailable = productOptions.first(where: { optionAvailability($0).available }) {
            selectedProductOptionId = firstAvailable.id
            return
        }
        selectedProductOptionId = productOptions.first?.id
    }

    private func scheduleEstimate() {
        estimateTask?.cancel()
        ensureValidProductSelection()
        let addrSnapshot = normalizedShippingForLulu(shipping)
        let levelSnapshot = shippingLevel
        let versionId = book.bookVersionId
        let cartSnapshot = orderCart.items

        if cartSnapshot.isEmpty {
            guard hasAnyEligibleProductOption else {
                cartEstimate = nil
                errorMessage = "No available print formats for \(book.pageCount) pages. Adjust page count to match a listed format."
                return
            }
            guard selectedProductIsEligible, let selectedProductOptionId else {
                cartEstimate = nil
                errorMessage = "Choose an available print format to continue."
                return
            }
            guard isFormValid else {
                cartEstimate = nil
                return
            }
            errorMessage = nil
            let qty = lineQuantity
            estimateTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 480_000_000)
                if Task.isCancelled { return }
                isEstimating = true
                errorMessage = nil
                do {
                    let payload = [(versionId, selectedProductOptionId as String?, qty)]
                    let e = try await OrderService.shared.prepareCartCheckoutPricing(
                        items: payload,
                        shippingAddress: addrSnapshot,
                        shippingLevel: levelSnapshot
                    )
                    if Task.isCancelled { return }
                    cartEstimate = e
                    isEstimating = false
                    print(
                        "📦 prepareCartCheckoutQuote (preview) ok total=\(e.estimatedTotalCents) " +
                        "qty=\(qty) level=\(levelSnapshot)"
                    )
                } catch {
                    if Task.isCancelled { return }
                    isEstimating = false
                    cartEstimate = nil
                    errorMessage = OrderService.userFacingCallableErrorMessage(error)
                    OrderService.printCallableDiagnostics(error, context: "prepareCartCheckoutQuote (preview)")
                    #if DEBUG
                    print("📦 prepareCartCheckoutQuote (preview) failed: \(OrderService.debugCallableErrorFootnote(error, function: "prepareCartCheckoutQuote"))")
                    #else
                    print("📦 prepareCartCheckoutQuote (preview) failed: \(error.localizedDescription)")
                    #endif
                }
            }
        } else {
            guard isFormValid else {
                cartEstimate = nil
                return
            }
            if cartSnapshot.contains(where: { !cartLineAvailability($0).available }) {
                cartEstimate = nil
                isEstimating = false
                errorMessage = nil
                return
            }
            errorMessage = nil
            estimateTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 480_000_000)
                if Task.isCancelled { return }
                isEstimating = true
                errorMessage = nil
                do {
                    let payload = cartSnapshot.map { ($0.bookVersionId, $0.productOptionId as String?, $0.quantity) }
                    let e = try await OrderService.shared.prepareCartCheckoutPricing(
                        items: payload,
                        shippingAddress: addrSnapshot,
                        shippingLevel: levelSnapshot
                    )
                    if Task.isCancelled { return }
                    cartEstimate = e
                    isEstimating = false
                    print("📦 prepareCartCheckoutQuote ok total=\(e.estimatedTotalCents) lines=\(e.lines.count) level=\(levelSnapshot)")
                } catch {
                    if Task.isCancelled { return }
                    isEstimating = false
                    cartEstimate = nil
                    errorMessage = OrderService.userFacingCallableErrorMessage(error)
                    OrderService.printCallableDiagnostics(error, context: "prepareCartCheckoutQuote (cart estimate)")
                    #if DEBUG
                    print("📦 prepareCartCheckoutQuote failed: \(OrderService.debugCallableErrorFootnote(error, function: "prepareCartCheckoutQuote"))")
                    #else
                    print("📦 prepareCartCheckoutQuote failed: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    private func scheduleAutocomplete(query: String) {
        autocompleteTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let focused = focusedField == .street
        guard trimmed.count >= 3, focused else {
            addressPredictions = []
            localCompletionById = [:]
            return
        }

        if useLocalAutocompleteFallback {
            localAutocomplete.update(query: trimmed)
            return
        }

        autocompleteRequestSerial += 1
        let requestSerial = autocompleteRequestSerial
        let token = placesSessionToken
        let country = shipping.countryCode.trimmingCharacters(in: .whitespaces)
        let countryHint = country.count == 2 ? country : "US"
        autocompleteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }
            guard requestSerial == autocompleteRequestSerial else { return }
            guard trimmed.count >= 3 else { return }
            do {
                let preds = try await OrderService.shared.autocompleteAddress(
                    query: trimmed,
                    sessionToken: token,
                    countryCode: countryHint
                )
                if Task.isCancelled { return }
                guard requestSerial == autocompleteRequestSerial else { return }
                addressPredictions = preds
            } catch {
                if Task.isCancelled { return }
                guard requestSerial == autocompleteRequestSerial else { return }
                if shouldFallbackToLocalGooglePlacesError(error) {
                    useLocalAutocompleteFallback = true
                    addressPredictions = []
                    localCompletionById = [:]
                    localAutocomplete.update(query: trimmed)
                    print("📦 autocompleteAddress failed; using MapKit fallback: \(error.localizedDescription)")
                } else {
                    addressPredictions = []
                    print("📦 autocompleteAddress: \(error.localizedDescription)")
                }
            }
        }
    }

    /// One-time switch to MapKit when Places (server) is unavailable, key-blocked, or legacy/misconfigured.
    private func shouldFallbackToLocalGooglePlacesError(_ error: Error) -> Bool {
        let msg = error.localizedDescription
        let u = msg.uppercased()
        if u.contains("NOT FOUND") { return true }
        if msg.contains("LegacyApiNotActivatedMapError") { return true }
        if u.contains("LEGACY") && u.contains("NOT ACTIVATED") { return true }
        if u.contains("REQUEST_DENIED") { return true }
        if u.contains("PERMISSION_DENIED") { return true }
        if u.contains("FAILED-PRECONDITION") { return true }
        if u.contains("FAILED PRECONDITION") { return true }
        if u.contains("UNAVAILABLE") { return true }
        if u.contains("RESOURCE_EXHAUSTED") { return true }
        return false
    }

    private func selectPrediction(_ pred: AddressPrediction) {
        addressPredictions = []
        focusedField = nil
        applyPredictionImmediateFill(pred)
        scheduleEstimate()
        if pred.placeId.hasPrefix("local::"), let completion = localCompletionById[pred.placeId] {
            Task {
                let request = MKLocalSearch.Request(completion: completion)
                do {
                    let response = try await MKLocalSearch(request: request).start()
                    if let mapItem = response.mapItems.first {
                        let placemark = mapItem.placemark
                        await MainActor.run {
                            shipping.street1 = [placemark.subThoroughfare, placemark.thoroughfare]
                                .compactMap { $0 }
                                .joined(separator: " ")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if shipping.street1.isEmpty { shipping.street1 = pred.description }
                            if let city = placemark.locality, !city.isEmpty { shipping.city = city }
                            if let state = placemark.administrativeArea, !state.isEmpty { shipping.stateCode = state }
                            if let zip = placemark.postalCode, !zip.isEmpty { shipping.postcode = zip }
                            if let cc = placemark.isoCountryCode, !cc.isEmpty { shipping.countryCode = cc }
                        }
                        scheduleEstimate()
                        return
                    }
                } catch {
                    print("📦 local resolve failed: \(error.localizedDescription)")
                }
                await MainActor.run {
                    shipping.street1 = pred.description
                }
                scheduleEstimate()
            }
            return
        }

        if let cached = resolvedAddressByPlaceId[pred.placeId] {
            applyResolvedAddress(cached, fallbackDescription: pred.description)
            placesSessionToken = UUID().uuidString
            scheduleEstimate()
            return
        }

        Task {
            do {
                let (_, resolved) = try await OrderService.shared.resolveAddressPlace(
                    placeId: pred.placeId,
                    sessionToken: placesSessionToken
                )
                await MainActor.run {
                    resolvedAddressByPlaceId[pred.placeId] = resolved
                    applyResolvedAddress(resolved, fallbackDescription: pred.description)
                    placesSessionToken = UUID().uuidString
                }
                scheduleEstimate()
            } catch {
                print("📦 resolveAddressPlace: \(error.localizedDescription)")
            }
        }
    }

    private func prefetchResolvedAddresses(for predictions: [AddressPrediction]) {
        guard !useLocalAutocompleteFallback else { return }
        guard !predictions.isEmpty else { return }
        detailsPrefetchSerial += 1
        let serial = detailsPrefetchSerial
        let token = placesSessionToken
        let candidates = predictions
            .filter { !$0.placeId.hasPrefix("local::") }
            .prefix(8)

        for pred in candidates where resolvedAddressByPlaceId[pred.placeId] == nil {
            Task {
                do {
                    let (_, resolved) = try await OrderService.shared.resolveAddressPlace(
                        placeId: pred.placeId,
                        sessionToken: token
                    )
                    await MainActor.run {
                        guard serial == detailsPrefetchSerial else { return }
                        resolvedAddressByPlaceId[pred.placeId] = resolved
                    }
                } catch {
                    // Best-effort prefetch; selection flow can still resolve on demand.
                }
            }
        }
    }

    private func applyResolvedAddress(_ resolved: ShippingAddress, fallbackDescription: String) {
        if !resolved.street1.isEmpty {
            shipping.street1 = resolved.street1
        } else if !fallbackDescription.isEmpty {
            shipping.street1 = fallbackDescription
        }
        if !resolved.city.isEmpty { shipping.city = resolved.city }
        if !resolved.stateCode.isEmpty { shipping.stateCode = resolved.stateCode }
        if !resolved.postcode.isEmpty { shipping.postcode = resolved.postcode }
        if !resolved.countryCode.isEmpty { shipping.countryCode = resolved.countryCode }
    }

    /// Optimistic local parse so address fields update instantly on suggestion tap.
    private func applyPredictionImmediateFill(_ pred: AddressPrediction) {
        if pred.placeId.hasPrefix("local::"), let completion = localCompletionById[pred.placeId] {
            let street = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !street.isEmpty {
                shipping.street1 = street
            } else if !pred.description.isEmpty {
                shipping.street1 = pred.description
            }

            let parsed = parseAddressComponents(from: completion.subtitle)
            if !parsed.city.isEmpty { shipping.city = parsed.city }
            if !parsed.stateCode.isEmpty { shipping.stateCode = parsed.stateCode }
            if !parsed.postcode.isEmpty { shipping.postcode = parsed.postcode }
            if !parsed.countryCode.isEmpty { shipping.countryCode = parsed.countryCode }
            return
        }

        let parsed = parseAddressComponents(from: pred.description)
        if !parsed.street1.isEmpty {
            shipping.street1 = parsed.street1
        } else if !pred.description.isEmpty {
            shipping.street1 = pred.description
        }
        if !parsed.city.isEmpty { shipping.city = parsed.city }
        if !parsed.stateCode.isEmpty { shipping.stateCode = parsed.stateCode }
        if !parsed.postcode.isEmpty { shipping.postcode = parsed.postcode }
        if !parsed.countryCode.isEmpty { shipping.countryCode = parsed.countryCode }
    }

    /// Best-effort parser for strings like:
    /// "1609 Creekvista Dr, San Jose, CA 95120, USA"
    private func parseAddressComponents(from description: String) -> (
        street1: String,
        city: String,
        stateCode: String,
        postcode: String,
        countryCode: String
    ) {
        let rawParts = description
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawParts.isEmpty else {
            return ("", "", "", "", "")
        }

        var street1 = ""
        var city = ""
        var stateCode = ""
        var postcode = ""
        var countryCode = ""

        if rawParts.count >= 1 { street1 = rawParts[0] }
        if rawParts.count >= 2 { city = rawParts[1] }

        if rawParts.count >= 3 {
            let region = rawParts[2]
            let tokens = region.split(whereSeparator: \.isWhitespace).map(String.init)
            if let first = tokens.first {
                let firstUpper = first.uppercased()
                if firstUpper.count == 2 {
                    stateCode = firstUpper
                }
            }
            if tokens.count >= 2 {
                postcode = tokens.dropFirst().joined(separator: " ")
            } else if stateCode.isEmpty {
                // Non-US fallback where region may be postal code only.
                postcode = region
            }
        }

        if rawParts.count >= 4 {
            let country = rawParts[3].uppercased()
            if country == "USA" || country == "UNITED STATES" || country == "US" {
                countryCode = "US"
            } else if country.count == 2 {
                countryCode = country
            }
        }

        return (street1, city, stateCode, postcode, countryCode)
    }

    private func suggestedAddressIsUsable(_ s: SuggestedShippingAddress) -> Bool {
        !s.street1.isEmpty || !s.city.isEmpty || !s.postcode.isEmpty
    }

    private func applyLuluSuggested(_ s: SuggestedShippingAddress) {
        if !s.street1.isEmpty { shipping.street1 = s.street1 }
        if !s.city.isEmpty { shipping.city = s.city }
        if !s.stateCode.isEmpty { shipping.stateCode = s.stateCode }
        if !s.postcode.isEmpty { shipping.postcode = s.postcode }
        if !s.countryCode.isEmpty { shipping.countryCode = s.countryCode }
        scheduleEstimate()
    }

    private func loadLastAddress() {
        if let data = UserDefaults.standard.data(forKey: lastShippingDefaultsKey),
           let decoded = try? JSONDecoder().decode(ShippingAddress.self, from: data) {
            shipping = decoded
        }
    }

    private func saveLastAddress() {
        if let data = try? JSONEncoder().encode(shipping) {
            UserDefaults.standard.set(data, forKey: lastShippingDefaultsKey)
        }
    }

    private var lastShippingDefaultsKey: String {
        if let uid = Auth.auth().currentUser?.uid, !uid.isEmpty {
            return "order_last_shipping_\(uid)"
        }
        return "order_last_shipping"
    }

    private func addCurrentBookToCart() {
        focusedField = nil
        ensureValidProductSelection()
        guard canAddToCart, let optId = selectedProductOptionId, let opt = selectedProductOption else {
            errorMessage = "Choose an available print format and quantity before adding to cart."
            return
        }
        // Single-book checkout: only one cart line; replace any existing line when adding a book.
        orderCart.clear()
        let firstPageImageURL = book.pages
            .sorted { $0.pageIndex < $1.pageIndex }
            .compactMap { $0.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        let firstRenderedURL = book.pages
            .sorted { $0.pageIndex < $1.pageIndex }
            .compactMap { $0.renderedPageURL?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        orderCart.addOrIncrement(
            bookVersionId: book.bookVersionId,
            displayTitle: displayBookTitle,
            coverURL: book.coverURL,
            coverPDFURL: coverPDFURL?.absoluteString,
            coverThumbnailCacheRevision: book.coverThumbnailCacheRevision,
            fallbackImageURL: firstPageImageURL,
            fallbackRenderedURL: firstRenderedURL,
            productOptionId: optId,
            productTitle: opt.title,
            quantity: lineQuantity,
            snapshotPageCount: book.pageCount,
            isLandscape: isLandscapeBook
        )
        lineQuantity = 1
        errorMessage = nil
        activeStep = .shipping
        scheduleEstimate()
    }

    /// True when server quote exists, fast path is allowed, and quote is not expired.
    private func isFastCheckoutEligible(_ e: CartCheckoutEstimate?) -> Bool {
        guard let e else { return false }
        if e.fastCheckoutEnabled == false { return false }
        guard let q = e.quoteId, !q.isEmpty,
              let h = e.cartHash, !h.isEmpty else { return false }
        guard let ms = e.quoteExpiresAtMillis else { return true }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return ms - 60_000 > now
    }

    private func estimateNeedsRefreshBeforePay(_ e: CartCheckoutEstimate?) -> Bool {
        guard let e else { return true }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if let ms = e.quoteExpiresAtMillis, ms - 60_000 <= now { return true }
        return false
    }

    private func startCartCheckout() {
        focusedField = nil
        guard canCheckoutCart else {
            if cartHasInvalidLines {
                errorMessage = "Remove or fix the cart line so it matches its print format."
            } else if cartEstimate == nil {
                errorMessage = "Wait for a fresh cart estimate before checking out."
            } else {
                errorMessage = "Complete a valid shipping address before checkout."
            }
            return
        }
        if let last = lastCheckoutAttempt, Date().timeIntervalSince(last) < 3.0 {
            return
        }
        lastCheckoutAttempt = Date()
        fastCheckoutInstanceId = nil
        errorMessage = nil
        #if DEBUG
        checkoutErrorDebugFootnote = nil
        #endif
        isSubmitting = true

        Task {
            do {
                let url = try await performCheckoutSession()
                await MainActor.run {
                    checkoutURL = url
                    showStripeCheckout = true
                    isSubmitting = false
                    #if DEBUG
                    checkoutErrorDebugFootnote = nil
                    #endif
                }
            } catch {
                let dbgContext = await MainActor.run {
                    "cart checkout ctx=step:\(activeStep.rawValue) lines:\(orderCart.items.count) level:\(shippingLevel)"
                }
                OrderService.printCallableDiagnostics(error, context: dbgContext)
                await MainActor.run {
                    errorMessage = OrderService.userFacingCallableErrorMessage(error)
                    #if DEBUG
                    let dbg = dbgContext + " " + OrderService.debugCallableErrorFootnote(error, function: "createCartCheckoutSessionFast|createCartCheckoutSession")
                    checkoutErrorDebugFootnote = dbg
                    print("📦 \(dbg)")
                    #endif
                    isSubmitting = false
                }
            }
        }
    }

    private func performCheckoutSession() async throws -> URL {
        #if DEBUG
        let checkoutDebugId = String(UUID().uuidString.prefix(8))
        #endif
        var checkoutRetryCount = 0
        let (normalizedShipping, rows, level, initialEstimate) = await MainActor.run {
            (
                normalizedShippingForLulu(shipping),
                orderCart.items.map { ($0.bookVersionId, $0.productOptionId as String?, $0.quantity) },
                shippingLevel,
                cartEstimate
            )
        }
        await MainActor.run { saveLastAddress() }

        var estimate = initialEstimate
        if estimate == nil || estimateNeedsRefreshBeforePay(estimate) {
            let fresh = try await OrderService.shared.prepareCartCheckoutPricing(
                items: rows,
                shippingAddress: normalizedShipping,
                shippingLevel: level
            )
            await MainActor.run { cartEstimate = fresh }
            estimate = fresh
        }
        guard let est = estimate else {
            throw OrderError.badResponse
        }

        func createFastCheckoutURL(quoteId: String, cartHash: String, totalCents: Int) async throws -> URL {
            let resume = await MainActor.run { fastCheckoutInstanceId }
            let correlation = UUID().uuidString
            let (url, _, groupId, _) = try await OrderService.shared.createCartCheckoutSessionFast(
                quoteId: quoteId,
                cartHash: cartHash,
                clientEstimatedTotalCents: totalCents,
                checkoutInstanceId: resume,
                clientCorrelationId: correlation
            )
            if let groupId {
                await MainActor.run { fastCheckoutInstanceId = groupId }
            }
            return url
        }

        func createLegacyCheckoutURL(totalCents: Int) async throws -> URL {
            let (url, _, _, _) = try await OrderService.shared.createCartCheckoutSession(
                items: rows,
                shippingAddress: normalizedShipping,
                shippingLevel: level,
                clientEstimatedTotalCents: totalCents
            )
            return url
        }

        func createLegacyCheckoutURLWithTransientRetry(totalCents: Int) async throws -> URL {
            do {
                return try await createLegacyCheckoutURL(totalCents: totalCents)
            } catch {
                guard OrderService.shouldRetryCheckoutAfterTransientStripeError(error) else { throw error }
                checkoutRetryCount += 1
                #if DEBUG
                print("📦 checkout path=legacy_retry_transient debugId=\(checkoutDebugId) retry=\(checkoutRetryCount)")
                #endif
                return try await createLegacyCheckoutURL(totalCents: totalCents)
            }
        }

        #if DEBUG
        let quoteStatus = "quoteId=\(est.quoteId ?? "nil") cartHash=\(est.cartHash != nil ? "yes" : "no") totalCents=\(est.estimatedTotalCents)"
        print("📦 checkout path=eval debugId=\(checkoutDebugId) retry=\(checkoutRetryCount) fastEligible=\(isFastCheckoutEligible(est)) \(quoteStatus)")
        #endif

        if isFastCheckoutEligible(est),
           let qid = est.quoteId,
           let ch = est.cartHash {
            do {
                #if DEBUG
                print("📦 checkout path=fast debugId=\(checkoutDebugId) retry=\(checkoutRetryCount) quoteId=\(qid)")
                #endif
                return try await createFastCheckoutURL(quoteId: qid, cartHash: ch, totalCents: est.estimatedTotalCents)
            } catch {
                if OrderService.shouldFallbackToLegacyCartCheckout(error) {
                    #if DEBUG
                    print(
                        "📦 checkout path=legacy fn=createCartCheckoutSession reason=fallback_from_fast " +
                        OrderService.debugCallableErrorFootnote(error, function: "createCartCheckoutSessionFast") +
                        " debugId=\(checkoutDebugId) retry=\(checkoutRetryCount)"
                    )
                    #endif
                    return try await createLegacyCheckoutURLWithTransientRetry(totalCents: est.estimatedTotalCents)
                }
                if OrderService.shouldRetryCheckoutQuoteAfterError(error) {
                    checkoutRetryCount += 1
                    #if DEBUG
                    print("📦 checkout path=retry_quote debugId=\(checkoutDebugId) retry=\(checkoutRetryCount)")
                    #endif
                    let fresh2 = try await OrderService.shared.prepareCartCheckoutPricing(
                        items: rows,
                        shippingAddress: normalizedShipping,
                        shippingLevel: level
                    )
                    await MainActor.run { cartEstimate = fresh2 }
                    if isFastCheckoutEligible(fresh2),
                       let q2 = fresh2.quoteId,
                       let h2 = fresh2.cartHash {
                        #if DEBUG
                        print("📦 checkout path=fast_after_retry debugId=\(checkoutDebugId) retry=\(checkoutRetryCount)")
                        #endif
                        return try await createFastCheckoutURL(
                            quoteId: q2,
                            cartHash: h2,
                            totalCents: fresh2.estimatedTotalCents
                        )
                    }
                    #if DEBUG
                    print("📦 checkout path=legacy_after_retry debugId=\(checkoutDebugId) retry=\(checkoutRetryCount)")
                    #endif
                    return try await createLegacyCheckoutURLWithTransientRetry(totalCents: fresh2.estimatedTotalCents)
                }
                if OrderService.shouldRetryCheckoutAfterTransientStripeError(error) {
                    checkoutRetryCount += 1
                    #if DEBUG
                    print("📦 checkout path=fast_retry_transient debugId=\(checkoutDebugId) retry=\(checkoutRetryCount)")
                    #endif
                    return try await createFastCheckoutURL(quoteId: qid, cartHash: ch, totalCents: est.estimatedTotalCents)
                }
                throw error
            }
        }

        #if DEBUG
        print("📦 checkout path=legacy debugId=\(checkoutDebugId) retry=\(checkoutRetryCount) (no fast quote)")
        #endif
        return try await createLegacyCheckoutURLWithTransientRetry(totalCents: est.estimatedTotalCents)
    }

    private var shippingValidationIssues: [String] {
        validateShippingForLulu(shipping)
    }

    private func normalizedShippingForLulu(_ raw: ShippingAddress) -> ShippingAddress {
        var out = raw
        out.name = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
        out.street1 = raw.street1.trimmingCharacters(in: .whitespacesAndNewlines)
        out.city = raw.city.trimmingCharacters(in: .whitespacesAndNewlines)
        out.stateCode = raw.stateCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        out.countryCode = raw.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        out.postcode = raw.postcode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let plusPrefix = raw.phone.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+")
        let digits = raw.phone.filter(\.isNumber)
        out.phone = plusPrefix ? "+\(digits)" : digits
        return out
    }

    private func validateShippingForLulu(_ raw: ShippingAddress) -> [String] {
        let v = normalizedShippingForLulu(raw)
        var issues: [String] = []
        if v.name.count < 2 { issues.append("Enter a valid full name.") }
        if v.street1.count < 5 { issues.append("Street address is too short.") }
        if v.city.count < 2 { issues.append("City is required.") }
        if v.countryCode.count != 2 { issues.append("Country must be a 2-letter code (e.g. US).") }
        if v.phone.filter(\.isNumber).count < 10 { issues.append("Phone must include at least 10 digits.") }

        if v.countryCode == "US" {
            let stateOK = v.stateCode.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil
            if !stateOK { issues.append("State must be 2 letters for US addresses.") }
            let zipOK = v.postcode.range(of: "^\\d{5}(-\\d{4})?$", options: .regularExpression) != nil
            if !zipOK { issues.append("ZIP must be 5 digits (or ZIP+4).") }
        } else {
            if v.stateCode.count < 2 { issues.append("State/region is required.") }
            if v.postcode.count < 3 { issues.append("Postal code is required.") }
        }

        return issues
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
