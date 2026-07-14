//
//  AdminOpsService.swift
//  MemoirAI
//
//  Thin wrapper around the admin-only print-order callables used by the in-app
//  developer ops dashboard (`Story/DevOpsDashboardView.swift`).
//
//  SECURITY MODEL: every callable here (`adminListPrintOrders`, `adminSyncOrderFromLulu`,
//  `fulfillOrder`) runs `assertMemoirAdmin` server-side in functions/index.js — access is
//  gated by `ADMIN_EMAILS` / the Auth `admin` custom claim, never by anything on this client.
//  The in-app "developer unlock" only reveals the UI; it grants no authority. A non-admin
//  caller always gets `permission-denied`/`unauthenticated` back, mapped to `.notAdmin` below.
//  Order data returned here is kept in memory only — never persist it to disk.
//

import Foundation
import FirebaseAuth
import FirebaseFunctions

/// Errors surfaced by `AdminOpsService` callables.
enum AdminOpsError: LocalizedError {
    /// Server rejected the call because the signed-in account isn't an admin (or no one is signed in).
    case notAdmin
    case notAuthenticated
    case badResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notAdmin:
            return "This dashboard needs your admin account."
        case .notAuthenticated:
            return "You must be signed in to view print orders."
        case .badResponse:
            return "Invalid response from server."
        case .serverError(let message):
            return message
        }
    }
}

/// Shipping address fields as returned inside `adminListPrintOrders` order records.
struct AdminShippingAddress {
    let name: String?
    let street1: String?
    let street2: String?
    let city: String?
    let stateCode: String?
    let postcode: String?
    let countryCode: String?

    /// "City, ST" for compact display on an order card.
    var cityStateLine: String {
        [city, stateCode]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
    }
}

/// One row from `adminListPrintOrders`. Field names mirror `orderRecordForOpsQueue` in
/// `functions/index.js` — keep the two in sync when the server shape changes.
struct AdminPrintOrder: Identifiable {
    let orderId: String
    let userId: String
    let status: String?
    let refundStatus: String?
    let disputeStatus: String?
    let fulfillmentHold: Bool
    /// Server's authoritative signal that this order is a paid order waiting to be sent to Lulu
    /// (mirrors `d.needsPrintAction` — already excludes held orders).
    let needsPrintAction: Bool
    let customerEmail: String?
    let printTitle: String?
    let bookDisplayName: String?
    let productTitle: String?
    let quantity: Int
    let shippingLevel: String?
    let shippingAddress: AdminShippingAddress?
    let totalCents: Int?
    let currency: String
    let luluPrintJobId: String?
    let luluError: String?
    let luluTrackingUrl: String?
    let createdAt: Date?

    var id: String { orderId }

    var displayTitle: String {
        printTitle ?? bookDisplayName ?? productTitle ?? "Untitled"
    }

    /// Mirrors `chipClass` in `public/ops/app.js`: `lulu_failed` is the one status treated as an error.
    var isLuluFailed: Bool { status == "lulu_failed" }

    /// Mirrors `flagBadgesHtml` in `public/ops/app.js`: any of these should block printing.
    var isOnHold: Bool {
        fulfillmentHold || refundStatus == "refunded" || refundStatus == "partially_refunded" || disputeStatus == "disputed"
    }

    var isInProduction: Bool {
        status == "submitted_to_printer" || status == "printing"
    }

    /// Folds `delivered` into the "Shipped" bucket — the ops UI has no separate delivered chip.
    var isShipped: Bool {
        status == "shipped" || status == "delivered"
    }

    var statusDisplay: String {
        (status ?? "unknown").replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Result of `adminListPrintOrders`, plus the same bucket derivation `public/ops/app.js` uses
/// (`pending = orders.filter(o => o.needsPrintAction)`, flag badges from refund/dispute/hold fields).
struct AdminOrdersSummary {
    let orders: [AdminPrintOrder]
    let totalOrders: Int

    var awaitingFulfillmentCount: Int { orders.filter(\.needsPrintAction).count }
    var failedCount: Int { orders.filter(\.isLuluFailed).count }
    var onHoldCount: Int { orders.filter(\.isOnHold).count }
    var inProductionCount: Int { orders.filter(\.isInProduction).count }
    var shippedCount: Int { orders.filter(\.isShipped).count }
}

/// Wraps the admin-only print-order callables. See file header for the security model.
actor AdminOpsService {
    static let shared = AdminOpsService()

    private init() {}

    /// Calls `adminListPrintOrders`. Throws `.notAdmin` when the signed-in account lacks admin rights.
    func listPrintOrders(limit: Int = 250) async throws -> AdminOrdersSummary {
        guard Auth.auth().currentUser != nil else {
            throw AdminOpsError.notAuthenticated
        }
        let callable = Functions.functions().httpsCallable("adminListPrintOrders")
        callable.timeoutInterval = 120
        do {
            let result = try await callable.call(["limit": limit])
            guard let dict = result.data as? [String: Any] else {
                throw AdminOpsError.badResponse
            }
            let rawOrders = dict["all"] as? [[String: Any]] ?? []
            let orders = rawOrders.compactMap(Self.parseOrder)
            let stats = dict["stats"] as? [String: Any] ?? [:]
            let totalOrders = (stats["totalOrders"] as? Int)
                ?? (stats["totalOrders"] as? NSNumber)?.intValue
                ?? orders.count
            return AdminOrdersSummary(orders: orders, totalOrders: totalOrders)
        } catch {
            throw Self.mapCallableError(error)
        }
    }

    /// Calls `adminSyncOrderFromLulu`. The server updates the order document in place; callers should
    /// re-run `listPrintOrders` afterward to reflect any change.
    func syncOrderFromLulu(orderId: String, userId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw AdminOpsError.notAuthenticated
        }
        let callable = Functions.functions().httpsCallable("adminSyncOrderFromLulu")
        callable.timeoutInterval = 60
        do {
            _ = try await callable.call(["orderId": orderId, "userId": userId])
        } catch {
            throw Self.mapCallableError(error)
        }
    }

    /// Calls `fulfillOrder`, submitting a paid order to Lulu for printing.
    /// The server rejects with `failed-precondition` for holds, test orders, or an unexpected
    /// order status — that message should be surfaced to the caller verbatim.
    func fulfillOrder(orderId: String, userId: String) async throws -> (luluJobId: String?, status: String) {
        guard Auth.auth().currentUser != nil else {
            throw AdminOpsError.notAuthenticated
        }
        let callable = Functions.functions().httpsCallable("fulfillOrder")
        callable.timeoutInterval = 120
        do {
            let result = try await callable.call(["orderId": orderId, "userId": userId])
            guard let dict = result.data as? [String: Any] else {
                throw AdminOpsError.badResponse
            }
            let jobId = dict["luluJobId"] as? String
            let status = dict["status"] as? String ?? "submitted_to_printer"
            return (jobId, status)
        } catch {
            throw Self.mapCallableError(error)
        }
    }

    /// Maps Firebase callable failures to `AdminOpsError`, reusing `OrderService`'s callable-error
    /// copy for anything that isn't an authorization failure.
    private static func mapCallableError(_ error: Error) -> Error {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else { return error }
        if ns.code == FunctionsErrorCode.permissionDenied.rawValue
            || ns.code == FunctionsErrorCode.unauthenticated.rawValue {
            return AdminOpsError.notAdmin
        }
        return AdminOpsError.serverError(OrderService.userFacingCallableErrorMessage(error))
    }

    private static func parseOrder(_ dict: [String: Any]) -> AdminPrintOrder? {
        guard let orderId = dict["orderId"] as? String, let userId = dict["userId"] as? String else {
            return nil
        }
        var shipping: AdminShippingAddress?
        if let ship = dict["shippingAddress"] as? [String: Any] {
            shipping = AdminShippingAddress(
                name: ship["name"] as? String,
                street1: ship["street1"] as? String,
                street2: ship["street2"] as? String,
                city: ship["city"] as? String,
                stateCode: ship["stateCode"] as? String,
                postcode: ship["postcode"] as? String,
                countryCode: ship["countryCode"] as? String
            )
        }
        let totalCents = (dict["totalCents"] as? Int) ?? (dict["totalCents"] as? NSNumber)?.intValue
        let quantity = (dict["quantity"] as? Int) ?? (dict["quantity"] as? NSNumber)?.intValue ?? 1
        return AdminPrintOrder(
            orderId: orderId,
            userId: userId,
            status: dict["status"] as? String,
            refundStatus: dict["refundStatus"] as? String,
            disputeStatus: dict["disputeStatus"] as? String,
            fulfillmentHold: dict["fulfillmentHold"] as? Bool ?? false,
            needsPrintAction: dict["needsPrintAction"] as? Bool ?? false,
            customerEmail: dict["customerEmail"] as? String,
            printTitle: dict["printTitle"] as? String,
            bookDisplayName: dict["bookDisplayName"] as? String,
            productTitle: dict["productTitle"] as? String,
            quantity: quantity,
            shippingLevel: dict["shippingLevel"] as? String,
            shippingAddress: shipping,
            totalCents: totalCents,
            currency: dict["currency"] as? String ?? "usd",
            luluPrintJobId: dict["luluPrintJobId"] as? String,
            luluError: dict["luluError"] as? String,
            luluTrackingUrl: dict["luluTrackingUrl"] as? String,
            createdAt: Self.parseIsoDate(dict["createdAt"])
        )
    }

    private static func parseIsoDate(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
