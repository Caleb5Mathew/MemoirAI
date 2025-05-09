import SwiftUI
import CoreData

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

// MARK: - Updated Color Theme
struct ColorTheme {
    let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)
    let terracotta = Color(red: 210/255, green: 112/255, blue: 45/255)
    let warmGreen = Color(red: 169/255, green: 175/255, blue: 133/255)
    let deepGreen = Color(red: 39/255, green: 60/255, blue: 34/255)
    let fadedGray = Color(red: 233/255, green: 204/255, blue: 158/255)
    let lockGray = Color(red: 233/255, green: 204/255, blue: 158/255)
    let tileBackground = Color(red: 255/255, green: 241/255, blue: 213/255)
}

struct MemoirView: View {
    let colors = ColorTheme()

    @EnvironmentObject var profileVM: ProfileViewModel // Added to access selected profile

    private let totalChapters = allChapters.count

    @State private var entries: [MemoryEntry] = [] // Use @State for manually fetched entries

    // Fetch entries for the selected profile
    private func fetchEntries() {
        let fetchRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        
        // Safely unwrap the profile ID and set predicate
        let profileID = profileVM.selectedProfile.id
        fetchRequest.predicate = NSPredicate(format: "profileID == %@", profileID as CVarArg)


        fetchRequest.sortDescriptors = []
        do {
            entries = try PersistenceController.shared.container.viewContext.fetch(fetchRequest)
        } catch {
            print("Failed to fetch entries: \(error)")
        }
    }

    var firstIncompleteChapter: Chapter? {
        allChapters.first(where: { entriesForChapter($0).count < $0.prompts.count })
    }

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

                            Text("\(completedChaptersCount()) of \(totalChapters) chapters completed")
                                .font(.subheadline)
                                .foregroundColor(colors.deepGreen)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)

                        // 📘 CURRENT CHAPTER CARD (dynamic)
                        if let chapter = firstIncompleteChapter {
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

                                NavigationLink(destination: ChapterJourneyView(chapter: getMockChapter(chapter.number))) {
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
                        }

                        // 📚 SECTION TITLE
                        Text("All Chapters")
                            .font(.headline)
                            .foregroundColor(colors.deepGreen)
                            .padding(.horizontal)
                            .padding(.top, 12)

                        // 📚 ALL CHAPTERS GRID
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(allChapters, id: \.number) { chapter in
                                let entryCount = entriesForChapter(chapter).count
                                let isCompleted = entryCount >= chapter.prompts.count

                                NavigationLink(destination: ChapterJourneyView(chapter: getMockChapter(chapter.number)).environmentObject(profileVM))
                                {
                                    ChapterTileView(
                                        chapterNumber: chapter.number,
                                        title: chapter.title,
                                        isLocked: false, // ✅ all chapters unlocked
                                        isCurrent: false, // ✅ simplified
                                        isCompleted: isCompleted,
                                        colors: colors
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 100)
                    }
                }
            }
            .background(colors.softCream.ignoresSafeArea())
            .onAppear {
                fetchEntries() // Fetch entries when the view appears
            }
        }
    }

    // MARK: - Helpers

    func completedChaptersCount() -> Int {
        allChapters.filter { entriesForChapter($0).count >= $0.prompts.count }.count
    }

    func entriesForChapter(_ chapter: Chapter) -> [MemoryEntry] {
        return entries.filter {
            ($0.chapter ?? "") == chapter.title &&
            chapter.prompts.map { $0.text }.contains($0.prompt ?? "")
        }
    }

    func getMockChapter(_ index: Int) -> Chapter {
        let chapter = allChapters.first { $0.number == index }!
        let coordinates: [(CGFloat, CGFloat)] = [
            (0.88, 0.80), (0.55, 0.63), (0.85, 0.43), (0.68, 0.28)
        ]

        let prompts = zip(chapter.prompts, coordinates).map { prompt, coord in
            MemoryPrompt(text: prompt.text, x: coord.0, y: coord.1)
        }

        return Chapter(number: chapter.number, title: chapter.title, prompts: prompts)
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
                        .foregroundColor(colors.deepGreen)
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
        if isCompleted { return "checkmark" }
        return "book"
    }

    private var iconColor: Color {
        if isCompleted { return colors.deepGreen }
        return colors.deepGreen
    }
}
