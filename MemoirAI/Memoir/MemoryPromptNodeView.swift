
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
    /// When true, this prompt is answered separately for each child in `Profile.childNames`.
    /// The text carries `{kid}` as a placeholder.
    var isPerChild: Bool = false
}



struct Chapter: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    var prompts: [MemoryPrompt]
}

let testChapter = Chapter(
    number: 1,
    title: "Beginnings",
    prompts: [
        MemoryPrompt(text: "What was one of your funniest childhood memories?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "Tell me a childhood story where you learned a lesson", x: 0.40, y: 0.62),
        MemoryPrompt(text: "Tell me about an early memory that reveals something about your personality.", x: 0.35, y: 0.44),
        MemoryPrompt(text: "What type of kid were you? Do you have any memories that best show who you were?", x: 0.50, y: 0.28)
    ]
)


import SwiftUI

struct MemoryPromptNodeView: View {
    let prompt: MemoryPrompt
    let isCompleted: Bool
    let isLocked: Bool
    let isSelected: Bool
    /// How many child variants this slot contains. 1 = single node, >1 = stacked discs with count badge.
    var childCount: Int = 1
    /// How many of the child variants have been recorded. Drives partial-progress styling.
    var completedChildCount: Int = 0

    let greenColor = Color.green
    let micColor = Color(red: 0.88, green: 0.52, blue: 0.28)
    let brownBorder = Color(red: 101/255, green: 69/255, blue: 44/255) // warm brown

    var body: some View {
        ZStack {
            // Stacked background discs for per-child slots.
            if childCount > 1 {
                ForEach(Array((0..<min(2, childCount - 1)).reversed()), id: \.self) { i in
                    let step = i + 1
                    Circle()
                        .fill(circleColor.opacity(0.55 - Double(i) * 0.15))
                        .frame(width: 60, height: 60)
                        .offset(x: CGFloat(step) * 5, y: CGFloat(step) * 5)
                        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                }
            }

            // Main disc
            Circle()
                .fill(circleColor)
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(iconColor)
        }
        .overlay(
            Circle()
                .stroke(borderColor, lineWidth: 3)
                .frame(width: 72, height: 72)
        )
        .overlay(alignment: .topTrailing) {
            if childCount > 1 {
                Text("\(completedChildCount)/\(childCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.78))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1.2))
                    .offset(x: 14, y: -10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected || isCompleted)
    }

    // Background color of the circle
    var circleColor: Color {
        if isLocked {
            return Color.gray.opacity(0.3)
        } else if isCompleted {
            return greenColor
        } else {
            return micColor
        }
    }

    // Icon inside the circle
    var iconName: String {
        if isLocked {
            return "lock.fill"
        } else if isCompleted {
            return "checkmark"
        } else {
            return "mic.fill"
        }
    }

    // Icon color
    var iconColor: Color {
        return .white
    }

    // Border color
    var borderColor: Color {
        if isCompleted {
            return brownBorder
        } else if isSelected {
            return Color.orange
        } else {
            return Color.clear
        }
    }
}
