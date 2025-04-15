//
//  MemoryPromptNodeView.swift
//  MemoirAI
//
//  Created by user941803 on 4/14/25.
//
struct MemoryPrompt: Identifiable {
    let id: UUID = UUID()
    let text: String
    let x: CGFloat // % of screen width (0 to 1)
    let y: CGFloat // % of screen height (0 to 1)
    var isCompleted: Bool = false
}



struct Chapter: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    var prompts: [MemoryPrompt]
}

let testChapter = Chapter(
    number: 1,
    title: "Childhood",
    prompts: [
        MemoryPrompt(text: "How did you meet?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "What drew you to them?", x: 0.40, y: 0.62),
        MemoryPrompt(text: "First date story?", x: 0.35, y: 0.44),
        MemoryPrompt(text: "When did you know it was love?", x: 0.50, y: 0.28)
    ]
)



import SwiftUI

struct MemoryPromptNodeView: View {
    let prompt: MemoryPrompt
    let isCompleted: Bool
    let isLocked: Bool
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(circleColor)
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
        }
        .overlay(
            Circle()
                .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 3)
                .frame(width: 72, height: 72)
        )
        .animation(.easeInOut, value: isSelected)
    }

    var circleColor: Color {
        if isLocked {
            return Color.gray.opacity(0.3)
        } else if isCompleted {
            return Color.green
        } else {
            return Color(red: 0.88, green: 0.52, blue: 0.28) // warm orange
        }
    }

    var iconName: String {
        if isLocked { return "lock.fill" }
        if isCompleted { return "checkmark" }
        return "mic.fill"
    }
}
