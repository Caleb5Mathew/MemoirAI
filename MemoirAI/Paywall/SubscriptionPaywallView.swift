import SwiftUI
import RevenueCat
import RevenueCatUI
import FirebaseAuth

/// Keeps every purchase surface tied to the account that owns its memories.
struct SubscriptionPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = RCSubscriptionManager.shared
    @ObservedObject private var auth = AuthenticationService.shared
    @State private var accountID: String?
    @State private var isPreparing = true
    @State private var isActivating = false
    @State private var isPurchasing = false
    @State private var preparationError: String?
    @State private var activationError: String?

    var body: some View {
        Group {
            if isPreparing {
                ProgressView("Checking your subscription…")
            } else if let accountID, preparationError == nil {
                PaywallView(displayCloseButton: false)
                    .onPurchaseStarted { _ in isPurchasing = true }
                    .onPurchaseCancelled { isPurchasing = false }
                    .onPurchaseFailure { _ in isPurchasing = false }
                    .onRestoreStarted { isPurchasing = true }
                    .onRestoreFailure { _ in isPurchasing = false }
                    .onPurchaseCompleted { info in
                        activate(info, accountID: accountID)
                    }
                    .onRestoreCompleted { info in
                        activate(info, accountID: accountID)
                    }
                    .onRequestedDismissal {
                        // RevenueCat requests dismissal before our activation finishes.
                        // The explicit Close button and verified activation own dismissal.
                    }
                    .overlay(alignment: .topTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("Close")
                        .disabled(isActivating || isPurchasing)
                        .padding(12)
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
                    Button("Try Again") { Task { await prepare() } }
                    Button("Close") { dismiss() }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled(isActivating || isPurchasing)
        .task { await prepare() }
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

    @MainActor
    private func prepare() async {
        isPreparing = true
        preparationError = nil
        defer { isPreparing = false }
        guard Purchases.isConfigured else {
            preparationError = "Subscriptions could not be loaded. Please contact support."
            return
        }
        guard await auth.prepareAuthenticatedSessionForLaunch(),
              let userID = Auth.auth().currentUser?.uid,
              await manager.identify(firebaseUserID: userID),
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
    private func activate(_ info: CustomerInfo, accountID: String) {
        isPurchasing = false
        isActivating = true
        Task { @MainActor in
            defer { isActivating = false }
            do {
                if try manager.applyPurchaseResult(info, for: accountID) {
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
