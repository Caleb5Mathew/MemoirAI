//
//  StorybookActiveJobPickerTests.swift
//  MemoirAITests
//

import FirebaseFirestore
import Foundation
import Testing
@testable import MemoirAI

struct StorybookActiveJobPickerTests {

    @Test func pickActive_returnsNewestInFlight() {
        let profileId = UUID()
        let ref = Date()
        let t1 = Timestamp(date: ref.addingTimeInterval(-50))
        let t2 = Timestamp(date: ref.addingTimeInterval(-150))
        let rows: [(String, [String: Any])] = [
            ("runningJob", ["createdAt": t1, "profileId": profileId.uuidString, "status": "running", "progress": ["completedMemoryCount": 2, "totalMemories": 5, "currentStatus": ""]]),
            ("failedOld", ["createdAt": t2, "profileId": profileId.uuidString, "status": "failed", "progress": [:]])
        ]
        let j = FirestoreSyncService.pickActiveStorybookCloudJob(profileId: profileId, rowsNewestFirst: rows, referenceNow: ref)
        #expect(j?.jobId == "runningJob")
        #expect(j?.status == "running")
    }

    @Test func pickActive_skipsFailedWhenNewerComplete() {
        let profileId = UUID()
        let ref = Date()
        let t1 = Timestamp(date: ref.addingTimeInterval(-50))
        let t2 = Timestamp(date: ref.addingTimeInterval(-150))
        let rows: [(String, [String: Any])] = [
            ("done", ["createdAt": t1, "profileId": profileId.uuidString, "status": "complete", "progress": [:]]),
            ("failedOld", ["createdAt": t2, "profileId": profileId.uuidString, "status": "failed", "progress": [:]])
        ]
        let j = FirestoreSyncService.pickActiveStorybookCloudJob(profileId: profileId, rowsNewestFirst: rows, referenceNow: ref)
        #expect(j == nil)
    }

    @Test func pickActive_returnsFailedWhenItIsNewest() {
        let profileId = UUID()
        let ref = Date()
        let t1 = Timestamp(date: ref.addingTimeInterval(-50))
        let rows: [(String, [String: Any])] = [
            ("failedNew", ["createdAt": t1, "profileId": profileId.uuidString, "status": "failed", "progress": ["currentStatus": "oops"]])
        ]
        let j = FirestoreSyncService.pickActiveStorybookCloudJob(profileId: profileId, rowsNewestFirst: rows, referenceNow: ref)
        #expect(j?.jobId == "failedNew")
        #expect(j?.status == "failed")
    }

    @Test func pickActive_ignoresDismissedFailed() {
        let profileId = UUID()
        let ref = Date()
        let t1 = Timestamp(date: ref.addingTimeInterval(-50))
        let t2 = Timestamp(date: ref.addingTimeInterval(-100))
        let rows: [(String, [String: Any])] = [
            ("dismissed", ["createdAt": t1, "profileId": profileId.uuidString, "status": "dismissedFailed", "progress": [:]]),
            ("running", ["createdAt": t2, "profileId": profileId.uuidString, "status": "running", "progress": [:]])
        ]
        let j = FirestoreSyncService.pickActiveStorybookCloudJob(profileId: profileId, rowsNewestFirst: rows, referenceNow: ref)
        #expect(j?.jobId == "running")
    }

    // MARK: - pickLatestCompletedStorybookCloudJob

    @Test func pickCompleted_returnsNewestComplete() {
        let profileId = UUID()
        let ref = Date()
        let rows: [(String, [String: Any])] = [
            ("failedNew", ["createdAt": Timestamp(date: ref.addingTimeInterval(-30)), "profileId": profileId.uuidString, "status": "failed", "progress": [:]]),
            ("doneNew", ["createdAt": Timestamp(date: ref.addingTimeInterval(-60)), "profileId": profileId.uuidString, "status": "complete", "progress": [:]]),
            ("doneOld", ["createdAt": Timestamp(date: ref.addingTimeInterval(-600)), "profileId": profileId.uuidString, "status": "complete", "progress": [:]])
        ]
        let j = FirestoreSyncService.pickLatestCompletedStorybookCloudJob(profileId: profileId, rowsNewestFirst: rows, referenceNow: ref)
        #expect(j?.jobId == "doneNew")
        #expect(j?.status == "complete")
    }

    @Test func pickCompleted_ignoresOtherProfilesAndStaleJobs() {
        let profileId = UUID()
        let ref = Date()
        let stale = Timestamp(date: ref.addingTimeInterval(-8 * 24 * 60 * 60))
        let rows: [(String, [String: Any])] = [
            ("otherProfile", ["createdAt": Timestamp(date: ref.addingTimeInterval(-30)), "profileId": UUID().uuidString, "status": "complete", "progress": [:]]),
            ("staleComplete", ["createdAt": stale, "profileId": profileId.uuidString, "status": "complete", "progress": [:]])
        ]
        let j = FirestoreSyncService.pickLatestCompletedStorybookCloudJob(profileId: profileId, rowsNewestFirst: rows, referenceNow: ref)
        #expect(j == nil)
    }

    @Test func pickCompleted_returnsNilWhenNoCompleteJobs() {
        let profileId = UUID()
        let ref = Date()
        let rows: [(String, [String: Any])] = [
            ("running", ["createdAt": Timestamp(date: ref.addingTimeInterval(-30)), "profileId": profileId.uuidString, "status": "running", "progress": [:]])
        ]
        let j = FirestoreSyncService.pickLatestCompletedStorybookCloudJob(profileId: profileId, rowsNewestFirst: rows, referenceNow: ref)
        #expect(j == nil)
    }
}
