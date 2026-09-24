// RelationshipJourneyView.swift
// MemoirAI — relationship artwork and questions using the shared memoir journey.

import SwiftUI

struct RelationshipJourneyView: View {
    let chapter: Chapter
    let containerSafeAreaInsets: EdgeInsets

    init(chapter: Chapter, containerSafeAreaInsets: EdgeInsets = EdgeInsets()) {
        self.chapter = chapter
        self.containerSafeAreaInsets = containerSafeAreaInsets
    }

    var body: some View {
        ChapterJourneyView(
            chapter: chapterUsingMemoirGeometry,
            containerSafeAreaInsets: containerSafeAreaInsets,
            artworkAssetNameOverride: relationshipChapterImageAssetName(
                forChapterNumber: chapter.number
            ),
            memoirMode: .relationships
        )
    }

    private var chapterUsingMemoirGeometry: Chapter {
        let coordinates = ChapterJourneyNodeLayoutPolicy.coordinates(
            forRelationshipChapterNumber: chapter.number
        )
        let prompts = zip(chapter.prompts, coordinates).map { prompt, point in
            MemoryPrompt(
                text: prompt.text,
                x: point.x,
                y: point.y,
                isCompleted: prompt.isCompleted,
                isPerChild: prompt.isPerChild
            )
        }
        return Chapter(number: chapter.number, title: chapter.title, prompts: prompts)
    }
}
