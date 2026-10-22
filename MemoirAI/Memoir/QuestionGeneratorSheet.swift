import SwiftUI

struct MemoirQuestionGenerationRequest {
    let systemPrompt: String
    let userPrompt: String
    let fallbackQuestion: String
}

enum MemoirQuestionGenerationPolicy {
    static func request(chapterTitle: String, memoirMode: MemoirMode) -> MemoirQuestionGenerationRequest {
        let chapters: [Chapter]
        let purpose: String
        switch memoirMode {
        case .normal:
            chapters = allChapters
            purpose = "Help someone tell a clear story from their own life."
        case .parent:
            chapters = allParentChapters
            purpose = "Help a parent share their life, love, and perspective with their children."
        case .relationships:
            chapters = allRelationshipChapters
            purpose = "Help someone tell a warm, specific story about an important relationship."
        }

        let examples = chapters
            .first(where: { $0.title == chapterTitle })?
            .prompts
            .map(\.text)
            .joined(separator: "\n- ") ?? ""

        let systemPrompt = """
        Write one memoir question for the chapter “\(chapterTitle).”

        Purpose: \(purpose)

        The question must:
        - Ask for one specific memory, moment, person, place, or ordinary experience.
        - Use plain, natural language that is immediately clear when read aloud.
        - Be easy to begin answering without needing to find the perfect, first, best, biggest, or most important memory.
        - Invite a story with concrete details while asking only one main thing.
        - Be concise: preferably 8–18 words and never more than 24 words.
        - Fit the chapter without repeating any example below.
        - Avoid abstract philosophy, therapy language, assumptions, and vague phrases such as “that you still reach for today.”
        - Avoid tangled constructions such as “the first place you remember remembering.”
        - End with one question mark.

        Existing questions in this chapter:
        - \(examples)

        Return only the question.
        """

        return MemoirQuestionGenerationRequest(
            systemPrompt: systemPrompt,
            userPrompt: "Write one new, simple question for the \(chapterTitle) chapter.",
            fallbackQuestion: "What is one small moment from this part of your life that you remember clearly?"
        )
    }
}

struct QuestionGeneratorSheet: View {
    let chapterTitle: String
    var memoirMode: MemoirMode = currentMemoirMode()
    let onUse: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var generatedQuestion: String = ""
    @State private var isGenerating = false
    @State private var generateCount = 0
    @State private var showError = false

    private let maxGenerations = 30
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
        .background(LinenTheme.paper)
        .task { await generateQuestion() }
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(LinenTheme.line)
            .frame(width: 36, height: 5)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(chapterTitle.uppercased())
                .font(LinenTheme.body(11, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(LinenTheme.accent)
            Text("New Question")
                .font(LinenTheme.heading(24))
                .foregroundColor(LinenTheme.ink)
        }
    }

    private var questionCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinenTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(LinenTheme.line, lineWidth: 1)
                )

            if isGenerating {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: LinenTheme.accent))
                        .scaleEffect(1.2)
                    Text("Finding a question for you…")
                        .font(LinenTheme.body(14))
                        .foregroundColor(LinenTheme.secondary)
                }
                .padding(32)
            } else if showError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(LinenTheme.accent)
                    Text("Couldn't generate a question.\nCheck your connection and try again.")
                        .font(LinenTheme.body(14))
                        .multilineTextAlignment(.center)
                        .foregroundColor(LinenTheme.secondary)
                }
                .padding(32)
            } else {
                Text(generatedQuestion)
                    .font(LinenTheme.heading(20))
                    .foregroundColor(LinenTheme.ink)
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
                    .font(LinenTheme.body(16, weight: .semibold))
                    .foregroundColor(LinenTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(generatedQuestion.isEmpty || isGenerating ? LinenTheme.line : LinenTheme.forest)
                    )
            }
            .disabled(generatedQuestion.isEmpty || isGenerating)

            HStack(spacing: 20) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(LinenTheme.body(15, weight: .medium))
                        .foregroundColor(LinenTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(LinenTheme.surface))
                }

                Button {
                    Task { await generateQuestion() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(LinenTheme.body(13, weight: .semibold))
                            .rotationEffect(.degrees(isGenerating ? 360 : 0))
                            .animation(isGenerating ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isGenerating)
                        Text("Try Another")
                            .font(LinenTheme.body(15, weight: .medium))
                    }
                    .foregroundColor(canRegenerate ? LinenTheme.accent : LinenTheme.secondary.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canRegenerate ? LinenTheme.accent.opacity(0.08) : Color.clear)
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

        isGenerating = true
        showError = false

        let request = MemoirQuestionGenerationPolicy.request(
            chapterTitle: chapterTitle,
            memoirMode: memoirMode
        )

        do {
            let result = try await AIProxyService.shared.chatCompletion(
                model: "gpt-5-mini",
                messages: [
                    ["role": "system", "content": request.systemPrompt],
                    ["role": "user", "content": request.userPrompt]
                ],
                temperature: 0.9,
                maxTokens: 80
            )

            let question = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            generatedQuestion = question.isEmpty ? request.fallbackQuestion : question
            generateCount += 1
        } catch {
            showError = true
        }

        isGenerating = false
    }
}
