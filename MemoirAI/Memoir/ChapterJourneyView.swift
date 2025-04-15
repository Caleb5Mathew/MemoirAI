import SwiftUI

struct ChapterJourneyView: View {
    let chapter: Chapter
    @Environment(\.dismiss) var dismiss

    @State private var selectedPrompt: MemoryPrompt?
    @State private var completedPromptIDs: Set<UUID> = []
    @Namespace private var zoomNamespace // Shared animation namespace

    let highlightColor = Color(red: 254/255, green: 242/255, blue: 215/255) // #fef2d7
    let deepGreen = Color(red: 39/255, green: 60/255, blue: 34/255)         // #273c22

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 🌄 Background image
                Image(chapter.title.lowercased())
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                // 🎤 Microphone prompt buttons
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

                // 📝 Centered title and subtitle at top
                VStack(spacing: 8) {
                    Text("Chapter \(chapter.number) – \(chapter.title)")
                        .font(.customSerifFallback(size: 28))
                        .foregroundColor(deepGreen)
                        .multilineTextAlignment(.center)

                    Text("\(completedPromptIDs.count) of \(chapter.prompts.count) memories recorded")
                        .font(.subheadline)
                        .foregroundColor(deepGreen)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
                .offset(x: -geo.size.width * 0.085)
                .frame(maxHeight: .infinity, alignment: .top)

                // 🔙 Back button top-left
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black)
                        .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // 💬 Floating prompt quote
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
            .navigationBarBackButtonHidden(true)
            .fullScreenCover(item: $selectedPrompt) { prompt in
                RecordingView(prompt: prompt, chapterTitle: chapter.title, namespace: zoomNamespace)
            }
        }
        .onAppear {
            completedPromptIDs = Set() // All prompts unlocked
        }
    }
}
