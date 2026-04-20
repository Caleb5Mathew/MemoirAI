import Foundation

extension CharacterDetails {
    /// Merges `incoming` extraction into `existing` by character name (case-insensitive, trimmed).
    /// For each matching name, non-empty fields from `incoming` override empty fields in `existing`;
    /// if `incoming` has a non-empty value, it replaces the corresponding field.
    /// New names in `incoming` are appended. If `incoming` has no characters, returns `existing`.
    static func merging(existing: CharacterDetails, incoming: CharacterDetails) -> CharacterDetails {
        if incoming.characters.isEmpty {
            return existing
        }
        if existing.characters.isEmpty {
            return incoming
        }

        var result = existing
        for inc in incoming.characters {
            let incName = inc.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !incName.isEmpty else { continue }
            let key = incName.lowercased()
            if let idx = result.characters.firstIndex(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
            }) {
                result.characters[idx] = mergeCharacter(result.characters[idx], with: inc)
            } else {
                result.characters.append(copyCharacter(inc))
            }
        }
        return result
    }

    private static func mergeCharacter(
        _ base: CharacterDetails.Character,
        with incoming: CharacterDetails.Character
    ) -> CharacterDetails.Character {
        var out = CharacterDetails.Character()
        out.globalCharacterId = base.globalCharacterId ?? incoming.globalCharacterId
        out.name = pickName(base: base.name, incoming: incoming.name)
        out.age = pickField(incoming.age, base.age)
        out.gender = pickField(incoming.gender, base.gender)
        out.ethnicity = pickField(incoming.ethnicity, base.ethnicity)
        out.hairAndFeatures = pickField(incoming.hairAndFeatures, base.hairAndFeatures)
        out.clothes = pickField(incoming.clothes, base.clothes)
        out.relationshipToNarrator = pickField(incoming.relationshipToNarrator, base.relationshipToNarrator)
        out.appearance = pickField(incoming.appearance, base.appearance)
        out.race = pickField(incoming.race, base.race)
        out.physicalDescription = pickField(incoming.physicalDescription, base.physicalDescription)
        out.clothing = pickField(incoming.clothing, base.clothing)
        return out
    }

    private static func pickField(_ incoming: String, _ base: String) -> String {
        let t = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return base
    }

    private static func pickName(base: String, incoming: String) -> String {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let i = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if !i.isEmpty { return i }
        return b
    }

    private static func copyCharacter(_ c: CharacterDetails.Character) -> CharacterDetails.Character {
        var out = CharacterDetails.Character()
        out.globalCharacterId = c.globalCharacterId
        out.name = c.name
        out.age = c.age
        out.gender = c.gender
        out.ethnicity = c.ethnicity
        out.hairAndFeatures = c.hairAndFeatures
        out.clothes = c.clothes
        out.relationshipToNarrator = c.relationshipToNarrator
        out.appearance = c.appearance
        out.race = c.race
        out.physicalDescription = c.physicalDescription
        out.clothing = c.clothing
        return out
    }
}
