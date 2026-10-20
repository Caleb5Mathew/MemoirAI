import Foundation

struct OnboardingDraft: Codable {
    let session: OnboardingSession
    let story: String
    let rawTranscript: String?
    let audioURL: URL?
    let photoData: Data?
    var previewStory: String? = nil
    var audioDigest: String? = nil
}

/// Keeps the exact submitted inputs so a retry never spends another generation.
struct OnboardingDraftStore {
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OnboardingDrafts", isDirectory: true)
    }

    func load(userID: String) throws -> OnboardingDraft? {
        let url = fileURL(userID: userID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(OnboardingDraft.self, from: Data(contentsOf: url))
    }

    func save(_ draft: OnboardingDraft, userID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: fileURL(userID: userID), options: .atomic)
    }

    func clear(userID: String) throws {
        let url = fileURL(userID: userID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func fileURL(userID: String) -> URL {
        let name = Data(userID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
}
