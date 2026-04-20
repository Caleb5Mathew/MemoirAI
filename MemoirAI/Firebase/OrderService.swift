//
//  OrderService.swift
//  MemoirAI
//
//  Handles book print orders via Stripe Checkout and Firestore.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import UIKit

// MARK: - Callable HTTPS errors (Firebase Functions)

extension OrderService {
    /// Maps Firebase callable failures to readable copy; hides bare `INTERNAL` when the server omits a message.
    static func userFacingCallableErrorMessage(_ error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else {
            return error.localizedDescription
        }
        let desc = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if ns.code == FunctionsErrorCode.internal.rawValue {
            if desc.isEmpty || desc.uppercased() == "INTERNAL" {
                return "Couldn’t start secure checkout. Please try again. If this keeps happening, contact support."
            }
            return desc
        }
        if ns.code == FunctionsErrorCode.unauthenticated.rawValue {
            return desc.isEmpty ? "You must be signed in to order." : desc
        }
        if ns.code == FunctionsErrorCode.unavailable.rawValue {
            return desc.isEmpty ? "Checkout is temporarily unavailable. Please try again in a few minutes." : desc
        }
        if ns.code == FunctionsErrorCode.resourceExhausted.rawValue {
            return desc.isEmpty ? "Checkout is already in progress. Wait a moment and try again." : desc
        }
        if ns.code == FunctionsErrorCode.failedPrecondition.rawValue {
            if desc.localizedCaseInsensitiveContains("quote expired")
                || desc.localizedCaseInsensitiveContains("refresh pricing") {
                return desc.isEmpty ? "Pricing changed. Please wait for a fresh estimate and try again." : desc
            }
            return desc.isEmpty ? error.localizedDescription : desc
        }
        if ns.code == FunctionsErrorCode.notFound.rawValue {
            return desc.isEmpty ? "Checkout service not available. Try again in a moment." : desc
        }
        return desc.isEmpty ? error.localizedDescription : desc
    }

    /// When fast checkout callables are missing or disabled server-side, fall back to legacy `createCartCheckoutSession`.
    static func shouldFallbackToLegacyCartCheckout(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return false }
        switch ns.code {
        case FunctionsErrorCode.notFound.rawValue:
            return true
        case FunctionsErrorCode.unimplemented.rawValue:
            return true
        case FunctionsErrorCode.failedPrecondition.rawValue:
            let desc = ns.localizedDescription
            return desc.contains("Fast checkout is disabled")
        default:
            return false
        }
    }

    /// True when a failed-precondition likely means the server quote is stale (refresh `prepareCartCheckoutQuote` once).
    static func shouldRetryCheckoutQuoteAfterError(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return false }
        guard ns.code == FunctionsErrorCode.failedPrecondition.rawValue else { return false }
        let d = ns.localizedDescription.lowercased()
        if d.contains("fast checkout is disabled") { return false }
        return d.contains("quote") || d.contains("expired") || d.contains("refresh") || d.contains("changed")
            || d.contains("no longer valid")
    }

    /// True when checkout failed due to a likely transient Stripe transport outage.
    /// We auto-retry once in client checkout flow before surfacing an error.
    static func shouldRetryCheckoutAfterTransientStripeError(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return false }
        guard ns.code == FunctionsErrorCode.unavailable.rawValue else { return false }

        if let details = ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any] {
            let stage = String(describing: details["stage"] ?? "").lowercased()
            let stripeType = String(describing: details["stripeType"] ?? "").lowercased()
            let stripeMessage = String(describing: details["stripeMessage"] ?? "").lowercased()
            let transientValue = String(describing: details["transient"] ?? "").lowercased()
            let transient = transientValue == "1" || transientValue == "true"
            if stage.contains("stripe_session_create") && (transient || stripeType.contains("connection") || stripeMessage.contains("connection")) {
                return true
            }
        }

        let message = ns.localizedDescription.lowercased()
        return message.contains("temporarily unreachable") || message.contains("connection to stripe")
    }

    #if DEBUG
    /// Console + optional in-app footnote: correlate with Cloud Logging (`createCartCheckoutSession`, `cartOrderGroupId`).
    static func debugCallableErrorFootnote(_ error: Error, function: String) -> String {
        let ns = error as NSError
        var parts: [String] = ["fn=\(function)"]
        if ns.domain == FunctionsErrorDomain {
            parts.append("domain=\(FunctionsErrorDomain)")
            parts.append("code=\(ns.code)")
            if let details = ns.userInfo[FunctionsErrorDetailsKey] {
                parts.append("details=\(String(describing: details))")
            }
            if let region = ns.userInfo["region"] {
                parts.append("region=\(region)")
            }
        } else {
            parts.append("domain=\(ns.domain)")
            parts.append("code=\(ns.code)")
        }
        parts.append("msg=\(ns.localizedDescription)")
        return "DEBUG " + parts.joined(separator: " ")
    }
    #endif
}

struct ShippingAddress: Codable {
    var name: String = ""
    var street1: String = ""
    var city: String = ""
    var stateCode: String = ""
    var countryCode: String = "US"
    var postcode: String = ""
    var phone: String = ""
}

enum OrderStatus: String {
    case paid = "paid"
    case pendingFulfillment = "pending_fulfillment"
    case submittedToPrinter = "submitted_to_printer"
    case printing = "printing"
    case shipped = "shipped"
    case delivered = "delivered"
    case failed = "failed"
    case luluFailed = "lulu_failed"
    case testSimulated = "test_simulated"
}

// MARK: - Checkout estimate & address search (Lulu + Google via Cloud Functions)

struct LuluEstimateWarning: Sendable {
    let type: String
    let code: String
    let path: String
    let message: String
}

struct SuggestedShippingAddress: Sendable {
    var street1: String
    var street2: String
    var city: String
    var stateCode: String
    var postcode: String
    var countryCode: String
}

struct CartCheckoutLineEstimate: Sendable {
    let bookVersionId: String
    let productOptionId: String
    let productTitle: String
    let quantity: Int
    /// Book subtotal for the full line (all copies), from Lulu quantity-aware pricing.
    let lineBookBaseCents: Int
    /// Shipping for the full line (one shipment), from Lulu quantity-aware pricing.
    let lineShippingCents: Int
    let unitBookBaseCents: Int
    let unitShippingCents: Int
    let unitTotalCents: Int
    let lineTotalCents: Int
    let pageCount: Int
}

struct ShippingMethodEstimate: Sendable, Identifiable {
    var id: String { level }
    let level: String
    let label: String
    let shippingCents: Int
    let estimatedArrivalMinDays: Int?
    let estimatedArrivalMaxDays: Int?
    let estimatedArrivalMinDate: String?
    let estimatedArrivalMaxDate: String?
}

struct CartCheckoutEstimate: Sendable {
    let lines: [CartCheckoutLineEstimate]
    /// Sum of book/print lines only (no shipping). Mirrors Firebase `booksSubtotalCents`.
    let booksSubtotalCents: Int
    /// Combined shipment from one Lulu multi-line cost calc. Fallback: sum of line shipping when key absent.
    let orderShippingCents: Int
    let subtotalCents: Int
    let estimatedTotalCents: Int
    let currency: String
    let shippingMethods: [ShippingMethodEstimate]
    let warnings: [LuluEstimateWarning]
    let suggestedAddress: SuggestedShippingAddress?
    let fallback: Bool
    /// Set when estimate came from `prepareCartCheckoutQuote` (fast checkout path).
    let quoteId: String?
    let cartHash: String?
    let quoteExpiresAtMillis: Int64?
    let fastCheckoutEnabled: Bool?
}

struct CheckoutPriceEstimate: Sendable {
    let bookBaseCents: Int
    let shippingCents: Int
    let estimatedTotalCents: Int
    let currency: String
    let marginPercent: Int?
    let luluTotalCostInclTax: String?
    let luluShippingCostInclTax: String?
    let pricingFloorApplied: Bool
    let luluCurrency: String?
    let warnings: [LuluEstimateWarning]
    let suggestedAddress: SuggestedShippingAddress?
    let fallback: Bool
    let fallbackReason: String?
    let fallbackPhase: String?
    let fallbackStatusCode: Int?
    let fallbackDetail: String?
    let selectedProductOptionId: String?
    let selectedPodPackageId: String?
    let selectedProductTitle: String?
}

struct AddressPrediction: Identifiable, Sendable {
    var id: String { placeId }
    let placeId: String
    let description: String
}

struct OrderRecord: Identifiable {
    let id: String
    let orderId: String
    let bookVersionId: String
    let status: String
    let shippingAddress: ShippingAddress?
    let pricing: (totalCents: Int, currency: String)?
    let luluTrackingUrl: String?
    let stripeSessionId: String?
    let luluStatusHistory: [[String: Any]]
    let updatedAt: Date?
    let createdAt: Date?

    var statusDisplay: String {
        switch status {
        case OrderStatus.paid.rawValue: return "Paid — Processing"
        case OrderStatus.pendingFulfillment.rawValue: return "Pending Fulfillment"
        case OrderStatus.submittedToPrinter.rawValue: return "Sent to Printer"
        case OrderStatus.printing.rawValue: return "Printing"
        case OrderStatus.shipped.rawValue: return "Shipped"
        case OrderStatus.delivered.rawValue: return "Delivered"
        case OrderStatus.failed.rawValue, OrderStatus.luluFailed.rawValue: return "Failed"
        case OrderStatus.testSimulated.rawValue: return "Test Order"
        default: return status
        }
    }
}

final class OrderService {
    static let shared = OrderService()
    private let db = Firestore.firestore()

    private init() {}

    func estimateCheckoutPricing(
        bookVersionId: String,
        shippingAddress: ShippingAddress,
        shippingLevel: String = "MAIL",
        productOptionId: String? = nil
    ) async throws -> CheckoutPriceEstimate {
        guard Auth.auth().currentUser != nil else {
            throw OrderError.notAuthenticated
        }
        let callable = Functions.functions().httpsCallable("estimateCheckoutPricing")
        var data: [String: Any] = [
            "bookVersionId": bookVersionId,
            "shippingAddress": shippingDict(from: shippingAddress),
            "shippingLevel": shippingLevel
        ]
        if let productOptionId, !productOptionId.isEmpty {
            data["productOptionId"] = productOptionId
        }
        let result = try await callable.call(data)
        guard let dict = result.data as? [String: Any] else {
            throw OrderError.badResponse
        }
        return Self.parseCheckoutEstimate(dict)
    }

    func autocompleteAddress(query: String, sessionToken: String?, countryCode: String?) async throws -> [AddressPrediction] {
        guard Auth.auth().currentUser != nil else {
            throw OrderError.notAuthenticated
        }
        var data: [String: Any] = ["query": query]
        if let sessionToken { data["sessionToken"] = sessionToken }
        if let countryCode, countryCode.count == 2 {
            data["countryCode"] = countryCode.uppercased()
        }
        let callable = Functions.functions().httpsCallable("autocompleteAddress")
        let result = try await callable.call(data)
        guard let dict = result.data as? [String: Any],
              let raw = dict["predictions"] as? [[String: Any]] else {
            throw OrderError.badResponse
        }
        return raw.compactMap { row in
            guard let placeId = row["placeId"] as? String else { return nil }
            let description = row["description"] as? String ?? ""
            return AddressPrediction(placeId: placeId, description: description)
        }
    }

    /// Resolves a Google Place ID into structured address fields (merge into existing name/phone on client).
    func resolveAddressPlace(placeId: String, sessionToken: String?) async throws -> (formattedAddress: String, shippingAddress: ShippingAddress) {
        guard Auth.auth().currentUser != nil else {
            throw OrderError.notAuthenticated
        }
        var data: [String: Any] = ["placeId": placeId]
        if let sessionToken { data["sessionToken"] = sessionToken }
        let callable = Functions.functions().httpsCallable("resolveAddressPlace")
        let result = try await callable.call(data)
        guard let dict = result.data as? [String: Any],
              let addr = dict["shippingAddress"] as? [String: Any] else {
            throw OrderError.badResponse
        }
        let formatted = dict["formattedAddress"] as? String ?? ""
        var ship = ShippingAddress()
        ship.street1 = addr["street1"] as? String ?? ""
        ship.city = addr["city"] as? String ?? ""
        ship.stateCode = addr["stateCode"] as? String ?? ""
        ship.postcode = addr["postcode"] as? String ?? ""
        ship.countryCode = addr["countryCode"] as? String ?? "US"
        return (formatted, ship)
    }

    func createCheckoutSession(
        bookVersionId: String,
        shippingAddress: ShippingAddress,
        shippingLevel: String = "MAIL",
        clientEstimatedTotalCents: Int? = nil,
        productOptionId: String? = nil
    ) async throws -> (checkoutUrl: URL, sessionId: String) {
        guard Auth.auth().currentUser != nil else {
            throw OrderError.notAuthenticated
        }

        let callable = Functions.functions().httpsCallable("createCheckoutSession")
        callable.timeoutInterval = 180
        var data: [String: Any] = [
            "bookVersionId": bookVersionId,
            "shippingAddress": shippingDict(from: shippingAddress),
            "shippingLevel": shippingLevel
        ]
        if let c = clientEstimatedTotalCents {
            data["clientEstimatedTotalCents"] = c
        }
        if let productOptionId, !productOptionId.isEmpty {
            data["productOptionId"] = productOptionId
        }

        let result = try await callable.call(data)
        guard let dict = result.data as? [String: Any],
              let urlString = dict["checkoutUrl"] as? String,
              let checkoutUrl = URL(string: urlString),
              let sessionId = dict["sessionId"] as? String else {
            throw OrderError.badResponse
        }

        return (checkoutUrl, sessionId)
    }

    func estimateCartCheckoutPricing(
        items: [(bookVersionId: String, productOptionId: String?, quantity: Int)],
        shippingAddress: ShippingAddress,
        shippingLevel: String = "MAIL"
    ) async throws -> CartCheckoutEstimate {
        guard Auth.auth().currentUser != nil else {
            throw OrderError.notAuthenticated
        }
        let payloadItems: [[String: Any]] = items.map { row in
            var d: [String: Any] = [
                "bookVersionId": row.bookVersionId,
                "quantity": row.quantity
            ]
            if let opt = row.productOptionId, !opt.isEmpty {
                d["productOptionId"] = opt
            }
            return d
        }
        let callable = Functions.functions().httpsCallable("estimateCartCheckoutPricing")
        let data: [String: Any] = [
            "items": payloadItems,
            "shippingAddress": shippingDict(from: shippingAddress),
            "shippingLevel": shippingLevel
        ]
        let result = try await callable.call(data)
        guard let dict = result.data as? [String: Any] else {
            throw OrderError.badResponse
        }
        return Self.parseCartCheckoutEstimate(dict)
    }

    /// Live Lulu cart pricing plus a durable checkout quote for `createCartCheckoutSessionFast`.
    /// Falls back to `estimateCartCheckoutPricing` when `prepareCartCheckoutQuote` is not deployed (NOT FOUND / UNIMPLEMENTED).
    func prepareCartCheckoutPricing(
        items: [(bookVersionId: String, productOptionId: String?, quantity: Int)],
        shippingAddress: ShippingAddress,
        shippingLevel: String = "MAIL",
        clientPayloadHash: String? = nil
    ) async throws -> CartCheckoutEstimate {
        guard Auth.auth().currentUser != nil else {
            throw OrderError.notAuthenticated
        }
        let payloadItems: [[String: Any]] = items.map { row in
            var d: [String: Any] = [
                "bookVersionId": row.bookVersionId,
                "quantity": row.quantity
            ]
            if let opt = row.productOptionId, !opt.isEmpty {
                d["productOptionId"] = opt
            }
            return d
        }
        var data: [String: Any] = [
            "items": payloadItems,
            "shippingAddress": shippingDict(from: shippingAddress),
            "shippingLevel": shippingLevel
        ]
        if let h = clientPayloadHash, !h.isEmpty {
            data["clientPayloadHash"] = h
        }
        do {
            let callable = Functions.functions().httpsCallable("prepareCartCheckoutQuote")
            callable.timeoutInterval = 180
            let result = try await callable.call(data)
            guard let dict = result.data as? [String: Any] else {
                throw OrderError.badResponse
            }
            #if DEBUG
            print("📦 prepareCartCheckoutQuote ok (fast quote path)")
            #endif
            return Self.parseCartCheckoutEstimate(dict)
        } catch {
            let ns = error as NSError
            let shouldFallback = ns.domain == FunctionsErrorDomain && (
                ns.code == FunctionsErrorCode.notFound.rawValue
                    || ns.code == FunctionsErrorCode.unimplemented.rawValue
            )
            if shouldFallback {
                #if DEBUG
                print(
                    "📦 prepareCartCheckoutQuote fallback=estimateCartCheckoutPricing " +
                    OrderService.debugCallableErrorFootnote(error, function: "prepareCartCheckoutQuote")
                )
                #endif
                return try await estimateCartCheckoutPricing(
                    items: items,
                    shippingAddress: shippingAddress,
                    shippingLevel: shippingLevel
                )
            }
            throw error
        }
    }

    func createCartCheckoutSessionFast(
        quoteId: String,
        cartHash: String,
        idempotencyKey: String,
        clientEstimatedTotalCents: Int? = nil
    ) async throws -> (checkoutUrl: URL, sessionId: String, cartOrderGroupId: String?, totalCents: Int) {
        guard Auth.auth().currentUser != nil else {
            throw OrderError.notAuthenticated
        }
        var data: [String: Any] = [
            "quoteId": quoteId,
            "cartHash": cartHash,
            "idempotencyKey": idempotencyKey
        ]
        if let c = clientEstimatedTotalCents {
            data["clientEstimatedTotalCents"] = c
        }
        let callable = Functions.functions().httpsCallable("createCartCheckoutSessionFast")
        callable.timeoutInterval = 120
        let result = try await callable.call(data)
        guard let dict = result.data as? [String: Any],
              let urlString = dict["checkoutUrl"] as? String,
              let checkoutUrl = URL(string: urlString),
              let sessionId = dict["sessionId"] as? String else {
            throw OrderError.badResponse
        }
        let groupId = dict["cartOrderGroupId"] as? String
        let total = (dict["totalCents"] as? Int) ?? (dict["totalCents"] as? NSNumber)?.intValue ?? 0
        return (checkoutUrl, sessionId, groupId, total)
    }

    func createCartCheckoutSession(
        items: [(bookVersionId: String, productOptionId: String?, quantity: Int)],
        shippingAddress: ShippingAddress,
        shippingLevel: String = "MAIL",
        clientEstimatedTotalCents: Int? = nil
    ) async throws -> (checkoutUrl: URL, sessionId: String, cartOrderGroupId: String?, totalCents: Int) {
        guard Auth.auth().currentUser != nil else {
            throw OrderError.notAuthenticated
        }
        let payloadItems: [[String: Any]] = items.map { row in
            var d: [String: Any] = [
                "bookVersionId": row.bookVersionId,
                "quantity": row.quantity
            ]
            if let opt = row.productOptionId, !opt.isEmpty {
                d["productOptionId"] = opt
            }
            return d
        }
        var data: [String: Any] = [
            "items": payloadItems,
            "shippingAddress": shippingDict(from: shippingAddress),
            "shippingLevel": shippingLevel
        ]
        if let c = clientEstimatedTotalCents {
            data["clientEstimatedTotalCents"] = c
        }
        let callable = Functions.functions().httpsCallable("createCartCheckoutSession")
        callable.timeoutInterval = 180
        let result = try await callable.call(data)
        guard let dict = result.data as? [String: Any],
              let urlString = dict["checkoutUrl"] as? String,
              let checkoutUrl = URL(string: urlString),
              let sessionId = dict["sessionId"] as? String else {
            throw OrderError.badResponse
        }
        let groupId = dict["cartOrderGroupId"] as? String
        let total = (dict["totalCents"] as? Int) ?? (dict["totalCents"] as? NSNumber)?.intValue ?? 0
        return (checkoutUrl, sessionId, groupId, total)
    }

    private func shippingDict(from shippingAddress: ShippingAddress) -> [String: Any] {
        [
            "name": shippingAddress.name,
            "street1": shippingAddress.street1,
            "city": shippingAddress.city,
            "stateCode": shippingAddress.stateCode,
            "countryCode": shippingAddress.countryCode,
            "postcode": shippingAddress.postcode,
            "phone": shippingAddress.phone
        ]
    }

    private static func parseCheckoutEstimate(_ dict: [String: Any]) -> CheckoutPriceEstimate {
        let bookBase = (dict["bookBaseCents"] as? Int) ?? (dict["bookBaseCents"] as? NSNumber)?.intValue ?? 0
        let shipCents = (dict["shippingCents"] as? Int) ?? (dict["shippingCents"] as? NSNumber)?.intValue ?? 0
        let total = (dict["estimatedTotalCents"] as? Int) ?? (dict["estimatedTotalCents"] as? NSNumber)?.intValue ?? bookBase
        let currency = dict["currency"] as? String ?? "usd"
        let margin = (dict["marginPercent"] as? Int) ?? (dict["marginPercent"] as? NSNumber)?.intValue
        let luluTotal = dict["luluTotalCostInclTax"] as? String
        let luluShipping = dict["luluShippingCostInclTax"] as? String
        let pricingFloorApplied = dict["pricingFloorApplied"] as? Bool ?? false
        let luluCur = dict["luluCurrency"] as? String
        let fallback = dict["fallback"] as? Bool ?? false
        let fallbackReason = dict["fallbackReason"] as? String
        let fallbackPhase = dict["fallbackPhase"] as? String
        let fallbackStatusCode = (dict["fallbackStatusCode"] as? Int) ?? (dict["fallbackStatusCode"] as? NSNumber)?.intValue
        let fallbackDetail = dict["fallbackDetail"] as? String
        let selectedProductOptionId = dict["selectedProductOptionId"] as? String
        let selectedPodPackageId = dict["selectedPodPackageId"] as? String
        let selectedProductTitle = dict["selectedProductTitle"] as? String
        var warnings: [LuluEstimateWarning] = []
        if let wArr = dict["warnings"] as? [[String: Any]] {
            for w in wArr {
                warnings.append(LuluEstimateWarning(
                    type: w["type"] as? String ?? "",
                    code: w["code"] as? String ?? "",
                    path: w["path"] as? String ?? "",
                    message: w["message"] as? String ?? ""
                ))
            }
        }
        var suggested: SuggestedShippingAddress?
        if let s = dict["suggestedAddress"] as? [String: Any] {
            suggested = SuggestedShippingAddress(
                street1: s["street1"] as? String ?? "",
                street2: s["street2"] as? String ?? "",
                city: s["city"] as? String ?? "",
                stateCode: s["stateCode"] as? String ?? "",
                postcode: s["postcode"] as? String ?? "",
                countryCode: s["countryCode"] as? String ?? ""
            )
        }
        return CheckoutPriceEstimate(
            bookBaseCents: bookBase,
            shippingCents: shipCents,
            estimatedTotalCents: total,
            currency: currency,
            marginPercent: margin,
            luluTotalCostInclTax: luluTotal,
            luluShippingCostInclTax: luluShipping,
            pricingFloorApplied: pricingFloorApplied,
            luluCurrency: luluCur,
            warnings: warnings,
            suggestedAddress: suggested,
            fallback: fallback,
            fallbackReason: fallbackReason,
            fallbackPhase: fallbackPhase,
            fallbackStatusCode: fallbackStatusCode,
            fallbackDetail: fallbackDetail,
            selectedProductOptionId: selectedProductOptionId,
            selectedPodPackageId: selectedPodPackageId,
            selectedProductTitle: selectedProductTitle
        )
    }

    private static func parseCartCheckoutEstimate(_ dict: [String: Any]) -> CartCheckoutEstimate {
        let sub = (dict["subtotalCents"] as? Int) ?? (dict["subtotalCents"] as? NSNumber)?.intValue ?? 0
        let total = (dict["estimatedTotalCents"] as? Int) ?? (dict["estimatedTotalCents"] as? NSNumber)?.intValue ?? sub
        let currency = dict["currency"] as? String ?? "usd"
        let fallback = dict["fallback"] as? Bool ?? false
        var lines: [CartCheckoutLineEstimate] = []
        if let rawLines = dict["lines"] as? [[String: Any]] {
            for row in rawLines {
                let qty = (row["quantity"] as? Int) ?? (row["quantity"] as? NSNumber)?.intValue ?? 1
                let unitBook = (row["unitBookBaseCents"] as? Int) ?? (row["unitBookBaseCents"] as? NSNumber)?.intValue ?? 0
                let unitShip = (row["unitShippingCents"] as? Int) ?? (row["unitShippingCents"] as? NSNumber)?.intValue ?? 0
                let lineBook = (row["lineBookBaseCents"] as? Int) ?? (row["lineBookBaseCents"] as? NSNumber)?.intValue
                let lineShip = (row["lineShippingCents"] as? Int) ?? (row["lineShippingCents"] as? NSNumber)?.intValue
                let resolvedLineBook = lineBook ?? unitBook * max(1, qty)
                let resolvedLineShip = lineShip ?? unitShip * max(1, qty)
                lines.append(CartCheckoutLineEstimate(
                    bookVersionId: row["bookVersionId"] as? String ?? "",
                    productOptionId: row["productOptionId"] as? String ?? "",
                    productTitle: row["productTitle"] as? String ?? "",
                    quantity: qty,
                    lineBookBaseCents: resolvedLineBook,
                    lineShippingCents: resolvedLineShip,
                    unitBookBaseCents: unitBook,
                    unitShippingCents: unitShip,
                    unitTotalCents: (row["unitTotalCents"] as? Int) ?? (row["unitTotalCents"] as? NSNumber)?.intValue ?? 0,
                    lineTotalCents: (row["lineTotalCents"] as? Int) ?? (row["lineTotalCents"] as? NSNumber)?.intValue ?? 0,
                    pageCount: (row["pageCount"] as? Int) ?? (row["pageCount"] as? NSNumber)?.intValue ?? 0
                ))
            }
        }
        var warnings: [LuluEstimateWarning] = []
        if let wArr = dict["warnings"] as? [[String: Any]] {
            for w in wArr {
                warnings.append(LuluEstimateWarning(
                    type: w["type"] as? String ?? "",
                    code: w["code"] as? String ?? "",
                    path: w["path"] as? String ?? "",
                    message: w["message"] as? String ?? ""
                ))
            }
        }
        var suggested: SuggestedShippingAddress?
        if let s = dict["suggestedAddress"] as? [String: Any] {
            suggested = SuggestedShippingAddress(
                street1: s["street1"] as? String ?? "",
                street2: s["street2"] as? String ?? "",
                city: s["city"] as? String ?? "",
                stateCode: s["stateCode"] as? String ?? "",
                postcode: s["postcode"] as? String ?? "",
                countryCode: s["countryCode"] as? String ?? ""
            )
        }
        var shippingMethods: [ShippingMethodEstimate] = []
        if let rawMethods = dict["shippingMethods"] as? [[String: Any]] {
            for method in rawMethods {
                let level = method["level"] as? String ?? ""
                guard !level.isEmpty else { continue }
                shippingMethods.append(
                    ShippingMethodEstimate(
                        level: level,
                        label: method["label"] as? String ?? level,
                        shippingCents: (method["shippingCents"] as? Int) ?? (method["shippingCents"] as? NSNumber)?.intValue ?? 0,
                        estimatedArrivalMinDays: (method["estimatedArrivalMinDays"] as? Int) ?? (method["estimatedArrivalMinDays"] as? NSNumber)?.intValue,
                        estimatedArrivalMaxDays: (method["estimatedArrivalMaxDays"] as? Int) ?? (method["estimatedArrivalMaxDays"] as? NSNumber)?.intValue,
                        estimatedArrivalMinDate: method["estimatedArrivalMinDate"] as? String,
                        estimatedArrivalMaxDate: method["estimatedArrivalMaxDate"] as? String
                    )
                )
            }
        }
        let booksFromLines = lines.reduce(0) { $0 + $1.lineBookBaseCents }
        let booksSubtotal = (dict["booksSubtotalCents"] as? Int)
            ?? (dict["booksSubtotalCents"] as? NSNumber)?.intValue
            ?? booksFromLines
        let summedLineShipping = lines.reduce(0) { $0 + $1.lineShippingCents }
        let orderShipRaw = (dict["orderShippingCents"] as? Int)
            ?? (dict["orderShippingCents"] as? NSNumber)?.intValue
        let orderShipping = orderShipRaw ?? summedLineShipping

        let quoteId = dict["quoteId"] as? String
        let cartHash = dict["cartHash"] as? String
        let quoteExpiresAtMillis: Int64? = {
            if let n = dict["expiresAtMillis"] as? NSNumber { return n.int64Value }
            if let i = dict["expiresAtMillis"] as? Int64 { return i }
            if let i = dict["expiresAtMillis"] as? Int { return Int64(i) }
            return nil
        }()
        let fastCheckoutEnabled = dict["fastCheckoutEnabled"] as? Bool

        return CartCheckoutEstimate(
            lines: lines,
            booksSubtotalCents: booksSubtotal,
            orderShippingCents: orderShipping,
            subtotalCents: sub,
            estimatedTotalCents: total,
            currency: currency,
            shippingMethods: shippingMethods,
            warnings: warnings,
            suggestedAddress: suggested,
            fallback: fallback,
            quoteId: quoteId,
            cartHash: cartHash,
            quoteExpiresAtMillis: quoteExpiresAtMillis,
            fastCheckoutEnabled: fastCheckoutEnabled
        )
    }

    func ordersListener(userId: String, completion: @escaping ([OrderRecord]) -> Void) -> ListenerRegistration {
        db.collection("users").document(userId).collection("orders")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents, error == nil else {
                    completion([])
                    return
                }
                let orders = docs.compactMap { doc -> OrderRecord? in
                    let d = doc.data()
                    guard let orderId = d["orderId"] as? String else { return nil }
                    let addr = d["shippingAddress"] as? [String: Any]
                    var shipping: ShippingAddress?
                    if let a = addr {
                        shipping = ShippingAddress(
                            name: a["name"] as? String ?? "",
                            street1: a["street1"] as? String ?? "",
                            city: a["city"] as? String ?? "",
                            stateCode: a["stateCode"] as? String ?? "",
                            countryCode: a["countryCode"] as? String ?? "US",
                            postcode: a["postcode"] as? String ?? "",
                            phone: a["phone"] as? String ?? ""
                        )
                    }
                    let pricing = d["pricing"] as? [String: Any]
                    let totalCents = pricing?["totalCents"] as? Int ?? 0
                    let currency = pricing?["currency"] as? String ?? "usd"
                    let createdAt = (d["createdAt"] as? Timestamp)?.dateValue()
                    return OrderRecord(
                        id: orderId,
                        orderId: orderId,
                        bookVersionId: d["bookVersionId"] as? String ?? "",
                        status: d["status"] as? String ?? "",
                        shippingAddress: shipping,
                        pricing: (totalCents, currency),
                        luluTrackingUrl: d["luluTrackingUrl"] as? String,
                        stripeSessionId: d["stripeSessionId"] as? String,
                        luluStatusHistory: d["luluStatusHistory"] as? [[String: Any]] ?? [],
                        updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                        createdAt: createdAt
                    )
                }
                completion(orders)
            }
    }

    static func markOrdersSeen() {
        UserDefaults.standard.set(Date(), forKey: "ordersLastViewedAt")
    }

    static func hasUnseenStatusUpdate(orders: [OrderRecord]) -> Bool {
        let lastViewed = UserDefaults.standard.object(forKey: "ordersLastViewedAt") as? Date ?? .distantPast
        return orders.contains { order in
            guard let updated = order.updatedAt else { return false }
            return updated > lastViewed && order.status != OrderStatus.paid.rawValue
        }
    }
}

enum OrderError: LocalizedError {
    case notAuthenticated
    case badResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to order."
        case .badResponse: return "Invalid response from server."
        case .serverError(let msg): return msg
        }
    }
}
