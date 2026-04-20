import SwiftUI

struct QuestionGeneratorSheet: View {
    let chapterTitle: String
    let onUse: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var generatedQuestion: String = ""
    @State private var isGenerating = false
    @State private var generateCount = 0
    @State private var showError = false

    private let maxGenerations = 30
    private let terracotta = Color(red: 210/255, green: 112/255, blue: 45/255)
    private let cream = Color(red: 253/255, green: 234/255, blue: 198/255)
    private let darkGreen = Color(red: 0.07, green: 0.21, blue: 0.13)

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            VStack(spacing: 28) {
                header
                questionCard
                actionButtons
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
            .padding(.top, 8)
        }
        .background(Color.white)
        .task { await generateQuestion() }
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(chapterTitle.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(terracotta)
            Text("New Question")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(darkGreen)
        }
    }

    private var questionCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(cream)

            if isGenerating {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: terracotta))
                        .scaleEffect(1.2)
                    Text("Finding a question for you…")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .padding(32)
            } else if showError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(terracotta)
                    Text("Couldn't generate a question.\nCheck your connection and try again.")
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                }
                .padding(32)
            } else {
                Text(generatedQuestion)
                    .font(.custom("Georgia", size: 18))
                    .foregroundColor(darkGreen)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
            }
        }
        .frame(minHeight: 140)
        .animation(.easeInOut(duration: 0.2), value: isGenerating)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                onUse(generatedQuestion)
                dismiss()
            } label: {
                Text("Use This Question")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(generatedQuestion.isEmpty || isGenerating ? Color.gray.opacity(0.4) : terracotta)
                    )
            }
            .disabled(generatedQuestion.isEmpty || isGenerating)

            HStack(spacing: 20) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
                }

                Button {
                    Task { await generateQuestion() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .rotationEffect(.degrees(isGenerating ? 360 : 0))
                            .animation(isGenerating ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isGenerating)
                        Text("Try Another")
                            .font(.system(size: 15))
                    }
                    .foregroundColor(canRegenerate ? terracotta : Color.gray.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canRegenerate ? terracotta.opacity(0.08) : Color.clear)
                    )
                }
                .disabled(!canRegenerate)
            }
        }
    }

    private var canRegenerate: Bool {
        !isGenerating && generateCount < maxGenerations
    }

    private func generateQuestion() async {
        guard generateCount < maxGenerations else { return }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
              key.hasPrefix("sk-") else { return }

        isGenerating = true
        showError = false

        let systemPrompt = """
        You generate warm, specific memoir questions for elderly people. The question MUST:
        - Fit the chapter theme: \(chapterTitle)
        - Be answerable with a specific memory, story, or moment (not a general life philosophy)
        - Paint a scene that could be illustrated — a place, a person, an action
        - Be gentle and easy to answer (avoid heavy trauma or abstract reflection)
        - Be one concise sentence, ending with a question mark
        Return ONLY the question — no quotes, no intro text, nothing else.
        """

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Give me one memoir question for the \(chapterTitle) chapter."]
            ],
            "max_tokens": 80,
            "temperature": 0.9
        ]

        do {
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                showError = true
                isGenerating = false
                return
            }

            struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
            struct Root: Decodable { let choices: [Choice] }
            let question = try JSONDecoder().decode(Root.self, from: data)
                .choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            generatedQuestion = question.isEmpty ? "Tell me about a moment from your \(chapterTitle.lowercased()) that you still think about today." : question
            generateCount += 1
        } catch {
            showError = true
        }

        isGenerating = false
    }
}
