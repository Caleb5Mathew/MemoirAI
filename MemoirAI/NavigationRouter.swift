//
//  NavigationRouter.swift
//  MemoirAI
//
//  Created by user941803 on 5/31/25.
//


import SwiftUIimport Combine/// A very small, shared router  — holds the ID of a memory the app/// should present.  Views can observe `selectedMemoryID` to push a/// `MemoryDetailView`.final class NavigationRouter: ObservableObject {    static let shared = NavigationRouter()    /// `nil`  ➜  no detail showing      /// non-nil ➜  push / present that MemoryDetailView    @Published var selectedMemoryID: UUID?    /// Call from deep-link handler.    func showMemoryDetail(id: UUID) {        selectedMemoryID = id    }    /// Call when detail is dismissed so future deep links re-trigger.    func clear() { selectedMemoryID = nil }}