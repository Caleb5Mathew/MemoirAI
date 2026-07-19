//
//  NavigationRouter.swift
//  MemoirAI
//
//  Created by user941803 on 5/31/25.
//


import SwiftUI
import Combine

/// A memory that is not in the local store: someone else's shared memory (or an
/// own memory not yet hydrated). Resolved remotely via SharedAccessService.
struct SharedMemoryRoute: Hashable {
    let ownerId: String
    let memoryId: UUID
}

/// A very small, shared router  — holds the ID of a memory the app
/// should present.  Views can observe `selectedMemoryID` to push a
/// `MemoryDetailView`.
final class NavigationRouter: ObservableObject {
    static let shared = NavigationRouter()

    /// `nil`  ➜  no detail showing
    /// non-nil ➜  push / present that MemoryDetailView
    @Published var selectedMemoryID: UUID?

    /// Set when a scanned memory belongs to another account (or is not local);
    /// pushes the shared memory flow instead of MemoryDetailView.
    @Published var sharedMemoryRoute: SharedMemoryRoute?

    /// Call from deep-link handler (e.g., QR code scan).
    func showMemoryDetail(id: UUID) {
        print("🔗 NavigationRouter: Showing memory detail for \(id.uuidString)")
        selectedMemoryID = id
    }

    func showSharedMemory(ownerId: String, memoryId: UUID) {
        print("🔗 NavigationRouter: Showing shared memory \(memoryId.uuidString) owner=\(ownerId.prefix(8))…")
        sharedMemoryRoute = SharedMemoryRoute(ownerId: ownerId, memoryId: memoryId)
    }

    /// Call when detail is dismissed so future deep links re-trigger.
    func clear() {
        print("🔗 NavigationRouter: Clearing selected memory")
        selectedMemoryID = nil
        sharedMemoryRoute = nil
    }
}
