//
//  GenerationProgressMarker.swift
//  MemoirAI
//
//  Persists in-flight storybook generation so the app can resume after termination.
//

import Foundation

struct GenerationProgressMarker: Codable, Equatable {
    var profileID: UUID
    var bookVersionId: String
    var createdAt: Date
    var artStyle: String
    var pageCountTarget: Int
    var profileName: String
    var profileEthnicity: String?
    var completedMemoryIDs: [UUID]
    var skippedMemoryIDs: [UUID]
    var orderedMemoryIDs: [UUID]
    let startedAt: Date
    var lastHeartbeatAt: Date
    var phase: Phase

    enum Phase: String, Codable {
        case selecting
        case generating
        case finalizing
        case uploading
    }

    private static func storageKey(profileID: UUID) -> String {
        "memoirai.generationInProgress.\(profileID.uuidString)"
    }

    static func load(for profileID: UUID) -> GenerationProgressMarker? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(profileID: profileID)) else { return nil }
        return try? JSONDecoder().decode(GenerationProgressMarker.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey(profileID: profileID))
        }
    }

    static func clear(for profileID: UUID) {
        UserDefaults.standard.removeObject(forKey: storageKey(profileID: profileID))
        NotificationCenter.default.post(
            name: .generationProgressMarkerChanged,
            object: nil,
            userInfo: ["profileId": profileID.uuidString]
        )
    }

    /// Drops abandoned markers (e.g. uninstalled app, never finished) so the “Resuming” banner can’t last forever.
    static func clearStaleOnLaunchIfNeeded(olderThan: TimeInterval = 14 * 24 * 60 * 60) {
        let prefix = "memoirai.generationInProgress."
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            guard key.hasPrefix(prefix) else { continue }
            let suffix = String(key.dropFirst(prefix.count))
            guard let pid = UUID(uuidString: suffix),
                  let data = UserDefaults.standard.data(forKey: key),
                  let m = try? JSONDecoder().decode(GenerationProgressMarker.self, from: data) else { continue }
            if Date().timeIntervalSince(m.lastHeartbeatAt) > olderThan {
                clear(for: pid)
            }
        }
    }

    /// `true` when a marker exists and has not been abandoned.
    var isActive: Bool {
        lastHeartbeatAt.timeIntervalSince1970 > 0
    }
}

extension GenerationProgressMarker {
    /// Merges duplicate IDs; keeps `completed` as source of truth for "done" memories.
    func memoryIDsStillToGenerate() -> [UUID] {
        let done = Set(completedMemoryIDs).union(skippedMemoryIDs)
        return orderedMemoryIDs.filter { !done.contains($0) }
    }
}
