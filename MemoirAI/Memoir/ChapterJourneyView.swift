import SwiftUI

struct ChapterJourneyView: View {
    let chapter: Chapter

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var context
    @EnvironmentObject var profileVM: ProfileViewModel

    @FetchRequest(
        entity: MemoryEntry.entity(),
        sortDescriptors: []
    ) var allEntries: FetchedResults<MemoryEntry>

    @State private var selectedPrompt: MemoryPrompt?
    @State private var refreshID = UUID() // Forces full rerender
    @Namespace private var zoomNamespace

    let highlightColor = Color(red: 254/255, green: 242/255, blue: 215/255)
    let deepGreen = Color(red: 39/255, green: 60/255, blue: 34/255)

    var completedPromptIDs: Set<UUID> {
        let entriesForCurrentProfile = allEntries.filter { $0.profileID == profileVM.selectedProfile.id }
        let savedPromptPairs = entriesForCurrentProfile.map { ($0.prompt ?? "", $0.chapter ?? "") }

        return Set(
            chapter.prompts
                .filter { prompt in
                    savedPromptPairs.contains(where: { $0 == (prompt.text, chapter.title) })
                }
                .map { $0.id }
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Image(chapter.title.lowercased())
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                // Prompt Nodes
                ForEach(chapter.prompts) { prompt in
                    let isCompleted = completedPromptIDs.contains(prompt.id)

                    MemoryPromptNodeView(
                        prompt: prompt,
                        isCompleted: isCompleted,
                        isLocked: false,
                        isSelected: prompt.id == selectedPrompt?.id
                    )
                    .matchedGeometryEffect(id: prompt.id, in: zoomNamespace)
                    .position(
                        x: prompt.x * geo.size.width,
                        y: prompt.y * geo.size.height
                    )
                    .onTapGesture {
                        withAnimation(.spring()) {
                            selectedPrompt = prompt
                        }
                    }
                }

                // Title
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.35))
                        .padding(.horizontal, 24)
                        .frame(height: 80)

                    VStack(spacing: 8) {
                        Text("Chapter \(chapter.number) – \(chapter.title)")
                            .font(.customSerifFallback(size: 28))
                            .foregroundColor(deepGreen)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\(completedPromptIDs.count) of \(chapter.prompts.count) memories recorded")
                            .font(.subheadline)
                            .foregroundColor(deepGreen)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.top, 50)
                .offset(x: -geo.size.width * 0.085)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // Back Button
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black)
                        .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Floating Prompt Quote
                if let selectedPrompt = selectedPrompt {
                    HStack {
                        Spacer(minLength: 24)
                        Text("\"\(selectedPrompt.text)\"")
                            .font(.system(size: 17, weight: .medium))
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .background(highlightColor)
                            .cornerRadius(20)
                            .shadow(radius: 4)
                        Spacer(minLength: 24)
                    }
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.move(edge: .bottom))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .onAppear {
                // No longer hiding TabBar here
            }
            .navigationBarBackButtonHidden(true)
            .fullScreenCover(item: $selectedPrompt) { prompt in
                RecordingView(prompt: prompt, chapterTitle: chapter.title, namespace: zoomNamespace)
                    .environmentObject(profileVM) // Inject profileVM here
                    .id(prompt.id) // Keeps animations fresh
                    .onDisappear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            refreshID = UUID()
                        }
                    }
            }
        }
        .id(refreshID) // Forces a re-render when refreshed
    }
}
