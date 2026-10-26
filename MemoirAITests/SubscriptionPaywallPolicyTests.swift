import RevenueCat
import Testing
@testable import MemoirAI

struct SubscriptionPaywallPolicyTests {
    @Test func annualPlanIsTheDefaultWhenBothPlansAreAvailable() {
        #expect(SubscriptionPaywallPolicy.defaultPlan(
            availablePlans: [.monthly, .yearly]
        ) == .yearly)
    }

    @Test func monthlyPlanRemainsAvailableAsTheFallback() {
        #expect(SubscriptionPaywallPolicy.defaultPlan(
            availablePlans: [.monthly]
        ) == .monthly)
        #expect(SubscriptionPaywallPolicy.defaultPlan(availablePlans: []) == nil)
    }

    @Test func callToActionMentionsTrialOnlyWhenEligibilityIsVerified() {
        #expect(SubscriptionPaywallPolicy.callToAction(hasEligibleFreeTrial: true) == "Start Free Trial")
        #expect(SubscriptionPaywallPolicy.callToAction(hasEligibleFreeTrial: false) == "Continue")
    }

    @Test func planLabelsMatchTheStoreBillingPeriods() {
        #expect(SubscriptionPlan.yearly.title == "Yearly")
        #expect(SubscriptionPlan.yearly.billingPeriod == "year")
        #expect(SubscriptionPlan.monthly.title == "Monthly")
        #expect(SubscriptionPlan.monthly.billingPeriod == "month")
    }

    @Test func bestValueRequiresAnnualToCostLessThanTwelveMonths() {
        #expect(SubscriptionPaywallPolicy.annualIsBetterValue(
            annualPrice: 59.99, monthlyPrice: 9.99
        ))
        #expect(!SubscriptionPaywallPolicy.annualIsBetterValue(
            annualPrice: 120, monthlyPrice: 10
        ))
    }

    @Test func selectedPlanRoutesOnlyToItsMatchingPackage() {
        let packages: [SubscriptionPlan: String] = [
            .yearly: "annual-package",
            .monthly: "monthly-package"
        ]
        #expect(SubscriptionPaywallPolicy.selectedValue(
            for: .yearly, values: packages
        ) == "annual-package")
        #expect(SubscriptionPaywallPolicy.selectedValue(
            for: .monthly, values: packages
        ) == "monthly-package")
        #expect(SubscriptionPaywallPolicy.selectedValue(
            for: nil, values: packages
        ) == nil)
    }

    @Test func renewalDisclosureDoesNotPromiseAnUnverifiedTrial() {
        #expect(SubscriptionPaywallPolicy.renewalDisclosure(
            price: "$59.99", billingPeriod: "year", freeTrialDuration: "1 week"
        ) == "1 week free, then $59.99 per year. Cancel anytime.")
        #expect(SubscriptionPaywallPolicy.renewalDisclosure(
            price: "$9.99", billingPeriod: "month", freeTrialDuration: nil
        ) == "$9.99 per month. Cancel anytime.")
    }

    @Test func trialDurationUsesReadableSingularAndPluralUnits() {
        #expect(SubscriptionPaywallPolicy.trialDuration(value: 1, unit: .week) == "1 week")
        #expect(SubscriptionPaywallPolicy.trialDuration(value: 7, unit: .day) == "7 days")
        #expect(SubscriptionPaywallPolicy.trialDuration(value: 3, unit: .month) == "3 months")
    }
}
