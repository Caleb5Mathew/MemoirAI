import SwiftUI
import RevenueCat
import RevenueCatUI
import FirebaseAuth
import Mixpanel

enum PaywallSource: String, CaseIterable {
    case onboarding
    case settings
    case storyGeneration = "story_generation"
    case profileLimit = "profile_limit"
    case memoir
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
    @State private var analyticsPresentationID = UUID().uuidString
    @State private var recordedImpression = false
    @State private var dismissalReason = "external"
    @State private var activationOrigin = "purchase"

    var body: some View {
        Group {
            if isPreparing {
                ProgressView("Checking your subscription…")
            } else if let accountID, preparationError == nil {
                PaywallView(displayCloseButton: false)
                    .onAppear {
                        guard !recordedImpression else { return }
                        recordedImpression = true
                        ProductAnalytics.shared.track("Paywall Viewed", analyticsProperties)
                    }
                    .onPurchaseStarted { _ in
                        isPurchasing = true
                        ProductAnalytics.shared.track("Subscription Purchase Started", analyticsProperties)
                    }
                    .onPurchaseCancelled {
                        isPurchasing = false
                        ProductAnalytics.shared.track("Subscription Purchase Cancelled", analyticsProperties)
                    }
                    .onPurchaseFailure { _ in
                        isPurchasing = false
                        ProductAnalytics.shared.track("Subscription Purchase Failed", analyticsProperties.merging(["failure_stage": "purchase"]) { current, _ in current })
                    }
                    .onRestoreStarted {
                        isPurchasing = true
                        ProductAnalytics.shared.track("Subscription Restore Started", analyticsProperties)
                    }
                    .onRestoreFailure { _ in
                        isPurchasing = false
                        ProductAnalytics.shared.track("Subscription Restore Failed", analyticsProperties.merging(["failure_stage": "restore"]) { current, _ in current })
                    }
                    .onPurchaseCompleted { info in
                        activate(info, accountID: accountID, origin: "purchase")
                    }
                    .onRestoreCompleted { info in
                        activate(info, accountID: accountID, origin: "restore")
                    }
                    .onRequestedDismissal {
                        // RevenueCat requests dismissal before our activation finishes.
                        // The explicit Close button and verified activation own dismissal.
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
                    .disabled(isActivating)
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
        // The illustrated header needs white system icons; the paywall itself stays light.
        .environment(\.colorScheme, .light)
        .preferredColorScheme(!isPreparing && accountID != nil && preparationError == nil ? .dark : .light)
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
            ProductAnalytics.shared.track("Subscription Activation Failed", analyticsProperties.merging(["purchase_origin": activationOrigin, "failure_stage": "activation"]) { current, _ in current })
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
    }

    private var analyticsProperties: Properties {
        ["presentation_id": analyticsPresentationID, "paywall_source": source.rawValue]
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
    }

    @MainActor
    private func activate(_ info: CustomerInfo, accountID: String, origin: String) {
        activationOrigin = origin
        activationError = nil
        ProductAnalytics.shared.track("Subscription Activation Started", analyticsProperties.merging(["purchase_origin": origin]) { current, _ in current })
        isPurchasing = false
        isActivating = true
        Task { @MainActor in
            defer { isActivating = false }
            do {
                if try manager.applyPurchaseResult(info, for: accountID) {
                    dismissalReason = "entitlement_active"
                    ProductAnalytics.shared.track("Subscription Activation Succeeded", analyticsProperties.merging(["purchase_origin": origin]) { current, _ in current })
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
                    ProductAnalytics.shared.track("Subscription Activation Succeeded", analyticsProperties.merging(["purchase_origin": origin]) { current, _ in current })
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
