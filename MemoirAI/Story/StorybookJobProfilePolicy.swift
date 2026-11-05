import Foundation

enum StorybookJobProfilePolicy {
    static func matches(_ data: [String: Any], profileID: UUID) -> Bool {
        let keys = ["profileId", "profileID"].filter { data[$0] != nil }
        guard !keys.isEmpty else { return false }
        return keys.allSatisfy { key in
            guard let raw = data[key] as? String, let value = UUID(uuidString: raw) else { return false }
            return value == profileID
        }
    }
}
