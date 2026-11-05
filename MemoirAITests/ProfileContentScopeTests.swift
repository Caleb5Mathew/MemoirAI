import CoreData
import Foundation
import Testing
@testable import MemoirAI

struct ProfileContentScopeTests {
    @Test func callbackRequiresSameAccountProfileAndRequest() {
        let profile = UUID()
        let request = ProfileContentScope(userID: "a", profileID: profile)
        #expect(request.isCurrent(userID: "a", profileID: profile, requestID: request.requestID))
        #expect(!request.isCurrent(userID: "b", profileID: profile, requestID: request.requestID))
        #expect(!request.isCurrent(userID: "a", profileID: UUID(), requestID: request.requestID))
        #expect(!request.isCurrent(userID: "a", profileID: profile, requestID: UUID()))
        #expect(!request.isCurrent(userID: nil, profileID: profile, requestID: nil))
    }

    @Test func returningToSameProfileDoesNotReviveOldCallback() {
        let profile = UUID()
        let first = ProfileContentScope(userID: "a", profileID: profile)
        let latest = ProfileContentScope(userID: "a", profileID: profile)
        #expect(!first.isCurrent(userID: latest.userID, profileID: latest.profileID, requestID: latest.requestID))
    }
}

@MainActor
struct MemoryEntryFetchRequestTests {
    @Test func resolvesEachActiveContextWithMultipleLoadedModels() throws {
        let first = PersistenceController(inMemory: true)
        let second = PersistenceController(inMemory: true)
        let firstID = UUID(), secondID = UUID()
        for (context, id) in [(first.container.viewContext, firstID), (second.container.viewContext, secondID)] {
            let entry = try #require(NSEntityDescription.insertNewObject(forEntityName: "MemoryEntry", into: context) as? MemoryEntry)
            entry.id = id
            try context.save()
        }
        #expect(try first.container.viewContext.fetch(MemoryEntryFetchRequest.make()).compactMap(\.id) == [firstID])
        #expect(try second.container.viewContext.fetch(MemoryEntryFetchRequest.make()).compactMap(\.id) == [secondID])
    }
}
