import Testing
@testable import MemoirAI

struct CheckoutReturnPolicyTests {
    @Test func acceptsStripeSessionIDsAndRejectsForgedLinks() {
        let valid = "cs_live_1234567890abcdef"
        #expect(CheckoutReturnPolicy.normalizeSessionID("  \(valid)  ") == valid)
        #expect(CheckoutReturnPolicy.normalizeSessionID("cs_live_bad/path") == nil)
        #expect(CheckoutReturnPolicy.normalizeSessionID("not-a-stripe-session") == nil)
        #expect(CheckoutReturnPolicy.normalizeSessionID(nil) == nil)
    }

    @Test func paidCheckoutWaitsForItsOrderLedgerBeforeSuccess() {
        let finalizing = CheckoutReturnVerification(
            verified: false,
            paymentConfirmed: true,
            orderRecorded: false
        )
        #expect(finalizing.isFinalizingPaidOrder)

        let complete = CheckoutReturnVerification(
            verified: true,
            paymentConfirmed: true,
            orderRecorded: true
        )
        #expect(!complete.isFinalizingPaidOrder)
    }
}
