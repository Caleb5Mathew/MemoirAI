//
//  CoverCopyPolicy.swift
//  MemoirAI
//
//  Style-aware default titles, interior bookends, and back-cover copy helpers for print.
//

import Foundation

/// Stable UUIDs for non-memory interior pages (title spread / colophon).
enum BookInteriorAnchor {
    static let titlePageMemoryId = UUID(uuidString: "B00BCAFE-FEED-4000-8000-000000000001")!
    static let closingPageMemoryId = UUID(uuidString: "B00BCAFE-FEED-4000-8000-000000000002")!
    static let blankPageMemoryId = UUID(uuidString: "B00BCAFE-FEED-4000-8000-000000000003")!

    static func isNonMemoryPage(_ id: UUID) -> Bool {
        id == titlePageMemoryId || id == blankPageMemoryId || id == closingPageMemoryId
    }
}

/// Serialized on `PersistableStorybook` / Firestore — maps to `BookCoverRenderer` fonts.
enum CoverFontPreset: String, Codable, CaseIterable {
    case kidsSerif
    case realisticSerif
    case comicBold
    case customClean
}

enum StorybookMemoirNamePolicy {
    static func usableName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let placeholders: Set<String> = ["grandparent", "narrator", "the narrator", "the memoir narrator", "memoir narrator", "the storyteller", "memoir", "memoirai reader", "your name", "name", "unknown"]
        guard !value.isEmpty, value.count <= 100,
              !placeholders.contains(value.lowercased()) else { return nil }
        return value
    }

    static func resolvedName(profileName: String?, narratorNames: [String]) -> String? {
        if let name = usableName(profileName) { return name }
        let candidates = narratorNames.compactMap(usableName)
        let unique = Set(candidates.map { $0.lowercased() })
        guard unique.count == 1 else { return nil }
        return candidates.first
    }

    static func bookTitle(for name: String) -> String {
        guard let name = usableName(name) else { return "Memoir" }
        return "\(name)’s Memoir"
    }
}

struct CoverCopyPolicy {
    let artStyle: ArtStyle
    let profileDisplayName: String

    private var shortName: String {
        let t = profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "MemoirAI Reader" }
        return t
    }

    /// Default cover / print title before user edits.
    func defaultBookTitle() -> String {
        StorybookMemoirNamePolicy.bookTitle(for: profileDisplayName)
    }

    /// Subject's display name for the closing page credit line.
    func subjectDisplayName() -> String {
        shortName
    }

    func coverFontPreset() -> CoverFontPreset {
        switch artStyle {
        case .kidsBook: return .kidsSerif
        case .realistic: return .realisticSerif
        case .comic: return .comicBold
        case .custom: return .customClean
        }
    }

    /// Short line under the title on the interior title page.
    func interiorTitlePageBlurb() -> String {
        "A collection of life stories"
    }

    /// Deterministic back-cover pitch when AI is unavailable.
    func fallbackBackCoverPitch(bookTitle: String) -> String {
        let title = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.isEmpty ? defaultBookTitle() : title
        switch artStyle {
        case .kidsBook:
            return "\(safeTitle) is a gentle storybook celebration of family, curiosity, and the little moments that matter most. Open the pages and share it again and again."
        case .realistic:
            return "\(safeTitle) preserves a life in vivid scenes and heartfelt words, a keepsake to revisit and pass down."
        case .comic:
            return "\(safeTitle) brings your memories to life with energy and heart, a fun and unforgettable gift edition."
        case .custom:
            return "\(safeTitle) turns your memories into a beautiful keepsake, personal, lasting, and full of meaning."
        }
    }

    /// Instructions for the LLM (Gemini) — output must be plain prose, no markdown.
    func aiPitchSystemPrompt(bookTitle: String, storyExcerpt: String, memoryThemes: [String]) -> String {
        let themes = memoryThemes.prefix(8).joined(separator: "; ")
        let styleLabel: String = {
            switch artStyle {
            case .kidsBook: return "warm children's storybook; wholesome; family-friendly"
            case .realistic: return "elegant adult memoir; sincere; grounded"
            case .comic: return "playful graphic-novel tone; energetic but family-friendly"
            case .custom: return "neutral literary gift book"
            }
        }()
        return """
        You write short back-cover marketing copy for a printed keepsake book.
        Rules:
        - Output ONLY the pitch text (no quotes, no title line, no markdown).
        - Exactly 2 or 3 short sentences.
        - Max 380 characters total.
        - Mention the book title "\(bookTitle)" once, naturally.
        - Tone: \(styleLabel).
        - Do not claim awards, bestseller status, or fabricate facts.
        - Themes you may subtly echo (optional): \(themes.isEmpty ? "none given" : themes).
        Story context (may be truncated): \(storyExcerpt.prefix(900))
        """
    }

    /// Clamp and trim model output for the physical back panel.
    static func sanitizePitch(_ raw: String, maxLength: Int = 380) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\""), t.hasSuffix("\""), t.count >= 2 {
            t = String(t.dropFirst().dropLast())
        }
        t = t.replacingOccurrences(of: "\n", with: " ")
        t = t.replacingOccurrences(of: "  ", with: " ")
        if t.count > maxLength {
            let idx = t.index(t.startIndex, offsetBy: maxLength)
            var cut = String(t[..<idx])
            if let lastPeriod = cut.lastIndex(of: "."), lastPeriod > cut.startIndex {
                cut = String(cut[..<cut.index(after: lastPeriod)])
            }
            t = cut.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }
}
