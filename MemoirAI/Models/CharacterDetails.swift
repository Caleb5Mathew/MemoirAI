import Foundation

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

    var hasAudio: Bool {
        playbackURL != nil
    }
}
