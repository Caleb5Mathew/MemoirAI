import Foundation
import RevenueCat
import SwiftUI

// Updated subscription tiers - removed free tier allowances
enum Tier: String, CaseIterable {
    case basic   = "com.Buildr.MemoirAI.Monthly"
    case premium = "com.Buildr.MemoirAI.PremiumMonthly"
    case pro     = "com.Buildr.MemoirAI.ProMonthly"
    case yearly  = "com.Buildr.MemoirAI.ProYearly"  // ✅ CHANGE THIS LINE

    var allowance: Int {
        // All subscription tiers get 50 images
        return 50
    }

    var displayName: String {
        switch self {
        case .basic: return "Basic Monthly"
        case .premium: return "Premium Monthly"
        case .pro: return "Pro Monthly"
        case .yearly: return "Yearly"
        }
    }
    
    var isYearly: Bool {
        return self == .yearly
    }
}

@MainActor
final class RCSubscriptionManager: NSObject, ObservableObject {
    static let shared = RCSubscriptionManager()

    @Published var offerings: Offerings?
    @Published var activeTier: Tier?
    @Published var remainingAllowance: Int = 0
    @Published var nextRenewalDate: Date?

    // 🔥 BACK TO USERDEFAULTS - Simple and reliable
    private let allowanceKeyPrefix = "memoirai_image_allowance_"
    private let lastResetPrefix    = "memoirai_image_lastReset_"
    private let renewalDateKey     = "memoirai_renewal_date"
    private let initializationKey  = "memoirai_initialized_"
    
    // Maximum images per subscription period
    private let maxImagesPerPeriod: Int = 50

    private override init() {
        super.init()
        
        if Purchases.isConfigured {
            Purchases.shared.delegate = self
            Task {
                await loadOfferings()
                await refreshCustomerInfo()
            }
        } else {
            print("⚠️ RevenueCat not configured - using development mode")
            // In development, simulate no subscription
            activeTier = nil
            remainingAllowance = 0
            nextRenewalDate = nil
        }
    }

    func loadOfferings() async {
        guard Purchases.isConfigured else { return }

        do {
            offerings = try await Purchases.shared.offerings()
            print("RCManager: Offerings loaded successfully.")

            // 🔎 DEBUG – packages actually delivered
            Task { @MainActor in
                if let pkgs = offerings?.current?.availablePackages {
                    print("🔍 Packages delivered:", pkgs.map(\.identifier))
                }
            }

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
            print("❌ RCManager: CustomerInfo error: \(error). Setting as non-subscriber.")
            // No subscription = no generation allowed
            activeTier = nil
            remainingAllowance = 0
            nextRenewalDate = nil
        }
    }

    private func evaluateEntitlements(from info: CustomerInfo) {
        var determinedTier: Tier? = nil
        var renewalDate: Date? = nil

        // Check for active entitlements and get renewal date
        for entitlement in info.entitlements.active.values {
            if entitlement.isActive {
                if let tier = Tier(rawValue: entitlement.productIdentifier) {
                    determinedTier = tier
                    renewalDate = entitlement.expirationDate
                    break
                }
            }
        }
        
        // Fallback: Check generic entitlement
        if determinedTier == nil, let ent = info.entitlements["image_generation"], ent.isActive {
            if let tierFromProduct = Tier(rawValue: ent.productIdentifier) {
                determinedTier = tierFromProduct
                renewalDate = ent.expirationDate
            }
        }

        if let newTier = determinedTier {
            print("RCManager: Active subscription found for tier: \(newTier.displayName)")
            setActiveTier(newTier, renewalDate: renewalDate)
        } else {
            print("RCManager: No active subscription found. User cannot generate images.")
            activeTier = nil
            remainingAllowance = 0
            nextRenewalDate = nil
        }
    }

    // 🔥 COMPLETELY FIXED: This is the core fix for the 50/50 vs 45/50 issue
    private func setActiveTier(_ tier: Tier, renewalDate: Date?) {
        let oldTierID = activeTier?.rawValue
        activeTier = tier
        nextRenewalDate = renewalDate
        
        // Store renewal date
        if let renewalDate = renewalDate {
            UserDefaults.standard.set(renewalDate, forKey: renewalDateKey)
        }

        let now = Date()
        let calendar = Calendar.current
        let allowanceUDKey = allowanceKeyPrefix + tier.rawValue
        let initKey = initializationKey + tier.rawValue
        
        // Check if this is the first time we're setting up this tier
        let isFirstTimeSetup = !UserDefaults.standard.bool(forKey: initKey)
        
        if isFirstTimeSetup {
            // 🔥 FIRST TIME: Set up with full allowance and mark as initialized
            remainingAllowance = maxImagesPerPeriod
            UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
            UserDefaults.standard.set(true, forKey: initKey)
            
            // Set initial reset tracking
            if tier.isYearly {
                UserDefaults.standard.set(now, forKey: lastResetPrefix + tier.rawValue + "_week")
            } else {
                let currentMonth = calendar.component(.month, from: now)
                let currentYear = calendar.component(.year, from: now)
                UserDefaults.standard.set(currentYear, forKey: lastResetPrefix + tier.rawValue + "_year")
                UserDefaults.standard.set(currentMonth, forKey: lastResetPrefix + tier.rawValue + "_month")
            }
            
            print("RCManager: First-time setup for \(tier.displayName). Starting allowance: \(remainingAllowance)")
            UserDefaults.standard.synchronize()
            return
        }
        
        // 🔥 CHECK FOR PERIOD RESET (monthly/weekly)
        let shouldReset: Bool
        if tier.isYearly {
            // Weekly reset for yearly subscriptions
            let lastResetWeek = UserDefaults.standard.object(forKey: lastResetPrefix + tier.rawValue + "_week") as? Date ?? Date.distantPast
            let weeksSinceReset = calendar.dateComponents([.weekOfYear], from: lastResetWeek, to: now).weekOfYear ?? 0
            shouldReset = weeksSinceReset >= 1
        } else {
            // Monthly reset for monthly subscriptions
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            let lastResetYear = UserDefaults.standard.integer(forKey: lastResetPrefix + tier.rawValue + "_year")
            let lastResetMonth = UserDefaults.standard.integer(forKey: lastResetPrefix + tier.rawValue + "_month")
            shouldReset = (lastResetYear != currentYear || lastResetMonth != currentMonth) && lastResetYear != 0
        }
        
        // 🔥 CHECK FOR TIER CHANGE
        let tierChanged = oldTierID != nil && oldTierID != tier.rawValue
        
        if tierChanged || shouldReset {
            // Reset allowance
            remainingAllowance = maxImagesPerPeriod
            
            // Update reset tracking
            if tier.isYearly {
                UserDefaults.standard.set(now, forKey: lastResetPrefix + tier.rawValue + "_week")
            } else {
                let currentMonth = calendar.component(.month, from: now)
                let currentYear = calendar.component(.year, from: now)
                UserDefaults.standard.set(currentYear, forKey: lastResetPrefix + tier.rawValue + "_year")
                UserDefaults.standard.set(currentMonth, forKey: lastResetPrefix + tier.rawValue + "_month")
            }
            
            UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
            print("RCManager: Allowance reset for \(tier.displayName). Reason: \(tierChanged ? "Tier changed" : "Period reset"). New allowance: \(remainingAllowance)")
        } else {
            // 🔥 NORMAL CASE: Load existing allowance (this preserves 45/50)
            if let storedValue = UserDefaults.standard.object(forKey: allowanceUDKey) as? Int {
                remainingAllowance = storedValue
                print("RCManager: Loaded existing allowance for \(tier.displayName): \(remainingAllowance)")
            } else {
                // Fallback if somehow we lost the data
                remainingAllowance = maxImagesPerPeriod
                UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
                print("RCManager: Fallback setup for \(tier.displayName). Starting allowance: \(remainingAllowance)")
            }
        }
        
        // Force save
        UserDefaults.standard.synchronize()
    }

    func purchase(package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled {
            print("RCManager: Purchase cancelled by user.")
            return
        }
        print("RCManager: Purchase successful. Refreshing customer info.")
        evaluateEntitlements(from: result.customerInfo)
    }

    // 🔥 ENHANCED: Better consumption tracking
    func consume(pages: Int) {
        guard pages > 0 else {
            print("RCManager: Consume called with 0 pages. No action taken.")
            return
        }

        guard let currentTier = activeTier else {
            print("RCManager: Cannot consume images. No active subscription.")
            return
        }
        
        guard remainingAllowance > 0 else {
            print("RCManager: Cannot consume \(pages) images. No remaining allowance.")
            return
        }

        let oldAllowance = remainingAllowance
        let newAllowance = remainingAllowance - pages
        remainingAllowance = max(0, newAllowance)
        
        // Save immediately with verification
        let allowanceUDKey = allowanceKeyPrefix + currentTier.rawValue
        UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
        UserDefaults.standard.synchronize()
        
        // Verify the save worked
        let verification = UserDefaults.standard.integer(forKey: allowanceUDKey)
        if verification != remainingAllowance {
            print("⚠️ WARNING: Save verification failed! Expected: \(remainingAllowance), Got: \(verification)")
        } else {
            print("✅ RCManager: Consumed \(pages) images. \(oldAllowance) → \(remainingAllowance)")
        }
    }

    func canGenerate(pages pagesToGenerate: Int) -> Bool {
        guard pagesToGenerate > 0 else { return true }

        // Must have active subscription to generate any images
        guard activeTier != nil else {
            print("RCManager: Cannot generate. No active subscription.")
            return false
        }

        if remainingAllowance >= pagesToGenerate {
            print("RCManager: Can generate \(pagesToGenerate) images. Remaining: \(remainingAllowance)")
            return true
        } else {
            print("RCManager: Cannot generate. Insufficient allowance. Remaining: \(remainingAllowance), Requested: \(pagesToGenerate)")
            return false
        }
    }
    
    // Get formatted renewal date string
    func getRenewalDateString() -> String {
        guard let tier = activeTier else { return "N/A" }
        
        let calendar = Calendar.current
        let now = Date()
        
        if tier.isYearly {
            // For yearly subscriptions, next reset is next Monday
            let nextMonday = calendar.nextDate(after: now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? now
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: nextMonday)
        } else {
            // For monthly subscriptions, use actual renewal date
            if let renewalDate = nextRenewalDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: renewalDate)
            } else {
                // Fallback to next month
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: nextMonth)
            }
        }
    }
    
    // Check if user has any active subscription
    var hasActiveSubscription: Bool {
        return activeTier != nil
    }
    
    // Check if user has reached image limit
    var hasReachedImageLimit: Bool {
        return hasActiveSubscription && remainingAllowance <= 0
    }

    // ✨ Smart generation advice based on remaining monthly allowance
    func getGenerationAdvice(for requestedPages: Int) -> String? {
        guard hasActiveSubscription else { return "Subscription required for image generation." }
        
        let remaining = remainingAllowance
        
        if requestedPages > remaining {
            return "You're requesting \(requestedPages) images but only have \(remaining) left in your monthly allowance. Consider generating fewer pages."
        }
        
        if requestedPages > 25 && remaining > 25 {
            return "This will use \(requestedPages) of your 50 monthly allowance. You'll have \(remaining - requestedPages) images remaining this month."
        }
        
        if remaining <= 10 {
            return "You have \(remaining) images left in your monthly allowance. Your allowance resets next month."
        }
        
        return nil // No warning needed
    }
    
    var monthlyAllowanceStatus: String {
        guard hasActiveSubscription else { return "No active subscription" }
        return "\(remainingAllowance)/50 monthly allowance remaining"
    }
    
    // ✨ Check if generation would use a large portion of allowance
    func isLargeGeneration(pages: Int) -> Bool {
        return pages > 10 // More than 20% of monthly allowance
    }
}

extension RCSubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases,
                               receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            print("RCManager (Delegate): Received updated customer info. Refreshing state...")
            RCSubscriptionManager.shared.evaluateEntitlements(from: customerInfo)
        }
    }
}
