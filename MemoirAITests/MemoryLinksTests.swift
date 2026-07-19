//
//  MemoryLinksTests.swift
//  MemoirAITests
//

import Foundation
import Testing
@testable import MemoirAI

struct MemoryLinksTests {
    private let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test func parsesLegacyCustomScheme() {
        let url = URL(string: "memoirai://memory/\(id.uuidString)")!
        #expect(MemoryLinks.parseMemoryDeepLink(url) == id)
    }

    @Test func parsesUniversalLink() {
        let url = URL(string: "https://\(MemoryLinks.universalLinkHost)/memory/\(id.uuidString)")!
        #expect(MemoryLinks.parseMemoryDeepLink(url) == id)
    }

    @Test func universalLinkRoundTrips() {
        let built = MemoryLinks.universalLink(memoryID: id)
        #expect(MemoryLinks.parseMemoryDeepLink(built) == id)
    }

    @Test func lowercasedUUIDStillParses() {
        let url = URL(string: "memoirai://memory/\(id.uuidString.lowercased())")!
        #expect(MemoryLinks.parseMemoryDeepLink(url) == id)
    }

    @Test func rejectsForeignHosts() {
        let url = URL(string: "https://evil.example.com/memory/\(id.uuidString)")!
        #expect(MemoryLinks.looksLikeMemoryLink(url) == false)
        #expect(MemoryLinks.parseMemoryDeepLink(url) == nil)
    }

    @Test func rejectsNonMemoryPaths() {
        let url = URL(string: "https://\(MemoryLinks.universalLinkHost)/ops")!
        #expect(MemoryLinks.looksLikeMemoryLink(url) == false)
    }

    @Test func memoryShapedLinkWithBadUUIDLooksLikeMemoryLinkButFailsParse() {
        let url = URL(string: "memoirai://memory/not-a-uuid")!
        #expect(MemoryLinks.looksLikeMemoryLink(url) == true)
        #expect(MemoryLinks.parseMemoryDeepLink(url) == nil)
    }

    @Test func otherCustomSchemeHostsAreIgnored() {
        let url = URL(string: "memoirai://order-complete?session_id=abc")!
        #expect(MemoryLinks.looksLikeMemoryLink(url) == false)
        #expect(MemoryLinks.parseMemoryDeepLink(url) == nil)
    }
}
