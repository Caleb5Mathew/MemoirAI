//
//  TutorialCoachMarkLayer.swift
//  MemoirAI
//

import SwiftUI

/// Full-screen coach marks: dim + spotlight hole + pulsing ring + tooltip (Skip always available).
/// Touches pass through only inside the highlighted region so users can tap the real control.
struct TutorialCoachMarkLayer: View {
    @EnvironmentObject var tutorial: TutorialCoordinator
    let anchors: [TutorialStep: CGRect]
    @EnvironmentObject var profileVM: ProfileViewModel

    private let cornerRadius: CGFloat = 14
    private let ringInset: CGFloat = 6

    @State private var pulseRing = false

    var body: some View {
        Group {
            if tutorial.isTutorialActive {
                GeometryReader { geo in
                    let safeFrame = geo.frame(in: .global)
                    let step = tutorial.currentStep
                    let globalHole = globalHoleRect(for: step)
                    let localHole = globalHole.map { $0.offsetBy(dx: -safeFrame.minX, dy: -safeFrame.minY) }
                    let hitMode = hitTestMode(step: step, globalHole: globalHole)

                    ZStack(alignment: .topLeading) {
                        // Visual dim + cutout
                        if let lh = localHole {
                            spotlightHole(full: CGRect(origin: .zero, size: geo.size), hole: lh)
                                .allowsHitTesting(false)

                            // Pulsing ring so the tap target is obvious even before interaction
                            RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                                .stroke(Color(red: 0.83, green: 0.45, blue: 0.14).opacity(0.95), lineWidth: 3)
                                .frame(width: lh.width + ringInset * 2, height: lh.height + ringInset * 2)
                                .position(x: lh.midX, y: lh.midY)
                                .id(tutorial.currentStep)
                                .scaleEffect(pulseRing ? 1.03 : 1.0)
                                .opacity(pulseRing ? 1.0 : 0.82)
                                .animation(
                                    .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                                    value: pulseRing
                                )
                                .allowsHitTesting(false)
                        } else if step == .homeIntro {
                            Color.black.opacity(0.5)
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                        } else {
                            // Interactive step but anchor not ready yet — light dim, still readable
                            Color.black.opacity(0.35)
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                        }

                        // Invisible layer: block outside the hole so stray taps don’t fire elsewhere
                        TutorialHitTestOverlay(mode: hitMode)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(true)

                        VStack {
                            Spacer()
                            tooltipCard(for: step)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 32)
                        }
                        .zIndex(100)
                        .allowsHitTesting(true)
                    }
                    .onAppear {
                        pulseRing = true
                    }
                    .onChange(of: tutorial.currentStep) { _, _ in
                        pulseRing = true
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
    }

    // MARK: - Geometry

    private func globalHoleRect(for step: TutorialStep) -> CGRect? {
        if step == .homeIntro { return nil }
        guard let r = anchors[step] else {
            return nil
        }
        return r.insetBy(dx: -ringInset, dy: -ringInset)
    }

    private func stepNeedsInteractiveAnchor(_ step: TutorialStep) -> Bool {
        switch step {
        case .homeContinueMemoir, .memoirPickChapter, .chapterPickPrompt, .recordingSaveMemory, .homeYourBook, .storybookCreate:
            return true
        case .homeIntro, .none, .finished:
            return false
        }
    }

    private func hitTestMode(step: TutorialStep, globalHole: CGRect?) -> TutorialHitTestMode {
        if step == .homeIntro {
            return .blockAll
        }
        if stepNeedsInteractiveAnchor(step) {
            if let h = globalHole {
                return .hole(h)
            }
            return .passThroughAll
        }
        return .passThroughAll
    }

    private func spotlightHole(full: CGRect, hole: CGRect) -> some View {
        Path { path in
            path.addRect(full)
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        }
        .fill(style: FillStyle(eoFill: true))
        .foregroundColor(Color.black.opacity(0.52))
    }

    // MARK: - Tooltip

    @ViewBuilder
    private func tooltipCard(for step: TutorialStep) -> some View {
        let profileID = profileVM.selectedProfile.id
        VStack(alignment: .leading, spacing: 12) {
            Text(title(for: step))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Color(red: 0.1, green: 0.15, blue: 0.12))

            Text(subtitle(for: step))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Skip tutorial") {
                    tutorial.skipTutorial(profileID: profileID)
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

                Spacer()

                if showsBack(for: step) {
                    Button("Back") {
                        goBack(from: step, profileID: profileID)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                if showsPrimary(for: step) {
                    Button(primaryTitle(for: step)) {
                        primaryAction(step: step, profileID: profileID)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.83, green: 0.45, blue: 0.14))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.99, green: 0.97, blue: 0.94))
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
        )
    }

    private func title(for step: TutorialStep) -> String {
        switch step {
        case .homeIntro:
            return "Welcome — quick tour"
        case .homeContinueMemoir:
            return "Your chapters"
        case .memoirPickChapter:
            return "Pick a chapter"
        case .chapterPickPrompt:
            return "Choose a memory"
        case .recordingSaveMemory:
            return "Save your memory"
        case .homeYourBook:
            return "Your AI storybook"
        case .storybookCreate:
            return "Create your storybook"
        case .none, .finished:
            return ""
        }
    }

    private func subtitle(for step: TutorialStep) -> String {
        switch step {
        case .homeIntro:
            return "In about a minute you’ll record one memory, then see how it becomes a beautiful book page. You can leave anytime with Skip."
        case .homeContinueMemoir:
            return "Tap Continue Your Memoir to open your chapter map."
        case .memoirPickChapter:
            return "Tap any chapter to open it. We’ll use the prompts inside to record."
        case .chapterPickPrompt:
            return "Tap a glowing prompt to record (or replay a finished one)."
        case .recordingSaveMemory:
            return "Record or type, then tap Save (or Stop & Save). This step completes automatically when your memory is saved."
        case .homeYourBook:
            return "Tap Your Book to generate illustrated pages from your memories."
        case .storybookCreate:
            return "Tap Create My Storybook. If you’ve used your free previews, you still get one bonus generation from this tour."
        case .none, .finished:
            return ""
        }
    }

    private func showsBack(for step: TutorialStep) -> Bool {
        switch step {
        case .homeIntro:
            return false
        default:
            return true
        }
    }

    private func showsPrimary(for step: TutorialStep) -> Bool {
        switch step {
        case .homeIntro, .storybookCreate:
            return true
        default:
            return false
        }
    }

    private func primaryTitle(for step: TutorialStep) -> String {
        switch step {
        case .homeIntro:
            return "Next"
        case .storybookCreate:
            return "Done"
        default:
            return "Next"
        }
    }

    private func primaryAction(step: TutorialStep, profileID: UUID) {
        switch step {
        case .homeIntro:
            tutorial.nextFromHomeIntro(profileID: profileID)
        case .storybookCreate:
            tutorial.finishStorybookTutorialStep(profileID: profileID)
        default:
            break
        }
    }

    private func goBack(from step: TutorialStep, profileID: UUID) {
        switch step {
        case .homeContinueMemoir:
            tutorial.goToStep(.homeIntro, profileID: profileID)
        case .memoirPickChapter:
            tutorial.goToStep(.homeContinueMemoir, profileID: profileID)
        case .chapterPickPrompt:
            tutorial.goToStep(.memoirPickChapter, profileID: profileID)
        case .recordingSaveMemory:
            tutorial.goToStep(.chapterPickPrompt, profileID: profileID)
        case .homeYourBook:
            tutorial.goToStep(.recordingSaveMemory, profileID: profileID)
        case .storybookCreate:
            tutorial.goToStep(.homeYourBook, profileID: profileID)
        default:
            break
        }
    }
}
