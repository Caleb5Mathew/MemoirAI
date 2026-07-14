import Foundation

extension CharacterDetails {

    /// Profile names that read as roles (aligned with cloud `isRelationshipStyleProfileName`).
    static func isRelationshipStyleProfileName(_ name: String) -> Bool {
        let lowerFull = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["memoir narrator", "the narrator", "the storyteller"].contains(lowerFull) { return true }
        let first = lowerFull.split(separator: " ").first.map(String.init) ?? ""
        let tokens: Set<String> = [
            "grandparent", "grandma", "grandpa", "grandmother", "grandfather",
            "nana", "nan", "mom", "mum", "dad", "mother", "father", "mama", "papa",
            "mommy", "daddy", "aunt", "auntie", "uncle", "narrator"
        ]
        if tokens.contains(first) { return true }
        if first == "the", lowerFull.contains("narrator") { return true }
        return false
    }

    /// Display label for narrator cards (matches cloud `imageNarratorDisplayName`).
    static func imageNarratorDisplayLabel(profileDisplayName: String?, relationshipStyleProfileName: Bool) -> String {
        let raw = (profileDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "Narrator" }
        if relationshipStyleProfileName || Self.isRelationshipStyleProfileName(raw) {
            return "the memoir narrator"
        }
        return raw
    }

    private static func familyRoleKey(from text: String) -> String? {
        let s = text.lowercased()
        if s.range(of: #"\b(grandmother|grandma|granny|nana|nan)\b"#, options: .regularExpression) != nil { return "grandmother" }
        if s.range(of: #"\b(grandfather|grandpa)\b"#, options: .regularExpression) != nil { return "grandfather" }
        if s.range(of: #"\b(mother|mom|mum|mama|mommy)\b"#, options: .regularExpression) != nil { return "mother" }
        if s.range(of: #"\b(father|dad|daddy|papa|pop)\b"#, options: .regularExpression) != nil { return "father" }
        if s.range(of: #"\b(wife)\b"#, options: .regularExpression) != nil { return "wife" }
        if s.range(of: #"\b(husband)\b"#, options: .regularExpression) != nil { return "husband" }
        if s.range(of: #"\b(daughter)\b"#, options: .regularExpression) != nil { return "daughter" }
        if s.range(of: #"\b(son)\b"#, options: .regularExpression) != nil { return "son" }
        if s.range(of: #"\b(brother|bro)\b"#, options: .regularExpression) != nil { return "brother" }
        if s.range(of: #"\b(sister|sis)\b"#, options: .regularExpression) != nil { return "sister" }
        return nil
    }

    /// Post-extraction: fixes narrator placeholder names and role vs `relationshipToNarrator` mismatches (e.g. Mother + wife).
    mutating func normalizeCardDisplayNames(profileDisplayName: String?, relationshipStyleProfileName: Bool) {
        let display = Self.imageNarratorDisplayLabel(
            profileDisplayName: profileDisplayName,
            relationshipStyleProfileName: relationshipStyleProfileName
        )
        let narratorAliases: Set<String> = ["i", "me", "myself", "narrator", "the narrator", "the memoir narrator"]
        for i in characters.indices {
            let relRaw = characters[i].relationshipToNarrator.trimmingCharacters(in: .whitespacesAndNewlines)
            let relLower = relRaw.lowercased()
            if relLower.contains("memoir narrator") {
                characters[i].name = display
                continue
            }
            let rawName = characters[i].name.trimmingCharacters(in: .whitespacesAndNewlines)
            let nameLower = rawName.lowercased()
            if narratorAliases.contains(nameLower) {
                characters[i].name = display
                continue
            }
            if relRaw.isEmpty { continue }
            if let nk = Self.familyRoleKey(from: rawName),
               let rk = Self.familyRoleKey(from: relRaw),
               nk != rk {
                characters[i].name = "\(rawName) (the narrator's \(relRaw))"
            }
        }
    }
}
