import Foundation

struct BookLibraryEntry {
    let record: BookVersionRecord
    let local: PersistableStorybook?
}

enum BookLibraryMergePolicy {
    static func merged(cloud: [BookVersionRecord], local: [PersistableStorybook],
                       profileID: UUID, userID: String, trustedLegacyOwner: Bool) -> [BookLibraryEntry] {
        var entries: [String: BookLibraryEntry] = [:]
        for record in cloud where UUID(uuidString: record.profileId) == profileID {
            entries[record.bookVersionId] = BookLibraryEntry(record: record, local: nil)
        }
        for book in local {
            guard book.profileID == profileID,
                  StorybookOwnershipPolicy.canRead(ownerUserID: book.ownerUserID, currentUserID: userID,
                                                  trustedLegacyOwner: trustedLegacyOwner) else { continue }
            let explicitID = book.bookVersionID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedID = explicitID?.isEmpty == false ? explicitID : nil
            let legacyMatches = storedID == nil ? cloud.filter {
                UUID(uuidString: $0.profileId) == profileID && abs($0.createdAt.timeIntervalSince(book.createdAt)) < 0.001
            } : []
            let matchingID = storedID ?? (legacyMatches.count == 1 ? legacyMatches.first?.bookVersionId : nil)
            let id = matchingID ?? "\(profileID.uuidString)_\(Int64((book.createdAt.timeIntervalSince1970 * 1000).rounded()))_local"
            if let existing = entries[id] {
                if existing.local == nil {
                    entries[id] = BookLibraryEntry(record: existing.record, local: book)
                }
            } else {
                let record = BookVersionRecordFactory.fromPersistable(book, bookVersionId: id, source: .localMigration)
                entries[id] = BookLibraryEntry(record: record, local: book)
            }
        }
        return entries.values.sorted {
            if $0.record.createdAt == $1.record.createdAt { return $0.record.bookVersionId < $1.record.bookVersionId }
            return $0.record.createdAt > $1.record.createdAt
        }
    }
}
