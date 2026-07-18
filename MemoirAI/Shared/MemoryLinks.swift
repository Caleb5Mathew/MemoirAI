import Foundation

/// Canonical memory deep link formats:
/// - `https://memoirai-7db06.web.app/memory/{uuid}` — universal link printed in new books;
///   opens the app when installed, otherwise a hosted page that routes to the App Store.
/// - `memoirai://memory/{uuid}` — legacy custom scheme printed in already-shipped books.
enum MemoryLinks {
    static let universalLinkHost = "memoirai-7db06.web.app"
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/memoir-record-your-life-story/id6746061021")!

    static func universalLink(memoryID: UUID) -> URL {
        URL(string: "https://\(universalLinkHost)/memory/\(memoryID.uuidString)")!
    }

    /// True when the URL is shaped like a memory link (either scheme), even if the ID is invalid.
    /// Used to decide whether a parse failure deserves a user-facing error.
    static func looksLikeMemoryLink(_ url: URL) -> Bool {
        if url.scheme == "memoirai", url.host == "memory" { return true }
        if url.scheme == "https", url.host == universalLinkHost, url.path.hasPrefix("/memory/") { return true }
        return false
    }

    static func parseMemoryDeepLink(_ url: URL) -> UUID? {
        guard looksLikeMemoryLink(url) else { return nil }
        let segments = url.path.split(separator: "/").map(String.init)
        guard let idSegment = segments.last else { return nil }
        return UUID(uuidString: idSegment)
    }
}
