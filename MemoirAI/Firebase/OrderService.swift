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

    func createCheckoutSession(
        bookVersionId: String,
        shippingAddress: ShippingAddress,
        shippingLevel: String = "MAIL"
    ) async throws -> (checkoutUrl: URL, sessionId: String) {
        guard Auth.auth().currentUser != nil else {
            throw OrderError.notAuthenticated
        }

        let callable = Functions.functions().httpsCallable("createCheckoutSession")
        let data: [String: Any] = [
            "bookVersionId": bookVersionId,
            "shippingAddress": [
                "name": shippingAddress.name,
                "street1": shippingAddress.street1,
                "city": shippingAddress.city,
                "stateCode": shippingAddress.stateCode,
                "countryCode": shippingAddress.countryCode,
                "postcode": shippingAddress.postcode,
                "phone": shippingAddress.phone
            ],
            "shippingLevel": shippingLevel
        ]

        let result = try await callable.call(data)
        guard let dict = result.data as? [String: Any],
              let urlString = dict["checkoutUrl"] as? String,
              let checkoutUrl = URL(string: urlString),
              let sessionId = dict["sessionId"] as? String else {
            throw OrderError.badResponse
        }

        return (checkoutUrl, sessionId)
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
