//
//  MemoirView.swift
//  MemoirAI
//
//  Created by ChatGPT on 5/31/25.
//  “Back” chevron is now black via .tint(.black).
//

import SwiftUI
import CoreData
import RevenueCat
import RevenueCatUI

// MARK: - Custom Serif Font Fallback
extension Font {
    static func customSerifFallback(size: CGFloat) -> Font {
        let fontNames = [
            "Georgia-Bold", "NewYork-Bold", "Palatino-Bold",
            "TimesNewRomanPS-BoldMT", "Charter-Bold"
        ]
        for name in fontNames where UIFont(name: name, size: size) != nil {
            return Font.custom(name, size: size)
        }
        return .system(size: size, weight: .bold, design: .serif)
    }
}

// MARK: - App Color Theme
struct ColorTheme {
    let softCream      = Color(red: 253/255, green: 234/255, blue: 198/255)
    let terracotta     = Color(red: 210/255, green: 112/255, blue:  45/255)
    let warmGreen      = Color(red: 169/255, green: 175/255, blue: 133/255)
    let deepGreen      = Color(red:  39/255, green:  60/255, blue:  34/255)
    let tileBackground = Color(red: 255/255, green: 241/255, blue: 213/255)
}

struct MemoirView: View {
    let colors = ColorTheme()
    @EnvironmentObject var profileVM: ProfileViewModel
    @StateObject private var subscriptionManager = RCSubscriptionManager.shared
    @State private var showPaywall = false
    @State private var entries: [MemoryEntry] = []
    @State private var navigateToChapter: Int? = nil
    private let totalChapters = allChapters.count

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if let ch = firstIncompleteChapter { currentChapterCard(for: ch) }
                    allChaptersTitle
                    chaptersGrid
                }
                .padding(.bottom, 100)
            }
            .background(colors.softCream.ignoresSafeArea())
            .onAppear {
                fetchEntries()
            }
            .toolbarBackground(colors.softCream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(item: $navigateToChapter) { chapterNumber in
                ChapterJourneyView(chapter: getMockChapter(chapterNumber))
                    .environmentObject(profileVM)
                    .navigationBarHidden(true)
            }
        }
        .tint(.black)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(displayCloseButton: true)
        }
    }

    // MARK: — UI sections
    private var header: some View {
        VStack(spacing: 12) {
            Image("Flower")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .padding(.bottom, 4)

            Text("Hold on to your story")
                .font(.customSerifFallback(size: 30))
                .foregroundColor(colors.deepGreen)
                .multilineTextAlignment(.center)

            Text("\(completedChaptersCount()) of \(totalChapters) chapters completed")
                .font(.subheadline)
                .foregroundColor(colors.deepGreen)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private func currentChapterCard(for chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .foregroundColor(colors.terracotta)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Chapter \(chapter.number) – \(chapter.title)")
                        .font(.headline)
                        .foregroundColor(colors.deepGreen)

                    Text("\(entriesForChapter(chapter).count) of \(chapter.prompts.count) memories recorded")
                        .font(.subheadline)
                        .foregroundColor(colors.deepGreen)
                }
            }

            Button(action: {
                if chapter.number == 1 || isSubscribed {
                    navigateToChapter = chapter.number
                } else {
                    showPaywall = true
                }
            }) {
                Text("Continue Chapter")
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(colors.terracotta)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(colors.tileBackground)
        .cornerRadius(32)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 6)
        .padding(.horizontal)
    }

    private var allChaptersTitle: some View {
        Text("All Chapters")
            .font(.headline)
            .foregroundColor(colors.deepGreen)
            .padding(.horizontal)
            .padding(.top, 12)
    }

    private var chaptersGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(1...10, id: \.self) { chapterNumber in
                if let chapter = allChapters.first(where: { $0.number == chapterNumber }) {
                    let isDone = entriesForChapter(chapter).count >= chapter.prompts.count
                    let isLocked = chapterNumber > 1 && !isSubscribed

                    Button(action: {
                        if chapterNumber == 1 || isSubscribed {
                            navigateToChapter = chapterNumber
                        } else {
                            showPaywall = true
                        }
                    }) {
                        ChapterTileView(
                            chapterNumber: chapterNumber,
                            title: chapter.title,
                            isLocked: isLocked,
                            isCurrent: false,
                            isCompleted: isDone,
                            colors: colors
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: — Data helpers
    private var firstIncompleteChapter: Chapter? {
        allChapters.first { entriesForChapter($0).count < $0.prompts.count }
    }

    private func completedChaptersCount() -> Int {
        allChapters.filter { entriesForChapter($0).count >= $0.prompts.count }.count
    }

    private func entriesForChapter(_ c: Chapter) -> [MemoryEntry] {
        entries.filter {
            ($0.chapter ?? "") == c.title &&
            c.prompts.map(\.text).contains($0.prompt ?? "")
        }
    }

    private func fetchEntries() {
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "profileID == %@", profileVM.selectedProfile.id as CVarArg)
        do { entries = try PersistenceController.shared.container.viewContext.fetch(request) }
        catch { print("Fetch error:", error) }
    }

    private func getMockChapter(_ idx: Int) -> Chapter {
        guard let base = allChapters.first(where: { $0.number == idx }) else {
            return .init(number: idx, title: "Unknown", prompts: [])
        }
        let coords: [(CGFloat, CGFloat)] = [(0.88,0.80),(0.55,0.63),(0.85,0.43),(0.68,0.28)]
        let prompts = zip(base.prompts, coords).map { (p,c) in
            MemoryPrompt(text: p.text, x: c.0, y: c.1)
        }
        return .init(number: base.number, title: base.title, prompts: prompts)
    }

    // Check if user has subscription
    private var isSubscribed: Bool {
        subscriptionManager.activeTier != nil
    }
}

// MARK: — ChapterTileView (unchanged)
struct ChapterTileView: View {
    let chapterNumber: Int
    let title: String
    let isLocked: Bool
    let isCurrent: Bool
    let isCompleted: Bool
    let colors: ColorTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isCompleted ? "checkmark" : "book")
                    .foregroundColor(colors.deepGreen)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Chapter \(chapterNumber)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(colors.deepGreen)
                    Text(title)
                        .font(.caption)
                        .foregroundColor(colors.deepGreen)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(colors.tileBackground)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

// Make Int conform to Identifiable for navigation
extension Int: Identifiable {
    public var id: Int { self }
}
