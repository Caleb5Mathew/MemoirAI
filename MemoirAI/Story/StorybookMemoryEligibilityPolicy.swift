import Foundation

/// Book selection includes saved stories from every capture mode in the active profile.
enum StorybookMemoryEligibilityPolicy {
    static func matches(_ entry: MemoryEntry) -> Bool {
        BookTranscriptionPreflightPolicy.hasUsableText(entry.text)
            || !(entry.audioFileURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
