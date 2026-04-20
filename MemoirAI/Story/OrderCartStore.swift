//
//  OrderCartStore.swift
//  MemoirAI
//
//  Device-persistent print cart (UserDefaults), scoped by signed-in Firebase user.
//

import Foundation
import FirebaseAuth
import Combine

struct OrderCartItem: Codable, Identifiable, Equatable {
    var id: UUID
    var bookVersionId: String
    var displayTitle: String
    var coverURL: String?
    var coverPDFURL: String?
    /// Matches `BookVersionRecord.coverThumbnailCacheRevision` when the line was added (invalidates stale PDF panel thumbs).
    var coverThumbnailCacheRevision: String?
    var fallbackImageURL: String?
    var fallbackRenderedURL: String?
    var productOptionId: String
    var productTitle: String
    var quantity: Int
    var snapshotPageCount: Int
    var isLandscape: Bool
    var addedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, bookVersionId, displayTitle, coverURL
        case coverPDFURL, coverThumbnailCacheRevision, fallbackImageURL, fallbackRenderedURL
        case productOptionId, productTitle, quantity, snapshotPageCount, isLandscape, addedAt
    }

    init(
        id: UUID = UUID(),
        bookVersionId: String,
        displayTitle: String,
        coverURL: String? = nil,
        coverPDFURL: String? = nil,
        coverThumbnailCacheRevision: String? = nil,
        fallbackImageURL: String? = nil,
        fallbackRenderedURL: String? = nil,
        productOptionId: String,
        productTitle: String,
        quantity: Int = 1,
        snapshotPageCount: Int,
        isLandscape: Bool,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.bookVersionId = bookVersionId
        self.displayTitle = displayTitle
        self.coverURL = coverURL
        self.coverPDFURL = coverPDFURL
        self.coverThumbnailCacheRevision = coverThumbnailCacheRevision
        self.fallbackImageURL = fallbackImageURL
        self.fallbackRenderedURL = fallbackRenderedURL
        self.productOptionId = productOptionId
        self.productTitle = productTitle
        self.quantity = max(1, quantity)
        self.snapshotPageCount = snapshotPageCount
        self.isLandscape = isLandscape
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bookVersionId = try c.decode(String.self, forKey: .bookVersionId)
        displayTitle = try c.decode(String.self, forKey: .displayTitle)
        coverURL = try c.decodeIfPresent(String.self, forKey: .coverURL)
        coverPDFURL = try c.decodeIfPresent(String.self, forKey: .coverPDFURL)
        coverThumbnailCacheRevision = try c.decodeIfPresent(String.self, forKey: .coverThumbnailCacheRevision)
        fallbackImageURL = try c.decodeIfPresent(String.self, forKey: .fallbackImageURL)
        fallbackRenderedURL = try c.decodeIfPresent(String.self, forKey: .fallbackRenderedURL)
        productOptionId = try c.decode(String.self, forKey: .productOptionId)
        productTitle = try c.decode(String.self, forKey: .productTitle)
        quantity = max(1, try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1)
        snapshotPageCount = try c.decode(Int.self, forKey: .snapshotPageCount)
        isLandscape = try c.decode(Bool.self, forKey: .isLandscape)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

@MainActor
final class OrderCartStore: ObservableObject {
    static let shared = OrderCartStore()

    @Published private(set) var items: [OrderCartItem] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var authObserver: AuthStateDidChangeListenerHandle?

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        authObserver = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.reloadFromDisk(userId: user?.uid)
            }
        }
        reloadFromDisk(userId: Auth.auth().currentUser?.uid)
    }

    deinit {
        if let authObserver {
            Auth.auth().removeStateDidChangeListener(authObserver)
        }
    }

    private func storageKey(for userId: String?) -> String {
        let uid = userId ?? "_guest"
        return "memoir_print_cart_v1_\(uid)"
    }

    func reloadFromDisk(userId: String?) {
        let key = storageKey(for: userId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? decoder.decode([OrderCartItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func persist() {
        let key = storageKey(for: Auth.auth().currentUser?.uid)
        guard let data = try? encoder.encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    var totalLineCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    /// Merge key: same book + same print format.
    func addOrIncrement(
        bookVersionId: String,
        displayTitle: String,
        coverURL: String?,
        coverPDFURL: String? = nil,
        coverThumbnailCacheRevision: String? = nil,
        fallbackImageURL: String? = nil,
        fallbackRenderedURL: String? = nil,
        productOptionId: String,
        productTitle: String,
        quantity: Int,
        snapshotPageCount: Int,
        isLandscape: Bool
    ) {
        let addQty = max(1, quantity)
        if let idx = items.firstIndex(where: { $0.bookVersionId == bookVersionId && $0.productOptionId == productOptionId }) {
            var next = items
            var row = next[idx]
            row.quantity = min(99, row.quantity + addQty)
            if let incoming = coverURL?.trimmingCharacters(in: .whitespacesAndNewlines), !incoming.isEmpty {
                row.coverURL = incoming
            }
            if let incoming = coverPDFURL?.trimmingCharacters(in: .whitespacesAndNewlines), !incoming.isEmpty {
                row.coverPDFURL = incoming
            }
            if let incoming = coverThumbnailCacheRevision?.trimmingCharacters(in: .whitespacesAndNewlines), !incoming.isEmpty {
                row.coverThumbnailCacheRevision = incoming
            }
            if let incoming = fallbackImageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !incoming.isEmpty {
                row.fallbackImageURL = incoming
            }
            if let incoming = fallbackRenderedURL?.trimmingCharacters(in: .whitespacesAndNewlines), !incoming.isEmpty {
                row.fallbackRenderedURL = incoming
            }
            next[idx] = row
            items = next
        } else {
            var next = items
            next.append(OrderCartItem(
                bookVersionId: bookVersionId,
                displayTitle: displayTitle,
                coverURL: coverURL,
                coverPDFURL: coverPDFURL,
                coverThumbnailCacheRevision: coverThumbnailCacheRevision,
                fallbackImageURL: fallbackImageURL,
                fallbackRenderedURL: fallbackRenderedURL,
                productOptionId: productOptionId,
                productTitle: productTitle,
                quantity: min(99, addQty),
                snapshotPageCount: snapshotPageCount,
                isLandscape: isLandscape
            ))
            items = next
        }
        persist()
    }

    func updateQuantity(itemId: UUID, quantity: Int) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        var next = items
        if quantity <= 0 {
            next.remove(at: idx)
        } else {
            var row = next[idx]
            row.quantity = min(99, quantity)
            next[idx] = row
        }
        items = next
        persist()
    }

    func remove(itemId: UUID) {
        items = items.filter { $0.id != itemId }
        persist()
    }

    func clear() {
        items.removeAll(keepingCapacity: false)
        persist()
    }
}
