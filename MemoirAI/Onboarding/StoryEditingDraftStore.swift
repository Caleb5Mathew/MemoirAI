import Foundation
import CryptoKit

/// Editing inputs deliberately exclude submitted memory and generation identifiers.
struct StoryEditingDraft: Codable, Equatable {
    var text: String
    var prompt: String? = nil
    var audioURL: URL? = nil
    var rawTranscript: String? = nil
    var narratorName: String? = nil
    var audience: OnboardingAudience? = nil
    var storyteller: OnboardingStoryteller? = nil
    var interviewMode: Bool = false
    var interviewAudioProcessed: Bool = false

    var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || audioURL != nil }
}

struct StoryEditingDraftStore {
    enum Flow: String { case recording, onboarding, chapterRecording }
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StoryEditingDrafts", isDirectory: true)
    }

    func load(userID: String, profileID: UUID, flow: Flow, contextID: String = "") throws -> StoryEditingDraft? {
        let url = fileURL(userID: userID, profileID: profileID, flow: flow, contextID: contextID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(StoryEditingDraft.self, from: Data(contentsOf: url))
    }

    func save(_ draft: StoryEditingDraft, userID: String, profileID: UUID, flow: Flow, contextID: String = "") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(
            to: fileURL(userID: userID, profileID: profileID, flow: flow, contextID: contextID),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    /// Removes metadata only. An audio file can also belong to a saved memory.
    func clear(userID: String, profileID: UUID, flow: Flow, contextID: String = "") throws {
        let url = fileURL(userID: userID, profileID: profileID, flow: flow, contextID: contextID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func hasDraft(userID: String, profileID: UUID) throws -> Bool {
        let files = try scopedFiles(userID: userID, profileID: profileID)
        return try files.contains { url in
            try JSONDecoder().decode(StoryEditingDraft.self, from: Data(contentsOf: url)).hasContent
        }
    }

    func exclusiveRecordingURLs(userID: String, recordingsDirectory: URL, preserving: Set<URL>) throws -> Set<URL> {
        let ownedFiles = Set(try scopedFiles(userID: userID, profileID: nil))
        guard !ownedFiles.isEmpty else { return [] }
        let allFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var ownedAudio = Set<URL>()
        var protectedAudio = Set(preserving.map { $0.standardizedFileURL })
        for file in allFiles {
            let draft: StoryEditingDraft
            do {
                draft = try JSONDecoder().decode(StoryEditingDraft.self, from: Data(contentsOf: file))
            } catch {
                // An unreadable draft may share a recording. Keep audio until ownership can be established.
                return []
            }
            guard let audio = draft.audioURL, audio.isFileURL else { continue }
            let normalized = audio.standardizedFileURL
            if ownedFiles.contains(file) { ownedAudio.insert(normalized) }
            else { protectedAudio.insert(normalized) }
        }
        return Set(ownedAudio.subtracting(protectedAudio).filter { url in
            url.deletingLastPathComponent().path == recordingsDirectory.standardizedFileURL.path &&
            url.pathExtension == "m4a" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
        })
    }

    func clearAccount(userID: String) throws {
        for url in try scopedFiles(userID: userID, profileID: nil) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func scopedFiles(userID: String, profileID: UUID?) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let owner = Data(userID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let prefix = owner + "_" + (profileID.map { $0.uuidString + "_" } ?? "")
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
    }

    private func fileURL(userID: String, profileID: UUID, flow: Flow, contextID: String) -> URL {
        let owner = Data(userID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let context = SHA256.hash(data: Data(contextID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(owner)_\(profileID.uuidString)_\(flow.rawValue)_\(context).json")
    }
}
