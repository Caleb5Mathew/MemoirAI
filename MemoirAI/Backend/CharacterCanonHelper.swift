import Foundation

/// Lightweight helpers shared by memory enhancement and story tooling — keeps tier batching + name hints aligned with server-side canon thinking.
enum CharacterCanonHelper {

    /// Capitalized name-like tokens (same spirit as server `autoDetectNamesInTranscript`).
    static func capitalizedNameCandidates(in text: String, max: Int = 14) -> [String] {
        let pattern = #"\b[A-Z][a-z]{1,20}(?:\s+[A-Z][a-z]{1,20})?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let stop: Set<String> = [
            "one", "day", "we", "our", "my", "me", "i", "the", "a", "an", "it", "and",
            "in", "on", "at", "to", "for", "with", "of", "middle", "park", "woods", "creek"
        ]
        var out: [String] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, out.count < max else { return }
            let raw = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let token = raw.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
            guard !token.isEmpty, !stop.contains(token) else { return }
            let key = raw.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(raw)
        }
        return out
    }

    /// Heuristic “people in scene” — pronouns / kinship / proper names.
    static func likelyPeoplePresent(in text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains(" i ") || lower.hasPrefix("i ") { return true }
        if ["we ", " us ", " she ", " he ", " they ", " mom", " dad", " son", " daughter", " friend", " wife", " husband"]
            .contains(where: { lower.contains($0) }) {
            return true
        }
        return !capitalizedNameCandidates(in: text, max: 3).isEmpty
    }

    /// Strong cues that setting + action are already stated (deterministic skip signal combined with LLM preflight).
    static func hasLikelySettingAndAction(in text: String) -> Bool {
        let lower = text.lowercased()
        let settingCue = ["at home", "in the", "on the", "outside", "kitchen", "school", "church", "park", "beach", "car", "room", "yard", "street", "restaurant"]
            .contains { lower.contains($0) }
        let actionCue = ["went", "walked", "ran", "sat", "stood", "played", "talked", "danced", "celebrated", "visited", "drove", "ate", "cooked"]
            .contains { lower.contains($0) }
        return settingCue && actionCue && lower.split(separator: " ").count >= 12
    }
}
