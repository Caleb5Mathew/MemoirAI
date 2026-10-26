import SwiftUI
import RevenueCat
import FirebaseAuth
import Mixpanel

enum PaywallSource: String, CaseIterable {
    case onboarding
    case settings
    case storyGeneration = "story_generation"
    case profileLimit = "profile_limit"
    case memoir
}

enum SubscriptionPlan: String, CaseIterable, Sendable {
    case yearly
    case monthly

    var title: String {
        switch self {
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        }
    }

    var billingPeriod: String {
        switch self {
        case .yearly: return "year"
        case .monthly: return "month"
        }
    }
}

enum SubscriptionPaywallPolicy {
    static func defaultPlan(availablePlans: Set<SubscriptionPlan>) -> SubscriptionPlan? {
        if availablePlans.contains(.yearly) { return .yearly }
        if availablePlans.contains(.monthly) { return .monthly }
        return nil
    }

    static func callToAction(hasEligibleFreeTrial: Bool) -> String {
        hasEligibleFreeTrial ? "Start Free Trial" : "Continue"
    }

    static func annualIsBetterValue(annualPrice: Decimal, monthlyPrice: Decimal) -> Bool {
        annualPrice < monthlyPrice * 12
    }

    static func selectedValue<Value>(
        for plan: SubscriptionPlan?,
        values: [SubscriptionPlan: Value]
    ) -> Value? {
        guard let plan else { return nil }
        return values[plan]
    }

    static func renewalDisclosure(
        price: String,
        billingPeriod: String,
        freeTrialDuration: String?
    ) -> String {
        if let freeTrialDuration {
            return "\(freeTrialDuration) free, then \(price) per \(billingPeriod). Cancel anytime."
        }
        return "\(price) per \(billingPeriod). Cancel anytime."
    }

    static func trialDuration(value: Int, unit: SubscriptionPeriod.Unit) -> String {
        let unitName: String
        switch unit {
        case .day: unitName = "day"
        case .week: unitName = "week"
        case .month: unitName = "month"
        case .year: unitName = "year"
        @unknown default: unitName = "day"
        }
        return "\(value) \(unitName)\(value == 1 ? "" : "s")"
    }
}

/// Keeps every purchase surface tied to the account that owns its memories.
struct SubscriptionPaywallView: View {
    let source: PaywallSource
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = RCSubscriptionManager.shared
    @ObservedObject private var auth = AuthenticationService.shared
    @State private var accountID: String?
    @State private var isPreparing = true
    @State private var isActivating = false
    @State private var isPurchasing = false
    @State private var preparationError: String?
    @State private var activationError: String?
    @State private var transactionError: String?
    @State private var transactionErrorOrigin = "purchase"
    @State private var selectedPlan: SubscriptionPlan?
    @State private var eligibleTrialProductIDs: Set<String> = []
    @State private var analyticsPresentationID = UUID().uuidString
    @State private var recordedImpression = false
    @State private var dismissalReason = "external"
    @State private var activationOrigin = "purchase"

    var body: some View {
        Group {
            if isPreparing {
                ProgressView("Checking your subscription…")
            } else if let accountID, preparationError == nil {
                paywall(accountID: accountID)
                    .onAppear {
                        guard !recordedImpression else { return }
                        recordedImpression = true
                        ProductAnalytics.shared.track("Paywall Viewed", analyticsProperties)
                    }
                    .overlay(alignment: .topTrailing) {
                        Button { dismissalReason = "close_button"; dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("Close")
                        .disabled(isActivating || isPurchasing)
                        .padding(12)
                    }
                    .safeAreaInset(edge: .top) {
                        if manager.hasBillingIssue {
                            SubscriptionBillingNotice(hasActiveSubscription: manager.hasActiveSubscription)
                                .padding(.horizontal, 20)
                                .padding(.top, 56)
                        }
                    }
                    .disabled(isActivating || isPurchasing)
                    .overlay {
                        if isActivating {
                            ProgressView("Activating your subscription…")
                                .padding(24)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
            } else {
                VStack(spacing: 20) {
                    Text("Subscription unavailable").font(.title2.bold())
                    Text(preparationError ?? "Please try again.")
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        ProductAnalytics.shared.action("retry_paywall", screen: "paywall")
                        Task { await prepare() }
                    }
                    Button("Close") { dismiss() }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .analyticsScreen("paywall")
        .interactiveDismissDisabled(isActivating || isPurchasing)
        .task { await prepare() }
        .onDisappear {
            guard recordedImpression else { return }
            ProductAnalytics.shared.track("Paywall Dismissed", analyticsProperties.merging(["dismissal_reason": dismissalReason]) { current, _ in current })
        }
        .onChange(of: preparationError) { _, error in
            guard error != nil else { return }
            ProductAnalytics.shared.track("Paywall Preparation Failed", analyticsProperties.merging(["failure_stage": "preparation"]) { current, _ in current })
        }
        .onChange(of: activationError) { _, error in
            guard error != nil else { return }
            ProductAnalytics.shared.track("Subscription Activation Failed", activationAnalyticsProperties(
                origin: activationOrigin
            ).merging(["failure_stage": "activation"]) { current, _ in current })
        }
        .onChange(of: auth.user?.uid) { _, newID in
            guard let accountID, newID != accountID else { return }
            self.accountID = nil
            preparationError = "Your account changed. Close this screen and open it again to continue."
        }
        .alert("Subscription activation", isPresented: Binding(
            get: { activationError != nil },
            set: { if !$0 { activationError = nil } }
        )) {
            Button("OK", role: .cancel) { activationError = nil }
        } message: {
            Text(activationError ?? "Please try Restore Purchases. You do not need to buy again.")
        }
        .alert(transactionErrorOrigin == "restore" ? "Couldn’t restore purchases" : "Couldn’t start purchase",
               isPresented: Binding(
                get: { transactionError != nil },
                set: { if !$0 { transactionError = nil } }
               )) {
            Button("OK", role: .cancel) { transactionError = nil }
        } message: {
            Text(transactionError ?? "Check your connection and try again.")
        }
    }

    private var baseAnalyticsProperties: Properties {
        [
            "presentation_id": analyticsPresentationID,
            "paywall_source": source.rawValue
        ]
    }

    private var analyticsProperties: Properties {
        var properties = baseAnalyticsProperties
        if let selectedPlan {
            properties["subscription_plan"] = selectedPlan.rawValue
        }
        return properties
    }

    private func activationAnalyticsProperties(origin: String) -> Properties {
        var properties = origin == "restore" ? baseAnalyticsProperties : analyticsProperties
        properties["purchase_origin"] = origin
        return properties
    }

    private var offeringPackages: [SubscriptionPlan: Package] {
        guard let offering = manager.offerings?.current else { return [:] }
        var packages: [SubscriptionPlan: Package] = [:]
        if let annual = offering.annual { packages[.yearly] = annual }
        if let monthly = offering.monthly { packages[.monthly] = monthly }
        return packages
    }

    @ViewBuilder
    private func paywall(accountID: String) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("Keep every story")
                        .font(.largeTitle.weight(.bold))
                    Text("Create memoirs, add family profiles, and make up to 100 illustrations each month.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 44)

                VStack(spacing: 12) {
                    ForEach(SubscriptionPlan.allCases, id: \.self) { plan in
                        if let package = offeringPackages[plan] {
                            planButton(plan: plan, package: package)
                        }
                    }
                }

                if let package = SubscriptionPaywallPolicy.selectedValue(
                    for: selectedPlan,
                    values: offeringPackages
                ),
                   let selectedPlan {
                    VStack(spacing: 10) {
                        Button {
                            Task { await purchase(package: package, accountID: accountID) }
                        } label: {
                            HStack(spacing: 8) {
                                if isPurchasing {
                                    ProgressView().tint(.white)
                                }
                                Text(SubscriptionPaywallPolicy.callToAction(
                                    hasEligibleFreeTrial: hasEligibleFreeTrial(package)
                                ))
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 54)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPurchasing || isActivating)
                        .accessibilityIdentifier("subscription_continue")

                        Text(disclosure(for: package, plan: selectedPlan))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Button("Restore Purchases") {
                    Task { await restore(accountID: accountID) }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isPurchasing || isActivating)

                Text("Payment is charged to your Apple ID. Subscriptions renew automatically unless canceled at least 24 hours before the current period ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"),
                   let privacyURL = URL(string: "https://memoirai-7db06.web.app/privacy/") {
                    HStack(spacing: 20) {
                        Link("Terms", destination: termsURL)
                        Link("Privacy", destination: privacyURL)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private func planButton(plan: SubscriptionPlan, package: Package) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
            ProductAnalytics.shared.track("Subscription Plan Selected", analyticsProperties.merging([
                "subscription_plan": plan.rawValue
            ]) { _, selected in selected })
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        selectionIndicator(isSelected: isSelected)
                        Text(plan.title).font(.headline)
                        Spacer(minLength: 8)
                        if plan == .yearly, annualIsBetterValue {
                            bestValueBadge
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            selectionIndicator(isSelected: isSelected)
                            Text(plan.title).font(.headline)
                        }
                        if plan == .yearly, annualIsBetterValue {
                            bestValueBadge
                        }
                    }
                }
                Text(plan == .yearly ? "One payment each year" : "Flexible monthly billing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(package.localizedPriceString) / \(plan.billingPeriod)")
                    .font(.headline)
            }
            .foregroundStyle(.primary)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("subscription_plan_\(plan.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .accessibilityHidden(true)
    }

    private var annualIsBetterValue: Bool {
        guard let annual = offeringPackages[.yearly],
              let monthly = offeringPackages[.monthly] else { return false }
        return SubscriptionPaywallPolicy.annualIsBetterValue(
            annualPrice: annual.storeProduct.price,
            monthlyPrice: monthly.storeProduct.price
        )
    }

    private var bestValueBadge: some View {
        Text("BEST VALUE")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(.black)
            .background(Color.accentColor, in: Capsule())
    }

    private func hasEligibleFreeTrial(_ package: Package) -> Bool {
        package.storeProduct.introductoryDiscount?.paymentMode == .freeTrial
            && eligibleTrialProductIDs.contains(package.storeProduct.productIdentifier)
    }

    private func disclosure(for package: Package, plan: SubscriptionPlan) -> String {
        let freeTrialDuration: String?
        if hasEligibleFreeTrial(package),
           let trial = package.storeProduct.introductoryDiscount {
            freeTrialDuration = SubscriptionPaywallPolicy.trialDuration(
                value: trial.subscriptionPeriod.value * trial.numberOfPeriods,
                unit: trial.subscriptionPeriod.unit
            )
        } else {
            freeTrialDuration = nil
        }
        return SubscriptionPaywallPolicy.renewalDisclosure(
            price: package.localizedPriceString,
            billingPeriod: plan.billingPeriod,
            freeTrialDuration: freeTrialDuration
        )
    }

    @MainActor
    private func prepare() async {
        isPreparing = true
        preparationError = nil
        defer { isPreparing = false }
        guard await auth.prepareAuthenticatedSessionForLaunch(),
              let userID = Auth.auth().currentUser?.uid,
              await manager.prepareIdentity(firebaseUserID: userID),
              Auth.auth().currentUser?.uid == userID else {
            preparationError = manager.identityErrorMessage
                ?? "We could not verify your account. Check your connection and try again."
            return
        }
        accountID = userID
        await manager.refreshCustomerInfo(forceRefresh: true)
        guard Auth.auth().currentUser?.uid == userID else { return }
        if manager.hasActiveSubscription {
            dismiss()
            return
        }
        if manager.offerings?.current?.availablePackages.isEmpty != false {
            await manager.loadOfferings()
        }
        guard manager.offerings?.current?.availablePackages.isEmpty == false else {
            preparationError = "Subscriptions could not be loaded. Check your connection and try again."
            return
        }
        let packages = offeringPackages
        guard !packages.isEmpty else {
            preparationError = "The available subscriptions are not configured correctly. Please try again later."
            return
        }
        selectedPlan = SubscriptionPaywallPolicy.defaultPlan(availablePlans: Set(packages.keys))
        isPreparing = false
        eligibleTrialProductIDs = await eligibleFreeTrialProductIDs(in: Array(packages.values))
    }

    private func eligibleFreeTrialProductIDs(in packages: [Package]) async -> Set<String> {
        var productIDs: Set<String> = []
        for package in packages where package.storeProduct.introductoryDiscount?.paymentMode == .freeTrial {
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
                product: package.storeProduct
            )
            if eligibility == .eligible {
                productIDs.insert(package.storeProduct.productIdentifier)
            }
        }
        return productIDs
    }

    @MainActor
    private func purchase(package: Package, accountID: String) async {
        isPurchasing = true
        activationError = nil
        transactionError = nil
        ProductAnalytics.shared.track("Subscription Purchase Started", analyticsProperties)
        do {
            let result = try await manager.purchase(package: package)
            if result.userCancelled {
                isPurchasing = false
                ProductAnalytics.shared.track("Subscription Purchase Cancelled", analyticsProperties)
                return
            }
            isPurchasing = false
            activate(result.customerInfo, accountID: accountID, origin: "purchase")
        } catch {
            isPurchasing = false
            transactionErrorOrigin = "purchase"
            transactionError = error.localizedDescription
            ProductAnalytics.shared.track("Subscription Purchase Failed", analyticsProperties.merging([
                "failure_stage": "purchase"
            ]) { current, _ in current })
        }
    }

    @MainActor
    private func restore(accountID: String) async {
        isPurchasing = true
        activationError = nil
        transactionError = nil
        ProductAnalytics.shared.track("Subscription Restore Started", baseAnalyticsProperties)
        do {
            let info = try await Purchases.shared.restorePurchases()
            isPurchasing = false
            activate(info, accountID: accountID, origin: "restore")
        } catch {
            isPurchasing = false
            transactionErrorOrigin = "restore"
            transactionError = error.localizedDescription
            ProductAnalytics.shared.track("Subscription Restore Failed", baseAnalyticsProperties.merging([
                "failure_stage": "restore"
            ]) { current, _ in current })
        }
    }

    @MainActor
    private func activate(_ info: CustomerInfo, accountID: String, origin: String) {
        activationOrigin = origin
        activationError = nil
        ProductAnalytics.shared.track("Subscription Activation Started", activationAnalyticsProperties(origin: origin))
        isPurchasing = false
        isActivating = true
        Task { @MainActor in
            defer { isActivating = false }
            do {
                if try manager.applyPurchaseResult(info, for: accountID) {
                    dismissalReason = "entitlement_active"
                    ProductAnalytics.shared.track("Subscription Activation Succeeded", activationAnalyticsProperties(origin: origin))
                    dismiss()
                    return
                }
                await manager.refreshCustomerInfo(forceRefresh: true)
                guard Auth.auth().currentUser?.uid == accountID,
                      manager.isIdentityReady(for: accountID) else {
                    activationError = "Your account changed. Sign back in to restore your subscription."
                    return
                }
                if manager.hasActiveSubscription {
                    dismissalReason = "entitlement_active"
                    ProductAnalytics.shared.track("Subscription Activation Succeeded", activationAnalyticsProperties(origin: origin))
                    dismiss()
                } else {
                    activationError = manager.activationErrorMessage
                        ?? "No active subscription was found. If you just purchased, try Restore Purchases. You do not need to buy again."
                }
            } catch {
                activationError = error.localizedDescription
            }
        }
    }
}

/// Recovery remains available even after a subscription's grace period ends.
struct SubscriptionBillingNotice: View {
    let hasActiveSubscription: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Payment needs attention", systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.semibold))
            Text(hasActiveSubscription
                 ? "Apple reported a subscription payment issue. Your access is still active. Update your payment method to avoid an interruption."
                 : "Apple couldn't renew your subscription. Update your Apple payment method and check your subscription in App Store settings. Return here to refresh your access.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            if let paymentURL = URL(string: "https://apps.apple.com/account/billing") {
                Link("Update Apple payment method", destination: paymentURL)
                    .font(.subheadline.weight(.semibold))
            }
            if !hasActiveSubscription,
               let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions") {
                Link("Manage App Store subscription", destination: subscriptionsURL)
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
