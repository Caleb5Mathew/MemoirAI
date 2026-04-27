//
//  GenerationProgressMarkerTests.swift
//  MemoirAITests
//

import Foundation
import Testing
@testable import MemoirAI

struct GenerationProgressMarkerTests {
    @Test func roundTrip_encodeDecode() throws {
        var m = GenerationProgressMarker(
            profileID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            bookVersionId: "profile_1700000000",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            artStyle: "kids",
            pageCountTarget: 12,
            profileName: "Ruth",
            profileEthnicity: "Any",
            completedMemoryIDs: [UUID(), UUID()],
            skippedMemoryIDs: [UUID()],
            orderedMemoryIDs: (0..<3).map { _ in UUID() },
            startedAt: Date(timeIntervalSince1970: 1_799_999_000),
            lastHeartbeatAt: Date(),
            phase: .generating
        )
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(GenerationProgressMarker.self, from: data)
        #expect(decoded == m)

        m.phase = .uploading
        m.completedMemoryIDs.append(UUID())
        #expect(try JSONDecoder().decode(GenerationProgressMarker.self, from: try JSONEncoder().encode(m)) == m)
    }

    @Test func memoryIDsStillToGenerate_filtersCompletedAndSkipped() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()
        var m = GenerationProgressMarker(
            profileID: UUID(),
            bookVersionId: "x",
            createdAt: Date(),
            artStyle: "kids",
            pageCountTarget: 2,
            profileName: "P",
            profileEthnicity: nil,
            completedMemoryIDs: [a, b],
            skippedMemoryIDs: [c],
            orderedMemoryIDs: [a, b, c, d],
            startedAt: Date(),
            lastHeartbeatAt: Date(),
            phase: .selecting
        )
        #expect(m.memoryIDsStillToGenerate() == [d])
        m.skippedMemoryIDs = []
        #expect(Set(m.memoryIDsStillToGenerate()) == [c, d])
    }
}
