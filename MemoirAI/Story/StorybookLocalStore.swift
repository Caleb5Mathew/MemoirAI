//
//  StorybookLocalStore.swift
//  MemoirAI
//
//  File-backed cache for PersistableStorybook payloads (replaces large UserDefaults blobs).
//

import Foundation

enum StorybookStorageScope {
    static func relativeDirectory(userID: String, profileID: UUID) -> String {
        "users/\(userID)/\(profileID.uuidString)"
    }

    static func migrationFlagKey(userID: String, profileID: UUID) -> String {
        "storybook_localstore_v2_migrated_\(userID)_\(profileID.uuidString)"
    }

    static func cloudCurrentKey(userID: String, profileID: UUID) -> String {
        "memoir_storybook_\(userID)_\(profileID.uuidString)"
    }

    static func cloudHistoryKey(userID: String, profileID: UUID) -> String {
        "memoir_storybook_history_\(userID)_\(profileID.uuidString)"
    }
}

enum StorybookHistoryRetentionPolicy {
    static let maximumRevisionCount = 8
    static let maximumTotalByteCount = 120 * 1024 * 1024

    /// Input sizes must be oldest first. Always retains the newest revision.
    static func removalCount(forOldestFirstByteCounts byteCounts: [Int]) -> Int {
        guard byteCounts.count > 1 else { return 0 }
        var remainingCount = byteCounts.count
        var remainingBytes = byteCounts.reduce(0, +)
        var removalCount = 0
        while remainingCount > 1,
              (remainingCount > maximumRevisionCount || remainingBytes > maximumTotalByteCount) {
            remainingBytes -= max(0, byteCounts[removalCount])
            remainingCount -= 1
            removalCount += 1
        }
        return removalCount
    }
}

enum StorybookLocalFilePolicy {
    static func accepts(byteCount: Int) -> Bool {
        StorybookPayloadCapacityPolicy.accepts(encodedByteCount: byteCount)
    }
}

/// Persists encoded storybook `Data` under Application Support to avoid CFPreferences size limits.
enum StorybookLocalStore {
    private static let rootFolderName = "StorybookCache"
    private static let currentFileName = "current.book"
    private static let pendingFileName = "pending.book"
    private static let historyFolderName = "history"
    private static let bookExtension = "book"

    /// Per-profile flag: legacy UserDefaults → disk migration completed.
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
        guard let userID = MemoryUserScope.currentFirebaseUserId else {
            throw CocoaError(.userCancelled)
        }
        let base = try applicationSupportBase()
        let dir = base.appendingPathComponent(
            StorybookStorageScope.relativeDirectory(userID: userID, profileID: profileID),
            isDirectory: true
        )
        let legacyDirectory = base.appendingPathComponent(profileID.uuidString, isDirectory: true)
        let trustedLegacyOwner = UserDefaults.standard.bool(
            forKey: "firebase_migration_complete_\(userID)"
        )
        if !FileManager.default.fileExists(atPath: dir.path),
           trustedLegacyOwner,
           FileManager.default.fileExists(atPath: legacyDirectory.path) {
            try FileManager.default.createDirectory(
                at: dir.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: legacyDirectory, to: dir)
        }
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

    private static func pendingBookURL(profileID: UUID) throws -> URL {
        try profileDirectory(profileID: profileID).appendingPathComponent(pendingFileName)
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
        guard let userID = MemoryUserScope.currentFirebaseUserId else { return }
        let defaults = UserDefaults.standard
        let flagKey = StorybookStorageScope.migrationFlagKey(
            userID: userID,
            profileID: profileID
        )
        let currentKey = legacyCurrentKey(profileID: profileID)
        let historyKey = legacyHistoryKey(profileID: profileID)
        let udCurrent = defaults.data(forKey: currentKey)
        let udHistory = defaults.array(forKey: historyKey) as? [Data] ?? []
        let hasLegacyUD = udCurrent != nil || !udHistory.isEmpty
        let trustedLegacyOwner = defaults.bool(forKey: "firebase_migration_complete_\(userID)")

        guard !hasLegacyUD || trustedLegacyOwner else { return }

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
            try pruneHistory(profileID: profileID)
            print("✅ StorybookLocalStore: migrated legacy UserDefaults for profile \(profileID.uuidString.prefix(8))…")
        } catch {
            print("❌ StorybookLocalStore: migration failed for \(profileID): \(error.localizedDescription)")
        }
    }

    // MARK: - Public API

    static func writeCurrentBook(data: Data, profileID: UUID) throws {
        migrateLegacyUserDefaultsIfNeeded(profileID: profileID)
        try atomicWrite(data: data, to: try currentBookURL(profileID: profileID))
    }

    static func writePendingBook(data: Data, profileID: UUID) throws {
        guard StorybookLocalFilePolicy.accepts(byteCount: data.count) else {
            throw BookPageEditorPersistenceError.bookTooLarge
        }
        migrateLegacyUserDefaultsIfNeeded(profileID: profileID)
        try atomicWrite(data: data, to: try pendingBookURL(profileID: profileID))
    }

    static func readPendingBookData(profileID: UUID) -> Data? {
        migrateLegacyUserDefaultsIfNeeded(profileID: profileID)
        guard let url = try? pendingBookURL(profileID: profileID) else { return nil }
        return readBoundedBookData(at: url)
    }

    static func removePendingBook(profileID: UUID) {
        guard let url = try? pendingBookURL(profileID: profileID),
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func promotePendingBook(bookVersionID: String, profileID: UUID) throws {
        guard let data = readPendingBookData(profileID: profileID),
              let book = try? JSONDecoder().decode(PersistableStorybook.self, from: data),
              book.bookVersionID == bookVersionID else { return }
        try writeCurrentBook(data: data, profileID: profileID)
        try appendHistory(data: data, profileID: profileID)
        removePendingBook(profileID: profileID)
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
        try pruneHistory(profileID: profileID)
    }

    static func readCurrentBookData(profileID: UUID) -> Data? {
        migrateLegacyUserDefaultsIfNeeded(profileID: profileID)
        let url = try? currentBookURL(profileID: profileID)
        guard let url else { return nil }
        return readBoundedBookData(at: url)
    }

    /// Removes exactly one canonical revision; timestamp fallback is only for legacy books without an ID.
    static func removeHistoryFile(
        bookVersionID: String,
        fallbackCreatedAt: Date,
        profileID: UUID
    ) {
        migrateLegacyUserDefaultsIfNeeded(profileID: profileID)
        guard let historyDir = try? historyDirectory(profileID: profileID),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: historyDir,
                includingPropertiesForKeys: nil
              ) else { return }
        let decoder = JSONDecoder()
        for url in urls where url.pathExtension == bookExtension {
            guard let d = readBoundedBookData(at: url),
                  let b = try? decoder.decode(PersistableStorybook.self, from: d) else { continue }
            let matchesCanonicalID = b.bookVersionID == bookVersionID
            let matchesLegacyTimestamp = b.bookVersionID == nil
                && abs(b.createdAt.timeIntervalSince(fallbackCreatedAt)) < 0.001
            if b.profileID == profileID, matchesCanonicalID || matchesLegacyTimestamp {
                try? FileManager.default.removeItem(at: url)
                break
            }
        }
    }

    static func removeCloudCache(
        bookVersionID: String,
        fallbackCreatedAt: Date,
        profileID: UUID
    ) {
        guard let userID = MemoryUserScope.currentFirebaseUserId else { return }
        let store = NSUbiquitousKeyValueStore.default
        let currentKey = StorybookStorageScope.cloudCurrentKey(userID: userID, profileID: profileID)
        if let data = store.data(forKey: currentKey),
           let book = try? JSONDecoder().decode(PersistableStorybook.self, from: data) {
            let matchesCanonicalID = book.bookVersionID == bookVersionID
            let matchesLegacyTimestamp = book.bookVersionID == nil
                && abs(book.createdAt.timeIntervalSince(fallbackCreatedAt)) < 0.001
            if matchesCanonicalID || matchesLegacyTimestamp {
                store.removeObject(forKey: currentKey)
            }
        }

        let historyKey = StorybookStorageScope.cloudHistoryKey(userID: userID, profileID: profileID) + "_metadata"
        let metadata = store.array(forKey: historyKey) as? [[String: Any]] ?? []
        let filtered = metadata.filter { entry in
            if let storedID = entry["bookVersionID"] as? String {
                return storedID != bookVersionID
            }
            guard let timestamp = entry["createdAt"] as? Double else { return true }
            return abs(timestamp - fallbackCreatedAt.timeIntervalSince1970) >= 0.001
        }
        store.set(filtered, forKey: historyKey)
        store.synchronize()
    }

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
            .suffix(StorybookHistoryRetentionPolicy.maximumRevisionCount)
        return files.compactMap(readBoundedBookData)
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

    private static func readBoundedBookData(at url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              StorybookLocalFilePolicy.accepts(byteCount: fileSize) else {
            return nil
        }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    private static func pruneHistory(profileID: UUID) throws {
        let historyDir = try historyDirectory(profileID: profileID)
        let urls = try FileManager.default.contentsOfDirectory(
            at: historyDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == bookExtension }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let sizes = urls.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return max(0, values?.fileSize ?? 0)
        }
        let count = StorybookHistoryRetentionPolicy.removalCount(
            forOldestFirstByteCounts: sizes
        )
        for url in urls.prefix(count) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
