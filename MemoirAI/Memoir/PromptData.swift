//
//  PromptData.swift
//  MemoirAI
//
//  Created by user941803 on 4/21/25.
//

import Foundation
import SwiftUI

// MARK: - Memoir mode (Normal / Parent / Relationships)

enum MemoirMode: String, CaseIterable {
    case normal = "normal"
    case parent = "parent"
    case relationships = "relationships"

    var displayTitle: String {
        switch self {
        case .normal: return "Normal"
        case .parent: return "Parent"
        case .relationships: return "Relationships"
        }
    }

    /// Titles shown in `MemoirModePickerView` and the memoir hub switch menu.
    var memoirKindTitle: String {
        switch self {
        case .normal: return "My Life Story"
        case .parent: return "Parenthood"
        case .relationships: return "Love & Relationships"
        }
    }
}

/// Primary storage for memoir question set.
let memoirModeKey = "memoirMode"

/// Legacy: parent toggle before three-way mode existed.
let memoirParentModeKey = "memoirParentMode"

/// Migrates `memoirParentMode` bool into `memoirMode` once, then uses `memoirMode` only.
func migrateLegacyMemoirModeIfNeeded() {
    let d = UserDefaults.standard
    guard d.object(forKey: memoirModeKey) == nil else { return }
    if d.bool(forKey: memoirParentModeKey) {
        d.set(MemoirMode.parent.rawValue, forKey: memoirModeKey)
    } else {
        d.set(MemoirMode.normal.rawValue, forKey: memoirModeKey)
    }
}

func currentMemoirMode() -> MemoirMode {
    migrateLegacyMemoirModeIfNeeded()
    let raw = UserDefaults.standard.string(forKey: memoirModeKey) ?? MemoirMode.normal.rawValue
    return MemoirMode(rawValue: raw) ?? .normal
}

// MARK: - Active chapters (reads the toggle at call time)

var activeChapters: [Chapter] {
    migrateLegacyMemoirModeIfNeeded()
    switch currentMemoirMode() {
    case .normal: return allChapters
    case .parent: return allParentChapters
    case .relationships: return allRelationshipChapters
    }
}

/// When normal memoir chapter titles changed, older `MemoryEntry.chapter` strings may still use these labels.
let normalChapterTitleAliases: [String: [String]] = [
    "Beginnings": ["Childhood"],
    "Growing Up": ["First Job"],
    "Belonging": ["Love"],
    "Becoming": ["Parenthood"],
    "Love": ["Life Lessons"],
    "Care": ["Faith"],
    "Work & Purpose": ["Career"],
    "Hard Seasons": ["Hard Times"],
    "Change": ["Triumphs"]
]

/// Parent-mode title rewrite: new title → the old titles it replaces (by chapter index).
let parentChapterTitleAliases: [String: [String]] = [
    "Before They Came": ["Childhood"],
    "The Day They Arrived": ["First Job"],
    "The Little Years": ["Love"],
    "What They've Taught": ["What They've Taught You", "Parenthood"],
    "Where You Come From": ["Life Lessons"],
    "What You Love": ["Faith"],
    "What You Believe": ["Career"],
    "When Life Was Hard": ["Hard Times"],
    "Your Little World": ["Your Little World Together", "Triumphs"],
    "When They're Older": ["For When They're Older", "Legacy"]
]

/// Love-mode title rewrite: new title → the old titles it replaces.
/// Old Love had 4 chapters; new has 10. Aliases map each new chapter to the nearest-content old chapter so legacy recordings still surface.
let relationshipChapterTitleAliases: [String: [String]] = [
    "First Glimpse": ["Beginning"],
    "Falling": ["Beginning"],
    "Choosing Each Other": ["Choosing Each Other"],
    "Your Places": ["Home Together"],
    "The Everyday": ["Everyday Love"],
    "What Makes You Laugh": ["Everyday Love"],
    "Through the Storms": ["Growth, Depth, and Future"],
    "Who You're Becoming": ["Growth, Depth, and Future"],
    "One Memory to Keep": ["If One Memory Could Say It All", "Growth, Depth, and Future"]
]

/// True when `entryChapter` (stored on a memory) should count toward the chapter identified by `chapterTitle` (current UI chapter).
func chapterTitleMatches(_ entryChapter: String?, _ chapterTitle: String) -> Bool {
    let ct = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let ec = entryChapter?.trimmingCharacters(in: .whitespacesAndNewlines), !ec.isEmpty, !ct.isEmpty else { return false }
    if ec.caseInsensitiveCompare(ct) == .orderedSame { return true }
    let aliasesTable: [String: [String]]
    switch currentMemoirMode() {
    case .normal: aliasesTable = normalChapterTitleAliases
    case .parent: aliasesTable = parentChapterTitleAliases
    case .relationships: aliasesTable = relationshipChapterTitleAliases
    }
    if let aliases = aliasesTable[ct] {
        return aliases.contains { $0.caseInsensitiveCompare(ec) == .orderedSame }
    }
    return false
}

/// Prompt texts that count as “shipped” for a normal chapter, including pre-rename prompts (e.g. old `Love` chapter → `Belonging`).
func normalChapterPromptTextsIncludingLegacy(for chapter: Chapter) -> [String] {
    var texts = chapter.prompts.map(\.text)
    guard currentMemoirMode() == .normal, let aliases = normalChapterTitleAliases[chapter.title] else {
        return texts
    }
    for legacyTitle in aliases {
        if let legacy = allChaptersLegacyKnownPrompts.first(where: { $0.title.caseInsensitiveCompare(legacyTitle) == .orderedSame }) {
            texts.append(contentsOf: legacy.prompts.map(\.text))
        }
    }
    return texts
}

/// How many prompt nodes are satisfied for this chapter (current or legacy prompt text per index). Used for hub + homepage progress.
func filledPromptSlotsForChapter(entries: [MemoryEntry], chapter: Chapter) -> Int {
    let entriesForChapter = entries.filter { chapterTitleMatches($0.chapter, chapter.title) }
    let legacySameNumber = allChaptersLegacyKnownPrompts.first { $0.number == chapter.number }
    let useLegacyIndexMatch = currentMemoirMode() == .normal
        && allChapters.contains(where: { $0.number == chapter.number && $0.title == chapter.title })
        && legacySameNumber != nil
    var filled = 0
    for (index, prompt) in chapter.prompts.enumerated() {
        if entriesForChapter.contains(where: { $0.prompt == prompt.text }) {
            filled += 1
            continue
        }
        if useLegacyIndexMatch,
           let leg = legacySameNumber,
           index < leg.prompts.count,
           entriesForChapter.contains(where: { $0.prompt == leg.prompts[index].text }) {
            filled += 1
        }
    }
    return filled
}

/// Maps Parent-mode chapter titles to asset catalog image names (which match Normal-mode titles).
func chapterImageAssetName(for title: String) -> String {
    let key = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let mapping: [String: String] = [
        // Legacy Parent-mode titles (kept for migration).
        "childhood": "beginnings",
        "first job": "growing up",
        "parenthood": "belonging",
        "life lessons": "becoming",
        "faith": "care",
        "career": "work & purpose",
        "hard times": "hard seasons",
        "triumphs": "change",
        // New Parent-mode titles.
        "before they came": "beginnings",
        "the day they arrived": "growing up",
        "the little years": "belonging",
        "what they've taught": "becoming",
        "what they've taught you": "becoming",
        "where you come from": "love",
        "what you love": "care",
        "what you believe": "work & purpose",
        "when life was hard": "hard seasons",
        "your little world": "change",
        "your little world together": "change",
        "when they're older": "legacy",
        "for when they're older": "legacy"
    ]
    return mapping[key] ?? key
}

/// Old normal chapter set (titles + prompts) kept so `isKnownMemoirPrompt` still recognizes pre-update memories.
let allChaptersLegacyKnownPrompts: [Chapter] = [
    Chapter(number: 1, title: "Childhood", prompts: [
        MemoryPrompt(text: "What is one of your clearest early memories?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "What games or activities made you happiest as a child?", x: 0.40, y: 0.62),
        MemoryPrompt(text: "Tell me about a place you loved to spend time when you were small.", x: 0.35, y: 0.44),
        MemoryPrompt(text: "Who showed you kindness when you were young, and what did they do?", x: 0.50, y: 0.28)
    ]),
    Chapter(number: 2, title: "First Job", prompts: [
        MemoryPrompt(text: "How did you first earn money on your own?", x: 0.20, y: 0.80),
        MemoryPrompt(text: "What was a skill you had to learn quickly in your first job?", x: 0.45, y: 0.60),
        MemoryPrompt(text: "Did someone help or guide you during your early work days?", x: 0.70, y: 0.45),
        MemoryPrompt(text: "What was the biggest lesson you learned from your work experiences?", x: 0.60, y: 0.30)
    ]),
    Chapter(number: 3, title: "Love", prompts: [
        MemoryPrompt(text: "Think of someone you have loved deeply—what first drew you to them?", x: 0.22, y: 0.76),
        MemoryPrompt(text: "Describe a simple moment with someone you love that still warms your heart.", x: 0.44, y: 0.60),
        MemoryPrompt(text: "What has love—romantic or otherwise—taught you about yourself?", x: 0.65, y: 0.44),
        MemoryPrompt(text: "How do you show care to the people who matter most to you today?", x: 0.48, y: 0.28)
    ]),
    Chapter(number: 4, title: "Parenthood", prompts: [
        MemoryPrompt(text: "If you are a parent, what did you feel the day you met your child? (If not, tell about nurturing someone younger than you.)", x: 0.30, y: 0.80),
        MemoryPrompt(text: "What family routine or tradition do you hope will continue?", x: 0.55, y: 0.63),
        MemoryPrompt(text: "Share a challenge you faced while caring for children and how you handled it.", x: 0.75, y: 0.44),
        MemoryPrompt(text: "What value did you try hardest to pass on, and why?", x: 0.60, y: 0.28)
    ]),
    Chapter(number: 5, title: "Life Lessons", prompts: [
        MemoryPrompt(text: "Tell about an event that changed how you see the world.", x: 0.26, y: 0.78),
        MemoryPrompt(text: "What is a mistake that later became a gift?", x: 0.42, y: 0.63),
        MemoryPrompt(text: "Which small habit has quietly improved your life?", x: 0.66, y: 0.45),
        MemoryPrompt(text: "What advice would you offer yourself when you were a kid?", x: 0.52, y: 0.28)
    ]),
    Chapter(number: 6, title: "Faith", prompts: [
        MemoryPrompt(text: "What role—if any—have faith or personal beliefs played in your life?", x: 0.25, y: 0.80),
        MemoryPrompt(text: "Describe a time you felt supported by something bigger than yourself.", x: 0.46, y: 0.60),
        MemoryPrompt(text: "Have you ever struggled with doubt? What helped you move forward?", x: 0.70, y: 0.43),
        MemoryPrompt(text: "Which practice, text, or idea gives you peace?", x: 0.56, y: 0.28)
    ]),
    Chapter(number: 7, title: "Career", prompts: [
        MemoryPrompt(text: "What kind of work has felt most meaningful to you, and why?", x: 0.24, y: 0.80),
        MemoryPrompt(text: "Tell about a mentor or co-worker who made a difference.", x: 0.45, y: 0.63),
        MemoryPrompt(text: "What was a hard decision you had to make at work?", x: 0.70, y: 0.46),
        MemoryPrompt(text: "Looking back, what part of your working life brings you pride?", x: 0.56, y: 0.30)
    ]),
    Chapter(number: 8, title: "Hard Times", prompts: [
        MemoryPrompt(text: "Describe a season when life was difficult. What helped you cope?", x: 0.30, y: 0.80),
        MemoryPrompt(text: "Who stood by you during a difficult time in your life?", x: 0.48, y: 0.63),
        MemoryPrompt(text: "What inner strength did you discover when facing a challenge?", x: 0.70, y: 0.44),
        MemoryPrompt(text: "What wisdom has a hard experience in your life left you with?", x: 0.55, y: 0.30)
    ]),
    Chapter(number: 9, title: "Triumphs", prompts: [
        MemoryPrompt(text: "Tell the story of a goal you reached that mattered to you.", x: 0.26, y: 0.78),
        MemoryPrompt(text: "What obstacles did you have to overcome to achieve something important?", x: 0.45, y: 0.61),
        MemoryPrompt(text: "How did accomplishing a big goal change you or those around you?", x: 0.66, y: 0.45),
        MemoryPrompt(text: "What advice would you give someone chasing a difficult dream?", x: 0.50, y: 0.29)
    ]),
    Chapter(number: 10, title: "Legacy", prompts: [
        MemoryPrompt(text: "When future family members think of you, what do you hope they feel?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "Is there a value, story, or tradition you want carried forward?", x: 0.44, y: 0.60),
        MemoryPrompt(text: "What do you see as your most lasting contribution?", x: 0.68, y: 0.45),
        MemoryPrompt(text: "If you could leave one message for people listening years from now, what would it be?", x: 0.52, y: 0.30)
    ]),
    // Pre-rewrite Parent-mode set.
    Chapter(number: 101, title: "Childhood", prompts: [
        MemoryPrompt(text: "What is a childhood memory that has stayed with you over the years?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "Where did you feel most at home as a child?", x: 0.40, y: 0.62),
        MemoryPrompt(text: "Who made childhood feel safe or special for you?", x: 0.35, y: 0.44),
        MemoryPrompt(text: "What is a childhood moment that taught you something you still carry today?", x: 0.50, y: 0.28)
    ]),
    Chapter(number: 102, title: "First Job", prompts: [
        MemoryPrompt(text: "What do you remember most about your first job?", x: 0.20, y: 0.80),
        MemoryPrompt(text: "Where was your first job, and what do you remember most about that place?", x: 0.45, y: 0.60),
        MemoryPrompt(text: "Was there a person or moment from your first job that stayed with you?", x: 0.70, y: 0.45),
        MemoryPrompt(text: "What did your first job reveal to you about yourself?", x: 0.60, y: 0.30)
    ]),
    Chapter(number: 103, title: "Love", prompts: [
        MemoryPrompt(text: "What is one moment when love felt real to you?", x: 0.22, y: 0.76),
        MemoryPrompt(text: "What was a moment when you knew you truly loved someone?", x: 0.44, y: 0.60),
        MemoryPrompt(text: "What moment made you feel deeply cared for?", x: 0.65, y: 0.44),
        MemoryPrompt(text: "What kind of love do you hope your child always feels in life, and when have you felt that kind of love yourself?", x: 0.48, y: 0.28)
    ]),
    Chapter(number: 104, title: "Parenthood", prompts: [
        MemoryPrompt(text: "What is a moment that made being a parent feel real to you?", x: 0.30, y: 0.80),
        MemoryPrompt(text: "What is one early memory with your child you can picture clearly?", x: 0.55, y: 0.63),
        MemoryPrompt(text: "What is one small parenting moment that means a lot to you?", x: 0.75, y: 0.44),
        MemoryPrompt(text: "What do you hope your child always feels from you?", x: 0.60, y: 0.28)
    ]),
    Chapter(number: 105, title: "Life Lessons", prompts: [
        MemoryPrompt(text: "What is a moment in your life that changed the way you see things?", x: 0.26, y: 0.78),
        MemoryPrompt(text: "What was happening in your life when that moment came?", x: 0.42, y: 0.63),
        MemoryPrompt(text: "What is a moment that taught you something you still carry today?", x: 0.66, y: 0.45),
        MemoryPrompt(text: "What is an experience that shaped the kind of person you are now?", x: 0.52, y: 0.28)
    ]),
    Chapter(number: 106, title: "Faith", prompts: [
        MemoryPrompt(text: "What is a moment that made your faith, hope, or deeper beliefs feel real to you?", x: 0.25, y: 0.80),
        MemoryPrompt(text: "What is a moment when you turned to faith, hope, or prayer in a hard time?", x: 0.46, y: 0.60),
        MemoryPrompt(text: "What is a moment when someone helped guide your heart or mind?", x: 0.70, y: 0.43),
        MemoryPrompt(text: "What kind of peace or strength do you hope your child carries through life?", x: 0.56, y: 0.28)
    ]),
    Chapter(number: 107, title: "Career", prompts: [
        MemoryPrompt(text: "What is a work moment you still feel proud of?", x: 0.24, y: 0.80),
        MemoryPrompt(text: "What is a moment from your working life that has stayed with you?", x: 0.45, y: 0.63),
        MemoryPrompt(text: "What is a moment when someone at work shaped or influenced you?", x: 0.70, y: 0.46),
        MemoryPrompt(text: "What part of your work story feels important to pass on to your child?", x: 0.56, y: 0.30)
    ]),
    Chapter(number: 108, title: "Hard Times", prompts: [
        MemoryPrompt(text: "What is a hard moment in life that has stayed with you?", x: 0.30, y: 0.80),
        MemoryPrompt(text: "What is a moment from that time when you found the strength to keep going?", x: 0.48, y: 0.63),
        MemoryPrompt(text: "Who stood by you when life felt heavy?", x: 0.70, y: 0.44),
        MemoryPrompt(text: "What is a moment from that season that showed you your own strength?", x: 0.55, y: 0.30)
    ]),
    Chapter(number: 109, title: "Triumphs", prompts: [
        MemoryPrompt(text: "What is an achievement in your life that meant a lot to you?", x: 0.26, y: 0.78),
        MemoryPrompt(text: "What is a moment when something you hoped for finally happened?", x: 0.45, y: 0.61),
        MemoryPrompt(text: "What is a moment when you surprised yourself with what you could do?", x: 0.66, y: 0.45),
        MemoryPrompt(text: "What is a moment that felt like a win you will always remember?", x: 0.50, y: 0.29)
    ]),
    Chapter(number: 110, title: "Legacy", prompts: [
        MemoryPrompt(text: "What is a moment that feels like it says a lot about who you are?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "What part of your story feels most important to pass on?", x: 0.44, y: 0.60),
        MemoryPrompt(text: "What kind of person do you hope your child knows you were?", x: 0.68, y: 0.45),
        MemoryPrompt(text: "What do you hope your child holds onto most from your life story?", x: 0.52, y: 0.30)
    ]),
    // Pre-rewrite Love-mode set.
    Chapter(number: 201, title: "Beginning", prompts: [
        MemoryPrompt(text: "Tell me about the first time you met them.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe the first real conversation with them that stayed with you.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about the first moment you felt drawn to them.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe your first date like a scene from a movie.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about an early moment that made you think, \u{201C}I want to keep seeing this person.\u{201D}", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe your first kiss with them.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about the first time they made you laugh so hard you relaxed around them.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe the first time you saw them vulnerable with you.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about an early moment where a tiny detail about them got stuck in your mind.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "If you could relive one moment from before you were officially together, which one would you choose?", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 202, title: "Choosing Each Other", prompts: [
        MemoryPrompt(text: "Tell me about the moment this stopped feeling casual and started feeling real.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a time they made you feel chosen.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a moment they understood you without needing a long explanation.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a time they showed love in a way that felt unmistakably like them.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a moment you looked at them and thought, \u{201C}This is my person.\u{201D}", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a time they surprised you in the best way.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a moment they made an ordinary day feel special.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a moment when something they said stayed with you long after the day ended.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a time they made you feel especially adored.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a moment you saw them at their absolute best.", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 203, title: "Everyday Love", prompts: [
        MemoryPrompt(text: "Tell me about your favorite ritual you share, and one specific time it happened.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a quiet, ordinary moment with them that still means a lot to you.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a meal, coffee run, drive, or errand with them that became memorable.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a moment at home that captures what being with them is really like.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a time you watched them with friends, family, kids, or strangers and loved them more because of it.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a small act of care from them that hit you harder than they probably realized.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a moment when the two of you felt completely in sync.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe an inside joke or silly moment that says everything about your relationship.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about an early-relationship habit, date, or ritual you miss, and one time it felt especially good.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a celebration, big or small, that became unforgettable because they were there.", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 204, title: "Growth, Depth, and Future", prompts: [
        MemoryPrompt(text: "Tell me about a hard day when they showed up for you in exactly the way you needed.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a disagreement or difficult season that changed your relationship for the better.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a moment of apology, repair, or reconnection after distance.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a time they saw you at your worst and stayed.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a moment you realized this relationship was helping you grow.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe something that once felt hard between you but now makes you smile when you look back.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a moment when you felt especially lucky to be with them.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Describe a moment that makes you proud of the relationship you\u{2019}ve built together.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a conversation about the future that made your future feel real.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "If this book ended on one memory that captures what this relationship means to you, what moment would you choose?", x: 0.5, y: 0.5)
    ])
]

/// Returns true when the prompt text belongs to any shipped question set,
/// so memories recorded in one mode are still recognised after switching.
func isKnownMemoirPrompt(chapterTitle: String, promptText: String) -> Bool {
    let trimmedChapter = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    for chapters in [allChapters, allParentChapters, allRelationshipChapters, allChaptersLegacyKnownPrompts] {
        for ch in chapters where ch.title.caseInsensitiveCompare(trimmedChapter) == .orderedSame {
            if ch.prompts.contains(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmedPrompt) == .orderedSame }) {
                return true
            }
        }
    }
    return false
}

// MARK: - Relationship chapter visuals (shared by RelationshipJourneyView + RecordingView)

/// Full-screen gradient for a Relationships chapter — matches the journey map (richer stops + cool accents).
func relationshipChapterGradient(forChapterNumber number: Int) -> LinearGradient {
    switch number {
    case 1:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 0.98, green: 0.72, blue: 0.82), location: 0),
                .init(color: Color(red: 0.92, green: 0.88, blue: 0.95), location: 0.22),
                .init(color: Color(red: 0.99, green: 0.90, blue: 0.78), location: 0.5),
                .init(color: Color(red: 0.97, green: 0.82, blue: 0.88), location: 0.78),
                .init(color: Color(red: 0.94, green: 0.78, blue: 0.92), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 2:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 1.0, green: 0.78, blue: 0.62), location: 0),
                .init(color: Color(red: 0.88, green: 0.72, blue: 0.92), location: 0.35),
                .init(color: Color(red: 0.99, green: 0.68, blue: 0.55), location: 0.72),
                .init(color: Color(red: 0.95, green: 0.52, blue: 0.48), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 3:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 0.99, green: 0.76, blue: 0.48), location: 0),
                .init(color: Color(red: 0.72, green: 0.88, blue: 0.92), location: 0.28),
                .init(color: Color(red: 0.99, green: 0.93, blue: 0.78), location: 0.55),
                .init(color: Color(red: 0.97, green: 0.96, blue: 0.90), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 4:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 0.95, green: 0.82, blue: 0.62), location: 0),
                .init(color: Color(red: 0.78, green: 0.88, blue: 0.75), location: 0.35),
                .init(color: Color(red: 0.92, green: 0.75, blue: 0.58), location: 0.70),
                .init(color: Color(red: 0.72, green: 0.55, blue: 0.48), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 5:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 1.0, green: 0.88, blue: 0.72), location: 0),
                .init(color: Color(red: 0.92, green: 0.82, blue: 0.72), location: 0.35),
                .init(color: Color(red: 0.98, green: 0.78, blue: 0.62), location: 0.75),
                .init(color: Color(red: 0.82, green: 0.62, blue: 0.52), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 6:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 1.0, green: 0.82, blue: 0.45), location: 0),
                .init(color: Color(red: 0.99, green: 0.70, blue: 0.55), location: 0.38),
                .init(color: Color(red: 1.0, green: 0.86, blue: 0.58), location: 0.72),
                .init(color: Color(red: 0.92, green: 0.55, blue: 0.42), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 7:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 0.38, green: 0.32, blue: 0.52), location: 0),
                .init(color: Color(red: 0.65, green: 0.55, blue: 0.72), location: 0.35),
                .init(color: Color(red: 0.48, green: 0.42, blue: 0.58), location: 0.70),
                .init(color: Color(red: 0.28, green: 0.26, blue: 0.42), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 8:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 0.98, green: 0.68, blue: 0.38), location: 0),
                .init(color: Color(red: 0.72, green: 0.55, blue: 0.78), location: 0.35),
                .init(color: Color(red: 0.95, green: 0.58, blue: 0.38), location: 0.72),
                .init(color: Color(red: 0.58, green: 0.38, blue: 0.45), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 9:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 0.72, green: 0.85, blue: 0.92), location: 0),
                .init(color: Color(red: 0.92, green: 0.82, blue: 0.95), location: 0.35),
                .init(color: Color(red: 0.82, green: 0.78, blue: 0.92), location: 0.72),
                .init(color: Color(red: 0.58, green: 0.62, blue: 0.82), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 10:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 0.98, green: 0.88, blue: 0.72), location: 0),
                .init(color: Color(red: 0.95, green: 0.72, blue: 0.62), location: 0.30),
                .init(color: Color(red: 0.85, green: 0.55, blue: 0.62), location: 0.62),
                .init(color: Color(red: 0.55, green: 0.38, blue: 0.58), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    default:
        return LinearGradient(
            stops: [
                .init(color: Color(red: 0.48, green: 0.28, blue: 0.38), location: 0),
                .init(color: Color(red: 0.35, green: 0.42, blue: 0.55), location: 0.35),
                .init(color: Color(red: 0.78, green: 0.48, blue: 0.42), location: 0.65),
                .init(color: Color(red: 0.92, green: 0.76, blue: 0.48), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Warm + cool accents for journey decorations (larger icons, contrast).
func relationshipChapterAccentPalette(forChapterNumber number: Int) -> [Color] {
    switch number {
    case 1:
        return [
            Color(red: 0.92, green: 0.38, blue: 0.52),
            Color(red: 0.28, green: 0.62, blue: 0.72),
            Color(red: 0.96, green: 0.72, blue: 0.28),
            Color(red: 0.45, green: 0.55, blue: 0.85)
        ]
    case 2:
        return [
            Color(red: 0.98, green: 0.48, blue: 0.35),
            Color(red: 0.35, green: 0.55, blue: 0.88),
            Color(red: 0.96, green: 0.68, blue: 0.32),
            Color(red: 0.55, green: 0.35, blue: 0.65)
        ]
    case 3:
        return [
            Color(red: 0.98, green: 0.58, blue: 0.22),
            Color(red: 0.30, green: 0.65, blue: 0.78),
            Color(red: 0.92, green: 0.42, blue: 0.55),
            Color(red: 0.75, green: 0.62, blue: 0.28)
        ]
    case 4:
        return [
            Color(red: 0.58, green: 0.72, blue: 0.48),
            Color(red: 0.85, green: 0.68, blue: 0.42),
            Color(red: 0.42, green: 0.55, blue: 0.72),
            Color(red: 0.72, green: 0.52, blue: 0.38)
        ]
    case 5:
        return [
            Color(red: 0.98, green: 0.78, blue: 0.42),
            Color(red: 0.72, green: 0.58, blue: 0.88),
            Color(red: 0.92, green: 0.62, blue: 0.35),
            Color(red: 0.48, green: 0.72, blue: 0.78)
        ]
    case 6:
        return [
            Color(red: 1.0, green: 0.72, blue: 0.28),
            Color(red: 0.92, green: 0.42, blue: 0.52),
            Color(red: 0.58, green: 0.72, blue: 0.92),
            Color(red: 0.95, green: 0.85, blue: 0.48)
        ]
    case 7:
        return [
            Color(red: 0.55, green: 0.48, blue: 0.78),
            Color(red: 0.88, green: 0.65, blue: 0.75),
            Color(red: 0.42, green: 0.38, blue: 0.62),
            Color(red: 0.72, green: 0.82, blue: 0.88)
        ]
    case 8:
        return [
            Color(red: 0.98, green: 0.58, blue: 0.35),
            Color(red: 0.62, green: 0.48, blue: 0.75),
            Color(red: 0.88, green: 0.72, blue: 0.48),
            Color(red: 0.52, green: 0.55, blue: 0.82)
        ]
    case 9:
        return [
            Color(red: 0.42, green: 0.58, blue: 0.88),
            Color(red: 0.82, green: 0.62, blue: 0.92),
            Color(red: 0.58, green: 0.72, blue: 0.85),
            Color(red: 0.72, green: 0.52, blue: 0.78)
        ]
    case 10:
        return [
            Color(red: 0.95, green: 0.68, blue: 0.52),
            Color(red: 0.82, green: 0.42, blue: 0.58),
            Color(red: 0.72, green: 0.55, blue: 0.78),
            Color(red: 0.96, green: 0.82, blue: 0.58)
        ]
    default:
        return [
            Color(red: 0.92, green: 0.55, blue: 0.45),
            Color(red: 0.40, green: 0.55, blue: 0.82),
            Color(red: 0.96, green: 0.75, blue: 0.35),
            Color(red: 0.55, green: 0.42, blue: 0.62)
        ]
    }
}

/// Secondary cool accent for radial glow spots on the map.
func relationshipChapterCoolAccent(forChapterNumber number: Int) -> Color {
    switch number {
    case 1: return Color(red: 0.32, green: 0.62, blue: 0.78)
    case 2: return Color(red: 0.38, green: 0.48, blue: 0.88)
    case 3: return Color(red: 0.28, green: 0.68, blue: 0.82)
    case 4: return Color(red: 0.42, green: 0.58, blue: 0.72)
    case 5: return Color(red: 0.48, green: 0.72, blue: 0.82)
    case 6: return Color(red: 0.35, green: 0.65, blue: 0.92)
    case 7: return Color(red: 0.48, green: 0.52, blue: 0.82)
    case 8: return Color(red: 0.38, green: 0.55, blue: 0.85)
    case 9: return Color(red: 0.42, green: 0.62, blue: 0.92)
    case 10: return Color(red: 0.58, green: 0.48, blue: 0.78)
    default: return Color(red: 0.45, green: 0.52, blue: 0.78)
    }
}

/// Top color for scroll-edge fade (matches gradient start).
func relationshipChapterTopFadeColor(forChapterNumber number: Int) -> Color {
    switch number {
    case 1: return Color(red: 0.98, green: 0.72, blue: 0.82)
    case 2: return Color(red: 1.0, green: 0.78, blue: 0.62)
    case 3: return Color(red: 0.99, green: 0.76, blue: 0.48)
    case 4: return Color(red: 0.95, green: 0.82, blue: 0.62)
    case 5: return Color(red: 1.0, green: 0.88, blue: 0.72)
    case 6: return Color(red: 1.0, green: 0.82, blue: 0.45)
    case 7: return Color(red: 0.38, green: 0.32, blue: 0.52)
    case 8: return Color(red: 0.98, green: 0.68, blue: 0.38)
    case 9: return Color(red: 0.72, green: 0.85, blue: 0.92)
    case 10: return Color(red: 0.98, green: 0.88, blue: 0.72)
    default: return Color(red: 0.48, green: 0.28, blue: 0.38)
    }
}

/// When `title` is a Relationships chapter title, returns its gradient for recording backdrop; otherwise `nil`.
func relationshipChapterGradient(forChapterTitle title: String) -> LinearGradient? {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let ch = allRelationshipChapters.first(where: { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
        return nil
    }
    return relationshipChapterGradient(forChapterNumber: ch.number)
}

// MARK: - Normal (default) questions

let allChapters: [Chapter] = [
    Chapter(number: 1, title: "Beginnings", prompts: [
        MemoryPrompt(text: "What was one of your funniest childhood memories?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "Tell me a childhood story where you learned a lesson", x: 0.40, y: 0.62),
        MemoryPrompt(text: "Tell me about an early memory that reveals something about your personality.", x: 0.35, y: 0.44),
        MemoryPrompt(text: "What type of kid were you? Do you have any memories that best show who you were?", x: 0.50, y: 0.28)
    ]),
    Chapter(number: 2, title: "Growing Up", prompts: [
        MemoryPrompt(text: "Growing up what were one of the biggest ways you changed? Are there any memories that were the cause of that or came from that change?", x: 0.20, y: 0.80),
        MemoryPrompt(text: "Tell me a story of when you broke a rule or took a risk.", x: 0.45, y: 0.60),
        MemoryPrompt(text: "What was a moment where growing up felt real to you?", x: 0.70, y: 0.45),
        MemoryPrompt(text: "Where did you grow up? What was it like?", x: 0.60, y: 0.30)
    ]),
    Chapter(number: 3, title: "Belonging", prompts: [
        MemoryPrompt(text: "Describe a moment when you realized a friendship or relationship mattered more than you had realized.", x: 0.22, y: 0.76),
        MemoryPrompt(text: "If you wanted to show someone what love was through a memory, what memory would you choose?", x: 0.44, y: 0.60),
        MemoryPrompt(text: "What has been one of your favorite memories with your friends as you were growing up?", x: 0.65, y: 0.44),
        MemoryPrompt(text: "Who's been one of the most influential people in your life? Do you have a specific memory that best shows who they were?", x: 0.48, y: 0.28)
    ]),
    Chapter(number: 4, title: "Becoming", prompts: [
        MemoryPrompt(text: "Tell me about a choice you made that shaped the direction of your life.", x: 0.30, y: 0.80),
        MemoryPrompt(text: "If there's one word that describes the type of person you want to be or are, what would it be?", x: 0.55, y: 0.63),
        MemoryPrompt(text: "Tell me about a moment when freedom felt exciting to you.", x: 0.75, y: 0.44),
        MemoryPrompt(text: "If you had to choose one memory that shows you becoming yourself, what would it be?", x: 0.60, y: 0.28)
    ]),
    Chapter(number: 5, title: "Love", prompts: [
        MemoryPrompt(text: "Tell me about a simple moment with someone you loved that became unforgettable.", x: 0.26, y: 0.78),
        MemoryPrompt(text: "If there's one word that could best capture the greatest love you've experienced, what would it be and why?", x: 0.42, y: 0.63),
        MemoryPrompt(text: "Tell me about a memory that captures the joy that love brings.", x: 0.66, y: 0.45),
        MemoryPrompt(text: "If one memory could show what love means to you, what moment would you choose?", x: 0.52, y: 0.28)
    ]),
    Chapter(number: 6, title: "Care", prompts: [
        MemoryPrompt(text: "Describe a time when you were cared for in a way you never forgot.", x: 0.25, y: 0.80),
        MemoryPrompt(text: "Tell me about a moment when you comforted someone who needed you.", x: 0.46, y: 0.60),
        MemoryPrompt(text: "In your life who has been one of the people that have cared for you the most and what's a specific memory of that?", x: 0.70, y: 0.43),
        MemoryPrompt(text: "Describe a moment that captures the kind of love you try to give others.", x: 0.56, y: 0.28)
    ]),
    Chapter(number: 7, title: "Work & Purpose", prompts: [
        MemoryPrompt(text: "Tell me about a day when your work made you feel purposeful or proud.", x: 0.24, y: 0.80),
        MemoryPrompt(text: "What's one of the things you believe about the purpose of your life and when did you start believing it?", x: 0.45, y: 0.63),
        MemoryPrompt(text: "Tell me about a person or moment that shaped your sense of purpose.", x: 0.70, y: 0.46),
        MemoryPrompt(text: "When's a time where you've been incredibly driven to work on something?", x: 0.56, y: 0.30)
    ]),
    Chapter(number: 8, title: "Hard Seasons", prompts: [
        MemoryPrompt(text: "What was one of the hardest periods of your life and what's a specific memory from it?", x: 0.30, y: 0.80),
        MemoryPrompt(text: "Have any hard times changed how you treat other people or saw the world and if so how?", x: 0.48, y: 0.63),
        MemoryPrompt(text: "Tell me about a time when someone showed up for you during a hard time and what it meant to you.", x: 0.70, y: 0.44),
        MemoryPrompt(text: "What's a difficult memory that later became part of your strength?", x: 0.55, y: 0.30)
    ]),
    Chapter(number: 9, title: "Change", prompts: [
        MemoryPrompt(text: "Tell me about a move, ending, beginning, or transition that changed you.", x: 0.26, y: 0.78),
        MemoryPrompt(text: "Across your life what have been one of the biggest ways your personality has changed and was there anything that caused that? A moment, a person, a story?", x: 0.45, y: 0.61),
        MemoryPrompt(text: "Describe a moment when change felt frightening.", x: 0.66, y: 0.45),
        MemoryPrompt(text: "Tell me about a moment that taught you what really mattered to you.", x: 0.50, y: 0.29)
    ]),
    Chapter(number: 10, title: "Legacy", prompts: [
        MemoryPrompt(text: "Describe a value, tradition, or way of living that has shaped you", x: 0.25, y: 0.78),
        MemoryPrompt(text: "Tell me about a memory where you impacted somebody more than you thought", x: 0.44, y: 0.60),
        MemoryPrompt(text: "What were one of the happiest moments of your life?", x: 0.68, y: 0.45),
        MemoryPrompt(text: "What was another one of the happiest moments of your life?", x: 0.52, y: 0.30)
    ])
]

// MARK: - Parent Mode questions
//
// The recorder is the parent. Questions elicit visible, paintable scenes.
// Per-child prompts carry `{kid}` as a placeholder; they are expanded at render time
// using `Profile.childNames`. Universal prompts are the same for all children.

let allParentChapters: [Chapter] = [
    Chapter(number: 1, title: "Before They Came", prompts: [
        MemoryPrompt(text: "Tell me about a day from your twenties that shows who you were before you had kids. Where were you, what were you doing, who were you with?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "Walk me through the home you lived in right before your first child was on the way. What did each room look like?", x: 0.40, y: 0.62),
        MemoryPrompt(text: "Describe a day from your life before kids where you felt completely free. What did the scene look like?", x: 0.35, y: 0.44),
        MemoryPrompt(text: "Tell me about a song, meal, or habit from that younger version of you that you still reach for today. When is the last time you did?", x: 0.50, y: 0.28)
    ]),

    Chapter(number: 2, title: "The Day They Arrived", prompts: [
        MemoryPrompt(text: "Tell me the story of the day {kid} was born. Where were you, who was with you, what did the room look like?", x: 0.20, y: 0.80, isPerChild: true),
        MemoryPrompt(text: "Describe the first moment you saw {kid}. What did they look like, who was holding them, what were you wearing?", x: 0.45, y: 0.60, isPerChild: true),
        MemoryPrompt(text: "Walk me through the drive home with {kid} for the first time. What was the weather, what did the car look like, who drove?", x: 0.70, y: 0.45, isPerChild: true),
        MemoryPrompt(text: "Tell me about your first night at home with {kid}. Where did they sleep, what did the room look like, who was there?", x: 0.60, y: 0.30, isPerChild: true)
    ]),

    Chapter(number: 3, title: "The Little Years", prompts: [
        MemoryPrompt(text: "Describe a tiny, specific thing {kid} did as a baby or toddler that you never want to forget. Paint the whole scene.", x: 0.22, y: 0.76, isPerChild: true),
        MemoryPrompt(text: "Paint the picture of a morning from when {kid} was little. What did your kitchen look like, what did you eat, what were you all wearing?", x: 0.44, y: 0.60, isPerChild: true),
        MemoryPrompt(text: "Tell me about a time {kid} was sick or scared and what you did to comfort them. Set the scene fully.", x: 0.65, y: 0.44, isPerChild: true),
        MemoryPrompt(text: "Tell me about a silly or sweet thing {kid} used to say or do, and the exact moment and place you remember it.", x: 0.48, y: 0.28, isPerChild: true)
    ]),

    Chapter(number: 4, title: "What They've Taught", prompts: [
        MemoryPrompt(text: "Describe a specific moment when being {kid}'s parent changed how you saw the world.", x: 0.30, y: 0.80, isPerChild: true),
        MemoryPrompt(text: "Tell me about a day you were exhausted and something small {kid} did lit you back up. Where were you, what did they do?", x: 0.55, y: 0.63, isPerChild: true),
        MemoryPrompt(text: "Paint the scene of a place {kid} took you through their play or imagination that you'd never have gone on your own.", x: 0.75, y: 0.44, isPerChild: true),
        MemoryPrompt(text: "Tell me about the moment it clicked, something about love you didn't understand until you had {kid}.", x: 0.60, y: 0.28, isPerChild: true)
    ]),

    Chapter(number: 5, title: "Where You Come From", prompts: [
        MemoryPrompt(text: "Describe your own parent or grandparent at their best, in one specific scene with them.", x: 0.26, y: 0.78),
        MemoryPrompt(text: "Tell me about a family tradition from your childhood you want to carry forward. What did it look like the last time it happened well?", x: 0.42, y: 0.63),
        MemoryPrompt(text: "Walk me through the place you called home as a kid. What did it look like, where was the corner you'd disappear to?", x: 0.66, y: 0.45),
        MemoryPrompt(text: "Tell me a story about your family your kids should know by heart. Tell it like a movie scene.", x: 0.52, y: 0.28)
    ]),

    Chapter(number: 6, title: "What You Love", prompts: [
        MemoryPrompt(text: "Describe the place in the world that feels most like you. What does it look like, what do you do there?", x: 0.25, y: 0.80),
        MemoryPrompt(text: "Tell me about a meal that means something to you. What does it look like on the table when you make it?", x: 0.46, y: 0.60),
        MemoryPrompt(text: "Paint the picture of the first time a song that matters to you really landed. Where were you, who were you with?", x: 0.70, y: 0.43),
        MemoryPrompt(text: "Tell me about a friend who shaped you, through one specific day with them.", x: 0.56, y: 0.28)
    ]),

    Chapter(number: 7, title: "What You Believe", prompts: [
        MemoryPrompt(text: "Describe a moment that taught you what matters most. The setting, what happened, what you thought right after.", x: 0.24, y: 0.80),
        MemoryPrompt(text: "Tell me about a person you admire, through one specific scene that shows why.", x: 0.45, y: 0.63),
        MemoryPrompt(text: "Walk me through a small daily thing you do that is a quiet kind of love. When did you start doing it?", x: 0.70, y: 0.46),
        MemoryPrompt(text: "Tell me about a moment your kids should picture when they need to be brave.", x: 0.56, y: 0.30)
    ]),

    Chapter(number: 8, title: "When Life Was Hard", prompts: [
        MemoryPrompt(text: "Tell me about a hard season you came through. Where were you living, what did the days look like?", x: 0.30, y: 0.80),
        MemoryPrompt(text: "Describe a person who helped you during a difficult time, in one specific moment with them.", x: 0.48, y: 0.63),
        MemoryPrompt(text: "Paint the picture of a day you were scared and what got you through it.", x: 0.70, y: 0.44),
        MemoryPrompt(text: "Tell me about a moment you are proud of, not for winning, but for not giving up.", x: 0.55, y: 0.30)
    ]),

    Chapter(number: 9, title: "Your Little World", prompts: [
        MemoryPrompt(text: "Describe your favorite spot with {kid}. Your seat on the couch, your bench, your corner of the world.", x: 0.26, y: 0.78, isPerChild: true),
        MemoryPrompt(text: "Tell me about a small ritual you share with {kid} and the best time you ever did it.", x: 0.45, y: 0.61, isPerChild: true),
        MemoryPrompt(text: "Tell me about an inside joke or silly word only you and {kid} use. Where did it come from?", x: 0.66, y: 0.45, isPerChild: true),
        MemoryPrompt(text: "Paint the picture of a perfect ordinary day with {kid}. What did you eat, where did you go, how did it end?", x: 0.50, y: 0.29, isPerChild: true)
    ]),

    Chapter(number: 10, title: "When They're Older", prompts: [
        MemoryPrompt(text: "Describe a day you hope {kid} has when they are grown. Paint it in detail, like you can already see it.", x: 0.25, y: 0.78, isPerChild: true),
        MemoryPrompt(text: "Tell me a piece of advice you want {kid} to have, tied to the moment in your life that taught it to you.", x: 0.44, y: 0.60, isPerChild: true),
        MemoryPrompt(text: "Describe the kind of love you hope {kid} finds, through a memory of when you saw love at its best.", x: 0.68, y: 0.45, isPerChild: true),
        MemoryPrompt(text: "If you could send {kid} one image from this point in your life together to remember forever, what would it be?", x: 0.52, y: 0.30, isPerChild: true)
    ])
]

// MARK: - Per-child prompt expansion

/// Substitutes `{kid}` in the prompt text with the given child name.
private func substitutedPromptText(_ template: String, kid: String) -> String {
    return template.replacingOccurrences(of: "{kid}", with: kid)
}

/// Returns the list of concrete prompts a user actually records against for a given Parenthood chapter.
/// Universal prompts pass through unchanged. Per-child prompts emit one entry per child in `childNames`.
/// If `childNames` is empty, per-child templates are rendered with the neutral phrase "your child".
/// Emitted MemoryPrompt entries share the original x/y coordinates so map layout stays stable.
func expandedPromptsForParent(chapter: Chapter, childNames: [String]) -> [MemoryPrompt] {
    var out: [MemoryPrompt] = []
    for prompt in chapter.prompts {
        if !prompt.isPerChild {
            out.append(prompt)
            continue
        }
        if childNames.isEmpty {
            out.append(MemoryPrompt(
                text: substitutedPromptText(prompt.text, kid: "your child"),
                x: prompt.x, y: prompt.y,
                isPerChild: true
            ))
        } else {
            for name in childNames {
                out.append(MemoryPrompt(
                    text: substitutedPromptText(prompt.text, kid: name),
                    x: prompt.x, y: prompt.y,
                    isPerChild: true
                ))
            }
        }
    }
    return out
}

/// Expands a single per-child prompt into one entry per child (or a single neutral entry when `childNames` is empty).
/// For non-per-child prompts, returns the prompt unchanged inside a single-element array.
func expandedChildPrompts(for prompt: MemoryPrompt, childNames: [String]) -> [MemoryPrompt] {
    guard prompt.isPerChild else { return [prompt] }
    if childNames.isEmpty {
        return [MemoryPrompt(
            text: substitutedPromptText(prompt.text, kid: "your child"),
            x: prompt.x, y: prompt.y,
            isPerChild: true
        )]
    }
    return childNames.map { name in
        MemoryPrompt(
            text: substitutedPromptText(prompt.text, kid: name),
            x: prompt.x, y: prompt.y,
            isPerChild: true
        )
    }
}

// MARK: - Relationships mode (10 chapters × 4 prompts; coordinates unused — RelationshipJourneyView lays out nodes)

let allRelationshipChapters: [Chapter] = [
    Chapter(number: 1, title: "First Glimpse", prompts: [
        MemoryPrompt(text: "Where were you the first time you saw them? What were they doing?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "What was the first real conversation you remember having with them? Where were you?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Was there a moment early on — a look, something they said, something small — that stuck with you?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "What was one of the first things that made you want to keep spending time with them?", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 2, title: "Falling", prompts: [
        MemoryPrompt(text: "Tell me about the first time you two were actually alone together. Where were you, what did you do?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "When did you first realize you liked them more than you expected to?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Was there a specific day or night in those early weeks that you kept thinking about after?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "What was the moment you knew this wasn't just casual anymore?", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 3, title: "Choosing Each Other", prompts: [
        MemoryPrompt(text: "When did it stop feeling like you were figuring it out and start feeling like a real thing?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a time they showed up for you in a way you didn't expect.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Was there a day — a trip, a long drive, just the two of you somewhere — that you still think about?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "When did you know you wanted this to last? Where were you?", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 4, title: "Your Places", prompts: [
        MemoryPrompt(text: "Is there a place that feels like the two of you — somewhere you keep ending up, or that just feels like yours?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "What's a meal, a drink, or a food thing that's become part of your relationship? Tell me about a time you had it together.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "What's the first place you remember feeling at home with them, even if it wasn't your home?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a slow afternoon or evening together that you'd want to go back to. Where were you, what were you doing?", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 5, title: "The Everyday", prompts: [
        MemoryPrompt(text: "What does a normal morning with them look like? Tell me about one you remember.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Where do you two spend the most time together? What does that spot look like?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a completely ordinary night with them that you'd want to remember.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "What's a regular day with them that, looking back, you'd keep if you could?", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 6, title: "What Makes You Laugh", prompts: [
        MemoryPrompt(text: "Do you have an inside joke or a word that's only funny to the two of you? Where did it come from?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Is there something goofy or silly you two do together that would make no sense to anyone else?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "What's something they've done that you still bring up and laugh about?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a time you two laughed so hard you couldn't stop. What happened, where were you?", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 7, title: "Through the Hard Parts", prompts: [
        MemoryPrompt(text: "Tell me about a time things were hard and they were there for you. What did that actually look like?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Has there been a rough stretch you two got through together? What did those days look like?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Was there a scary or stressful moment you faced together? Tell me about it.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a time you really leaned on each other. Where were you, what was going on?", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 8, title: "Seeing Them Clearly", prompts: [
        MemoryPrompt(text: "Tell me about a time you watched them do something and thought, that's exactly who they are.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "What's something they did that genuinely surprised you — in a good way?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Have you ever watched them with people they love — friends, family, a stranger even — and just felt proud?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Tell me about a moment where you saw them at their best. Where were you, what were they doing?", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 9, title: "Who You're Becoming", prompts: [
        MemoryPrompt(text: "Have you two talked about the future in a way that made it feel real? What did that conversation look like?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "When did you first feel like you were actually building something together, not just seeing where it goes?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "What does life look like for the two of you a year from now? Describe a day you can already picture.", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Where do you picture the two of you in five years? What does that scene look like?", x: 0.5, y: 0.5)
    ]),
    Chapter(number: 10, title: "One Memory to Keep", prompts: [
        MemoryPrompt(text: "If you had to pick one moment from your relationship to keep forever, what would it be?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "Is there a photo — one you actually have or one you wish existed — that captures the two of you?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "What's something about your relationship you'd want the people who love you to know?", x: 0.5, y: 0.5),
        MemoryPrompt(text: "If you had to choose one scene that captures what you two are to each other, what would it be?", x: 0.5, y: 0.5)
    ])
]
