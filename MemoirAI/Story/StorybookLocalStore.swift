//
//  StorybookLocalStore.swift
//  MemoirAI
//
//  File-backed cache for PersistableStorybook payloads (replaces large UserDefaults blobs).
//

import Foundation

/// Persists encoded storybook `Data` under Application Support to avoid CFPreferences size limits.
enum StorybookLocalStore {
    private static let rootFolderName = "StorybookCache"
    private static let currentFileName = "current.book"
    private static let historyFolderName = "history"
    private static let bookExtension = "book"

    /// Per-profile flag: legacy UserDefaults → disk migration completed.
    private static func migrationFlagKey(profileID: UUID) -> String {
        "storybook_localstore_v1_migrated_\(profileID.uuidString)"
    }

    private static func applicationSupportBase() throws -> URL {
        let url = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = url.appendingPathComponent(rootFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    private static func profileDirectory(profileID: UUID) throws -> URL {
        let base = try applicationSupportBase()
        let dir = base.appendingPathComponent(profileID.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func currentBookURL(profileID: UUID) throws -> URL {
        try profileDirectory(profileID: profileID).appendingPathComponent(currentFileName)
    }

    private static func historyDirectory(profileID: UUID) throws -> URL {
        let dir = try profileDirectory(profileID: profileID).appendingPathComponent(historyFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Legacy keys (must match StoryPageViewModel history)

    private static func legacyCurrentKey(profileID: UUID) -> String {
        "storybook_\(profileID.uuidString)"
    }

    private static func legacyHistoryKey(profileID: UUID) -> String {
        "storybook_history_\(profileID.uuidString)"
    }

    /// One-shot migration from UserDefaults → disk for this profile.
    static func migrateLegacyUserDefaultsIfNeeded(profileID: UUID) {
        let defaults = UserDefaults.standard
        let flagKey = migrationFlagKey(profileID: profileID)
        let currentKey = legacyCurrentKey(profileID: profileID)
        let historyKey = legacyHistoryKey(profileID: profileID)
        let udCurrent = defaults.data(forKey: currentKey)
        let udHistory = defaults.array(forKey: historyKey) as? [Data] ?? []
        let hasLegacyUD = udCurrent != nil || !udHistory.isEmpty

        // No legacy keys — nothing to migrate (avoid re-scanning disk every time).
        if !hasLegacyUD {
            if !defaults.bool(forKey: flagKey) {
                defaults.set(true, forKey: flagKey)
            }
            return
        }

        // UserDefaults still has payloads (e.g. user ran an older build) — migrate even if flag was set earlier.
        do {
            if let data = udCurrent {
                try atomicWrite(data: data, to: try currentBookURL(profileID: profileID))
            }
            let historyDir = try historyDirectory(profileID: profileID)
            let decoder = JSONDecoder()
            for (index, data) in udHistory.enumerated() {
                let stamp: Int64
                if let book = try? decoder.decode(PersistableStorybook.self, from: data) {
                    stamp = Int64(book.createdAt.timeIntervalSince1970 * 1000)
                } else {
                    stamp = Int64(Date().timeIntervalSince1970 * 1000) + Int64(index)
                }
                // Deterministic name so re-running a partial migration overwrites the same files.
                let fileName = String(format: "%016lld_%04d.\(bookExtension)", stamp, index)
                let fileURL = historyDir.appendingPathComponent(fileName)
                try atomicWrite(data: data, to: fileURL)
            }

            defaults.removeObject(forKey: currentKey)
            defaults.removeObject(forKey: historyKey)
            defaults.set(true, forKey: flagKey)
            print("✅ StorybookLocalStore: migrated legacy UserDefaults for profile \(profileID.uuidString)")
        } catch {
            print("❌ StorybookLocalStore: migration failed for \(profileID): \(error.localizedDescription)")
        }
    }

    // MARK: - Public API

    static func writeCurrentBook(data: Data, profileID: UUID) throws {
        migrateLegacyUserDefaultsIfNeeded(profileID: profileID)
        try atomicWrite(data: data, to: try currentBookURL(profileID: profileID))
    }

    /// Appends one full encoded book to history (one file per save — no giant plist arrays).
    static func appendHistory(data: Data, profileID: UUID) throws {
        migrateLegacyUserDefaultsIfNeeded(profileID: profileID)
        let decoder = JSONDecoder()
        let stamp: Int64
        if let book = try? decoder.decode(PersistableStorybook.self, from: data) {
            stamp = Int64(book.createdAt.timeIntervalSince1970 * 1000)
        } else {
            stamp = Int64(Date().timeIntervalSince1970 * 1000)
        }
        let historyDir = try historyDirectory(profileID: profileID)
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let name = String(format: "%016lld_%@.\(bookExtension)", stamp, suffix)
        let fileURL = historyDir.appendingPathComponent(name)
        try atomicWrite(data: data, to: fileURL)
    }

    static func readCurrentBookData(profileID: UUID) -> Data? {
        migrateLegacyUserDefaultsIfNeeded(profileID: profileID)
        let url = try? currentBookURL(profileID: profileID)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// All history payloads in chronological order (sorted by encoded filename).
    static func readHistoryDataArray(profileID: UUID) -> [Data] {
        migrateLegacyUserDefaultsIfNeeded(profileID: profileID)
        guard let historyDir = try? historyDirectory(profileID: profileID),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: historyDir,
                includingPropertiesForKeys: nil
              ) else {
            return []
        }
        let files = urls
            .filter { $0.pathExtension == bookExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.compactMap { try? Data(contentsOf: $0) }
    }

    static func removeCurrentBook(profileID: UUID) {
        migrateLegacyUserDefaultsIfNeeded(profileID: profileID)
        guard let url = try? currentBookURL(profileID: profileID),
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Atomic IO

    private static func atomicWrite(data: Data, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.moveItem(at: tmp, to: url)
    }
}
