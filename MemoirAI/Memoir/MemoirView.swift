import SwiftUI

// MARK: - Custom Serif Font Fallback
extension Font {
    static func customSerifFallback(size: CGFloat) -> Font {
        let fontNames = [
            "Georgia-Bold", "NewYork-Bold", "Palatino-Bold",
            "TimesNewRomanPS-BoldMT", "Charter-Bold"
        ]
        for name in fontNames {
            if UIFont(name: name, size: size) != nil {
                return Font.custom(name, size: size)
            }
        }
        return .system(size: size, weight: .bold, design: .serif)
    }
}

// MARK: - Updated Color Theme (from final screenshot palette)
struct ColorTheme {
    let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)       // #fdeac6
    let terracotta = Color(red: 210/255, green: 112/255, blue: 45/255)       // #d2702d
    let warmGreen = Color(red: 169/255, green: 175/255, blue: 133/255)       // reused
    let deepGreen = Color(red: 39/255, green: 60/255, blue: 34/255)          // #273c22
    let fadedGray = Color(red: 233/255, green: 204/255, blue: 158/255)       // #e9cc9e
    let lockGray = Color(red: 233/255, green: 204/255, blue: 158/255)        // reused
    let tileBackground = Color(red: 255/255, green: 241/255, blue: 213/255)  // #fff1d5
}

struct MemoirView: View {
    let colors = ColorTheme()
    @State private var currentChapter = 3
    @State private var completedChapters = 3
    @State private var totalChapters = 10

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // 🌸 HEADER
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

                            Text("\(completedChapters) of \(totalChapters) chapters completed")
                                .font(.subheadline)
                                .foregroundColor(colors.deepGreen)

                            Text("2 of 4 memories recorded")
                                .font(.subheadline)
                                .foregroundColor(colors.deepGreen)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)

                        // 📘 CURRENT CHAPTER CARD
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(colors.terracotta)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Chapter 3 – Falling in Love")
                                        .font(.headline)
                                        .foregroundColor(colors.deepGreen)
                                    Text("2 of 4 memories recorded")
                                        .font(.subheadline)
                                        .foregroundColor(colors.deepGreen)
                                }
                            }

                            NavigationLink(destination: ChapterJourneyView(chapter: testChapter)) {
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
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 6)
                        .padding(.horizontal)

                        // 📚 SECTION TITLE
                        Text("All Chapters")
                            .font(.headline)
                            .foregroundColor(colors.deepGreen)
                            .padding(.horizontal)
                            .padding(.top, 12)

                        // 📚 ALL CHAPTERS GRID
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(1...10, id: \.self) { index in
                                NavigationLink(destination: ChapterJourneyView(chapter: getMockChapter(index))) {
                                    ChapterTileView(
                                        chapterNumber: index,
                                        title: getChapterTitle(index),
                                        isLocked: index > completedChapters + 1,
                                        isCurrent: index == currentChapter,
                                        isCompleted: index <= completedChapters && index != currentChapter,
                                        colors: colors
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 100)
                    }
                }

                // 🎙️ STICKY MIC BUTTON
                Button(action: {
                    // Start new memory
                }) {
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("Tell a Story")
                            .bold()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(colors.terracotta)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 4)
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .background(colors.softCream.ignoresSafeArea())
        }
    }


    // Chapter Titles
    func getChapterTitle(_ index: Int) -> String {
        let titles = [
            "Childhood", "First Job", "Falling in Love", "Parenthood",
            "Life Lessons", "Faith and Doubts", "Career Journey",
            "Hard Times", "Triumphs", "Legacy"
        ]
        return titles.indices.contains(index - 1) ? titles[index - 1] : "Chapter \(index)"
    }
    func getMockChapter(_ index: Int) -> Chapter {
        let samplePrompts = [
            ("How did you meet?", 0.88, 0.80),
            ("What drew you to them?",               0.55, 0.63),
            ("What was your first date story?",         0.85, 0.43),
            ("When did you know it was love?",              0.68, 0.28)
        ]

        return Chapter(
            number: index,
            title: getChapterTitle(index),
            prompts: samplePrompts.map { MemoryPrompt(text: $0.0, x: $0.1, y: $0.2) }
        )
    }


}

// MARK: - Chapter Tile View
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
                Image(systemName: iconName)
                    .foregroundColor(iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Chapter \(chapterNumber)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(iconColor)

                    Text(title)
                        .font(.caption)
                        .foregroundColor(isLocked ? colors.lockGray : colors.deepGreen)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(colors.tileBackground)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }

    private var iconName: String {
        if isLocked { return "lock.fill" }
        if isCurrent { return "circle.fill" }
        if isCompleted { return "checkmark" }
        return "book"
    }

    private var iconColor: Color {
        if isLocked { return colors.lockGray }
        if isCurrent { return colors.warmGreen }
        return colors.deepGreen
    }
}
