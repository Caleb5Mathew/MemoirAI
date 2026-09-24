import Foundation

enum MemoryAudioAvailabilityPolicy {
    static func hasAudio(
        localFileExists: Bool,
        embeddedAudioByteCount: Int?,
        hasRemoteAudio: Bool = false
    ) -> Bool {
        localFileExists || (embeddedAudioByteCount ?? 0) > 0 || hasRemoteAudio
    }

    static func remoteURL(storedReference: String?) -> URL? {
        guard let storedReference,
              let url = URL(string: storedReference),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

extension MemoryEntry {
    /// Returns playable local audio, recreating a temporary file from Core Data when needed.
    var playbackURL: URL? {
        if let urlString = audioFileURL,
           let url = URL(string: urlString),
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        guard let data = value(forKey: "audioData") as? Data, !data.isEmpty else {
            return nil
        }
        let fileExtension = URL(string: audioFileURL ?? "")?.pathExtension.lowercased() == "m4a"
            ? "m4a"
            : "caf"
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent((id?.uuidString ?? UUID().uuidString) + ".\(fileExtension)")
        if !FileManager.default.fileExists(atPath: temporaryURL.path) {
            do {
                try data.write(to: temporaryURL, options: .atomic)
            } catch {
                print("❌ Could not write temporary audio file: \(error.localizedDescription)")
                return nil
            }
        }
        return temporaryURL
    }

    /// Returns either playable local audio or the private HTTPS download URL restored from Firestore.
    var availableAudioURL: URL? {
        playbackURL ?? MemoryAudioAvailabilityPolicy.remoteURL(storedReference: audioFileURL)
    }

    var hasAudio: Bool {
        if let urlString = audioFileURL,
           let url = URL(string: urlString),
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }

        let embeddedAudioByteCount = (value(forKey: "audioData") as? Data)?.count
        let hasRemoteAudio = MemoryAudioAvailabilityPolicy.remoteURL(
            storedReference: audioFileURL
        ) != nil
        return MemoryAudioAvailabilityPolicy.hasAudio(
            localFileExists: false,
            embeddedAudioByteCount: embeddedAudioByteCount,
            hasRemoteAudio: hasRemoteAudio
        )
    }
}
