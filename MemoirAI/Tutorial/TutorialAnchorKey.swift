//
//  TutorialAnchorKey.swift
//  MemoirAI
//

import SwiftUI

/// Collects global frames for tutorial spotlight targets from descendant views.
struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [TutorialStep: CGRect] = [:]

    static func reduce(value: inout [TutorialStep: CGRect], nextValue: () -> [TutorialStep: CGRect]) {
        let next = nextValue()
        for (step, rect) in next {
            if let existing = value[step] {
                value[step] = existing.union(rect)
            } else {
                value[step] = rect
            }
        }
    }
}

extension View {
    /// Registers this view’s bounds as the spotlight target for a tutorial step (global coordinates).
    func tutorialAnchor(_ step: TutorialStep) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TutorialAnchorKey.self,
                    value: [step: geo.frame(in: .global)]
                )
            }
        )
    }

    /// Registers a tutorial anchor only when `condition` is true (e.g. first chapter tile).
    func tutorialAnchor(_ step: TutorialStep, when condition: Bool) -> some View {
        Group {
            if condition {
                self.tutorialAnchor(step)
            } else {
                self
            }
        }
    }
}
