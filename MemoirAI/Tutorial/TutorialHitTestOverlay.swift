//
//  TutorialHitTestOverlay.swift
//  MemoirAI
//
//  Full-screen invisible overlay that blocks touches except in a "hole" (global rect),
//  so underlying controls remain tappable only where the tutorial highlights.
//

import SwiftUI
import UIKit

/// How the invisible hit-test layer should behave.
enum TutorialHitTestMode: Equatable {
    /// Block all touches (e.g. home intro — user uses tooltip only).
    case blockAll
    /// Let touches pass through everywhere (e.g. anchor not laid out yet — user can scroll).
    case passThroughAll
    /// Block touches outside the given rect (global coordinates).
    case hole(CGRect)
}

/// Invisible UIView that participates in hit-testing only.
final class TutorialHitTestHostView: UIView {
    var mode: TutorialHitTestMode = .blockAll

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        switch mode {
        case .blockAll:
            return true
        case .passThroughAll:
            return false
        case .hole(let globalRect):
            let localHole = convert(globalRect, from: nil)
            return !localHole.contains(point)
        }
    }
}

struct TutorialHitTestOverlay: UIViewRepresentable {
    var mode: TutorialHitTestMode

    func makeUIView(context: Context) -> TutorialHitTestHostView {
        let v = TutorialHitTestHostView()
        v.backgroundColor = .clear
        v.isOpaque = false
        return v
    }

    func updateUIView(_ uiView: TutorialHitTestHostView, context: Context) {
        uiView.mode = mode
    }
}
