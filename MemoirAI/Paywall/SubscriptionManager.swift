import Foundation
import RevenueCat
import SwiftUI

// (Make sure Purchases and other RevenueCat imports are available)

/// Subscription tiers with their monthly page allowances
enum Tier: String, CaseIterable {
    case basic   = "com.Buildr.MemoirAI.Monthly"
    case premium = "com.Buildr.MemoirAI.PremiumMonthly" // Ensure this ID matches your Premium product
    case pro     = "com.Buildr.MemoirAI.ProMonthly"     // Ensure this ID matches your Pro product

    var allowance: Int { // Pages per month
        switch self {
        case .basic:   return 100
        case .premium: return 300
        case .pro:     return 200
        }
    }

    var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .premium: return "Premium"
        case .pro: return "Pro"
        }
    }
}

@MainActor
final class RCSubscriptionManager: NSObject, ObservableObject {
    static let shared = RCSubscriptionManager()

    @Published var offerings: Offerings?
    @Published var activeTier: Tier?
    @Published var remainingAllowance: Int = 0

    private let allowanceKeyPrefix = "memoirai_page_allowance_"
    private let lastResetPrefix    = "memoirai_page_lastReset_"
    
    // New: Define the allowance for free users and an identifier for their storage
    private let freeTierInitialAllowance: Int = 95
    private let freeTierStorageIdentifier = "free_tier_user" // For UserDefaults keys

    private override init() {
        super.init()
        
        // Only configure RevenueCat if it's properly set up
        if Purchases.isConfigured {
            Purchases.shared.delegate = self
            Task {
                await loadOfferings()
                await refreshCustomerInfo()
            }
        } else {
            print("⚠️ RevenueCat not configured - using development mode")
            // Set up as free user for development
            activeTier = nil
            remainingAllowance = freeTierInitialAllowance
        }
    }

    func loadOfferings() async {
        guard Purchases.isConfigured else {
            print("⚠️ RevenueCat not configured - skipping offerings load")
            return
        }
        
        do {
            offerings = try await Purchases.shared.offerings()
            print("RCManager: Offerings loaded successfully.")
        } catch {
            print("❌ RCManager: Offerings error: \(error)")
            offerings = nil
        }
    }

    func refreshCustomerInfo() async {
        guard Purchases.isConfigured else {
            print("⚠️ RevenueCat not configured - skipping customer info refresh")
            return
        }
        
        do {
            let info = try await Purchases.shared.customerInfo()
            print("RCManager: CustomerInfo refreshed. Entitlements: \(info.entitlements.active.keys)")
            evaluateEntitlements(from: info)
        } catch {
            print("❌ RCManager: CustomerInfo error: \(error). Assuming free user state.")
            // When there's an error, configure as a free user to ensure consistent state.
            activeTier = nil
            configureAllowanceForFreeUser()
        }
    }

    private func evaluateEntitlements(from info: CustomerInfo) {
        var determinedTier: Tier? = nil

        // Prioritize higher tiers if multiple somehow become active.
        if info.entitlements.active.values.contains(where: { $0.productIdentifier == Tier.pro.rawValue && $0.isActive }) {
            determinedTier = .pro
        } else if info.entitlements.active.values.contains(where: { $0.productIdentifier == Tier.premium.rawValue && $0.isActive }) {
            determinedTier = .premium
        } else if info.entitlements.active.values.contains(where: { $0.productIdentifier == Tier.basic.rawValue && $0.isActive }) {
            determinedTier = .basic
        }
        
        // Fallback: Check a generic entitlement if your setup uses one.
        if determinedTier == nil, let ent = info.entitlements["image_generation"], ent.isActive {
             if let tierFromProduct = Tier(rawValue: ent.productIdentifier) {
                 determinedTier = tierFromProduct
             }
        }

        if let newTier = determinedTier {
            print("RCManager: Active entitlement found for tier: \(newTier.displayName) with productID: \(newTier.rawValue)")
            setActiveTier(newTier)
        } else {
            print("RCManager: No active tier entitlement found. User is on free plan.")
            activeTier = nil
            configureAllowanceForFreeUser() // Configure allowance for free users
        }
    }

    // New: Function to manage allowance for free users
    private func configureAllowanceForFreeUser() {
        let now = Date()
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        let resetKeyBase = lastResetPrefix + freeTierStorageIdentifier
        let allowanceUDKey = allowanceKeyPrefix + freeTierStorageIdentifier

        let lastResetYear = UserDefaults.standard.integer(forKey: resetKeyBase + "_year")
        let lastResetMonth = UserDefaults.standard.integer(forKey: resetKeyBase + "_month")

        if oldActiveTierWasPaid() || lastResetYear != currentYear || lastResetMonth != currentMonth {
            // Reset if the user was previously on a paid tier OR it's a new month/year for the free user
            remainingAllowance = freeTierInitialAllowance
            UserDefaults.standard.set(currentYear, forKey: resetKeyBase + "_year")
            UserDefaults.standard.set(currentMonth, forKey: resetKeyBase + "_month")
            UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
            print("RCManager: Allowance reset for Free User. New allowance: \(remainingAllowance)")
        } else {
            // Load existing allowance for the current month for Free User
            if let storedValue = UserDefaults.standard.object(forKey: allowanceUDKey) as? Int {
                remainingAllowance = storedValue
            } else {
                // Key not found for this period, grant initial allowance
                remainingAllowance = freeTierInitialAllowance
                UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey) // Store it now
            }
            print("RCManager: Loaded existing allowance for Free User: \(remainingAllowance)")
        }
        // Clear oldTier tracker after handling free user setup
        UserDefaults.standard.removeObject(forKey: "memoirai_old_active_tier_id")
    }
    
    // Helper to check if the user was previously on a paid tier
    // This is to ensure that if they drop from paid to free, their free allowance resets.
    private func oldActiveTierWasPaid() -> Bool {
        return UserDefaults.standard.string(forKey: "memoirai_old_active_tier_id") != nil
    }


    private func setActiveTier(_ tier: Tier) {
        let oldTierID = activeTier?.rawValue
        if oldTierID != tier.rawValue { // Store the old tier ID only if it's changing to a *different* paid tier or from free
             UserDefaults.standard.set(oldTierID, forKey: "memoirai_old_active_tier_id")
        }
        
        activeTier = tier

        let now = Date()
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        let resetKeyBase = lastResetPrefix + tier.rawValue
        
        let lastResetYear = UserDefaults.standard.integer(forKey: resetKeyBase + "_year")
        let lastResetMonth = UserDefaults.standard.integer(forKey: resetKeyBase + "_month")

        let allowanceUDKey = allowanceKeyPrefix + tier.rawValue

        if oldTierID != tier.rawValue || lastResetYear != currentYear || lastResetMonth != currentMonth {
            remainingAllowance = tier.allowance
            UserDefaults.standard.set(currentYear, forKey: resetKeyBase + "_year")
            UserDefaults.standard.set(currentMonth, forKey: resetKeyBase + "_month")
            UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
            print("RCManager: Allowance reset for \(tier.displayName). New allowance: \(remainingAllowance)")
        } else {
            if let storedValue = UserDefaults.standard.object(forKey: allowanceUDKey) as? Int {
                 remainingAllowance = storedValue
            } else {
                // Should not happen if tier was active and it's not a reset, but as a fallback:
                remainingAllowance = tier.allowance
                UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
            }
            print("RCManager: Loaded existing allowance for \(tier.displayName): \(remainingAllowance)")
        }
    }

    func purchase(package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled {
            print("RCManager: Purchase cancelled by user.")
            return
        }
        print("RCManager: Purchase successful. Refreshing customer info via evaluateEntitlements.")
        // evaluateEntitlements will be called by the delegate, or call it directly
        // to ensure immediate update of the tier and allowance.
        evaluateEntitlements(from: result.customerInfo)
    }

    func consume(pages: Int) {
        guard pages > 0 else { // Don't consume if 0 pages
            print("RCManager: Consume called with 0 pages. No action taken.")
            return
        }

        let userTypeForLog: String
        let allowanceUDKeyToUse: String

        if let currentActiveTier = activeTier {
            userTypeForLog = currentActiveTier.displayName
            allowanceUDKeyToUse = allowanceKeyPrefix + currentActiveTier.rawValue
        } else {
            userTypeForLog = "Free User"
            allowanceUDKeyToUse = allowanceKeyPrefix + freeTierStorageIdentifier
        }
        
        guard remainingAllowance > 0 else {
            print("RCManager: Cannot consume \(pages) pages. No remaining allowance for \(userTypeForLog).")
            return
        }

        let newAllowance = remainingAllowance - pages
        remainingAllowance = max(0, newAllowance)
        UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKeyToUse)
        print("RCManager: Consumed \(pages) pages. Remaining for \(userTypeForLog): \(remainingAllowance)")
    }

    func canGenerate(pages pagesToGenerate: Int) -> Bool {
        guard pagesToGenerate > 0 else { return true }

        // remainingAllowance is now set by either setActiveTier or configureAllowanceForFreeUser
        let userTypeForLog = activeTier?.displayName ?? "Free User"

        if remainingAllowance >= pagesToGenerate {
            print("RCManager: Usage check: Can generate. User: \(userTypeForLog), Remaining: \(remainingAllowance), Requested: \(pagesToGenerate)")
            return true
        } else {
            print("RCManager: Usage check: Cannot generate. Insufficient allowance. User: \(userTypeForLog), Remaining: \(remainingAllowance), Requested: \(pagesToGenerate)")
            return false
        }
    }
}

extension RCSubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases,
                               receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            print("RCManager (Delegate): Received updated customer info. Refreshing state...")
            // Before evaluating, store the current active tier ID to check if it changes from paid to free
            if let currentTier = RCSubscriptionManager.shared.activeTier {
                 UserDefaults.standard.set(currentTier.rawValue, forKey: "memoirai_old_active_tier_id")
            } else {
                 UserDefaults.standard.removeObject(forKey: "memoirai_old_active_tier_id") // Was free or undefined
            }
            RCSubscriptionManager.shared.evaluateEntitlements(from: customerInfo)
        }
    }
}
