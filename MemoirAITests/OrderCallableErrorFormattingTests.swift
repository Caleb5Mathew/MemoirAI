//
//  OrderCallableErrorFormattingTests.swift
//  MemoirAITests
//

import Foundation
import Testing
@testable import MemoirAI

/// Mirrors `FunctionsErrorDomain` / `FunctionsErrorCode.internal` without linking FirebaseFunctions in tests.
private let firebaseFunctionsDomain = "com.firebase.functions"
private let functionsInternalCode = 13
private let functionsNotFoundCode = 5
private let functionsFailedPreconditionCode = 9
private let functionsUnimplementedCode = 12
private let functionsUnavailableCode = 14

struct OrderCallableErrorFormattingTests {

    @Test func userFacingCallableErrorMessage_replacesBareInternal() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsInternalCode,
            userInfo: [NSLocalizedDescriptionKey: "INTERNAL"]
        )
        let msg = OrderService.userFacingCallableErrorMessage(err)
        #expect(msg.contains("start secure checkout"))
    }

    @Test func userFacingCallableErrorMessage_preservesExplicitServerMessage() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsInternalCode,
            userInfo: [NSLocalizedDescriptionKey: "Unable to start secure checkout. Please try again."]
        )
        let msg = OrderService.userFacingCallableErrorMessage(err)
        #expect(msg == "Unable to start secure checkout. Please try again.")
    }

    @Test func userFacingCallableErrorMessage_passesThroughNonFunctionsErrors() {
        let err = NSError(domain: "test.domain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hello"])
        let msg = OrderService.userFacingCallableErrorMessage(err)
        #expect(msg == "Hello")
    }

    @Test func shouldFallbackToLegacyCartCheckout_trueForNotFound() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsNotFoundCode,
            userInfo: [NSLocalizedDescriptionKey: "NOT FOUND"]
        )
        #expect(OrderService.shouldFallbackToLegacyCartCheckout(err))
    }

    @Test func shouldFallbackToLegacyCartCheckout_trueForUnimplemented() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsUnimplementedCode,
            userInfo: [NSLocalizedDescriptionKey: "UNIMPLEMENTED"]
        )
        #expect(OrderService.shouldFallbackToLegacyCartCheckout(err))
    }

    @Test func shouldFallbackToLegacyCartCheckout_trueForFastDisabledMessage() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsFailedPreconditionCode,
            userInfo: [NSLocalizedDescriptionKey: "Fast checkout is disabled. Use the standard checkout action."]
        )
        #expect(OrderService.shouldFallbackToLegacyCartCheckout(err))
    }

    @Test func shouldFallbackToLegacyCartCheckout_falseForOther() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsInternalCode,
            userInfo: [NSLocalizedDescriptionKey: "INTERNAL"]
        )
        #expect(!OrderService.shouldFallbackToLegacyCartCheckout(err))
    }

    @Test func shouldRetryCheckoutQuoteAfterError_trueForExpiredQuote() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsFailedPreconditionCode,
            userInfo: [NSLocalizedDescriptionKey: "Checkout quote expired. Refresh pricing and try again."]
        )
        #expect(OrderService.shouldRetryCheckoutQuoteAfterError(err))
    }

    @Test func shouldRetryCheckoutQuoteAfterError_falseWhenFastDisabled() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsFailedPreconditionCode,
            userInfo: [NSLocalizedDescriptionKey: "Fast checkout is disabled."]
        )
        #expect(!OrderService.shouldRetryCheckoutQuoteAfterError(err))
    }

    @Test func shouldRetryCheckoutAfterTransientStripeError_trueForStripeConnectionUnavailable() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsUnavailableCode,
            userInfo: [
                NSLocalizedDescriptionKey: "Stripe is temporarily unreachable. Please try again in a moment.",
                "details": [
                    "stage": "stripe_session_create",
                    "stripeType": "StripeConnectionError",
                    "transient": 1
                ]
            ]
        )
        #expect(OrderService.shouldRetryCheckoutAfterTransientStripeError(err))
    }

    @Test func shouldRetryCheckoutAfterTransientStripeError_falseForNonTransient() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsUnavailableCode,
            userInfo: [
                NSLocalizedDescriptionKey: "Temporarily unavailable",
                "details": [
                    "stage": "line_pricing",
                    "transient": 0
                ]
            ]
        )
        #expect(!OrderService.shouldRetryCheckoutAfterTransientStripeError(err))
    }

    #if DEBUG
    @Test func debugCallableErrorFootnote_includesDomainAndCode() {
        let err = NSError(
            domain: firebaseFunctionsDomain,
            code: functionsInternalCode,
            userInfo: [
                NSLocalizedDescriptionKey: "INTERNAL",
                "details": ["hint": "stripe"]
            ]
        )
        let foot = OrderService.debugCallableErrorFootnote(err, function: "createCartCheckoutSession")
        #expect(foot.contains("createCartCheckoutSession"))
        #expect(foot.contains(firebaseFunctionsDomain))
        #expect(foot.contains("code=\(functionsInternalCode)"))
    }
    #endif
}
