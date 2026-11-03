import AVFoundation
import FirebaseAuth
import Mixpanel
import OSLog
import SwiftUI
import UIKit

// Entering the app and successfully completing onboarding are separate outcomes.
enum OnboardingCompletionPolicy {
    enum Event { case finalContinueTapped, paywallDismissed }
    static func shouldComplete(after event: Event) -> Bool { event == .paywallDismissed }

    static func outcome(previewReady: Bool, offerPresented: Bool, entitlementActive: Bool) -> String {
        guard previewReady else { return "preview_unavailable" }
        if entitlementActive { return "entitled" }
        return offerPresented ? "offer_presented" : "offer_unavailable"
    }

    static func isSuccessful(_ outcome: String) -> Bool {
        outcome == "offer_presented" || outcome == "entitled"
    }

    static func replayStory(savedRequestID: String?, requestID: String, savedStory: String?, preparedStory: String) -> String {
        guard savedRequestID == requestID, let savedStory, !savedStory.isEmpty else { return preparedStory }
        return savedStory
    }
}

struct OnboardingColorTheme {
    let paper = Color(red: 247/255, green: 242/255, blue: 233/255)
    let ink = Color(red: 0.12, green: 0.16, blue: 0.13)
    let moss = Color(red: 0.22, green: 0.31, blue: 0.24)
    let rust = Color(red: 0.72, green: 0.31, blue: 0.13)
    let muted = Color(red: 0.43, green: 0.44, blue: 0.39)
    let beige = Color(red: 0.98, green: 0.94, blue: 0.86)
    let orange = Color(red: 0.83, green: 0.45, blue: 0.14)
    let deepGreen = Color(red: 39/255, green: 60/255, blue: 34/255)
    let fadedGray = Color(red: 233/255, green: 204/255, blue: 158/255)
}

private enum OnboardingStep: Int, CaseIterable {
    case audience, name, record, meetAlex, cover, spread, illustration, voice, story, building, reveal
}

struct OnboardingFlow: View {
    var onFinished: (() -> Void)? = nil
    @EnvironmentObject private var profileVM: ProfileViewModel
    @EnvironmentObject private var iCloudManager: iCloudManager
    @StateObject private var recorder = OnboardingRecorder()
    @StateObject private var sampleAudio = OnboardingSampleAudioPlayer()
    @StateObject private var memoryPreflight = OnboardingMemoryPreflight()

    @State private var availableSize = CGSize(width: 390, height: 780)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var layout: OnboardingLayoutMetrics {
        OnboardingLayoutMetrics(size: availableSize, accessibility: dynamicTypeSize.isAccessibilitySize)
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var didTrackCompletion = false
    @State private var wasBackgrounded = false
    @State private var analyticsFlowID = UUID().uuidString
    @State private var stepEnteredAt = Date()
    @State private var inputFieldsStarted: Set<String> = []
    @State private var inputMethod = "none"
    @State private var didTrackStart = false
    @State private var didTrackPresentation = false
    @State private var generationAttempt = 0
    @State private var didTrackReveal = false
    @State private var step: OnboardingStep = .audience
    @State private var session = OnboardingSession()
    @State private var storyDraft = ""
    @State private var previewImage: UIImage?
    @State private var restoredAudioURL: URL?
    @State private var restoredRawTranscript: String?
    @State private var readingCopy: String?
    @State private var generationFailure: String?
    @State private var previewRecovery: OnboardingPreviewRecovery = .retry
    @State private var offerPresented = false
    @State private var entitlementActive = false
    @State private var audioReady = false
    @State private var generationStage = "Preparing your first page"
    @State private var hasSubmittedMemory = false
    @State private var previewTitle = "A memory I carry"
    @State private var showPaywall = false
    @State private var showCloudDisclosure = false
    @State private var didWarmPreviewService = false
    @State private var isPreparingAccount = true
    @FocusState private var storyEditorFocused: Bool
    @State private var accountPreparationFailed = false
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generationStartedAt: Date?
    @State private var revealUnlocked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colors = OnboardingColorTheme()
    private let sessionStore = OnboardingSessionStore()
    private let draftStore = OnboardingDraftStore()
    private let editingDraftStore = StoryEditingDraftStore()
    @State private var editingOwner: String?
    @State private var editingProfileID: UUID?
    @State private var pendingEditingDraft: StoryEditingDraft?
    @State private var showEditingDraftRecovery = false
    @State private var editingDraftLoadFailed = false
    private var currentAudioURL: URL? { recorder.audioURL ?? restoredAudioURL }

    private var mainContent: some View {
        ZStack {
            colors.paper.ignoresSafeArea()
            if pendingEditingDraft == nil && !accountPreparationFailed {
                if step == .meetAlex {
                    meetAlex
                        .transition(.opacity)
                        .zIndex(1)
                } else {
                    VStack(spacing: 0) {
                        topBar
                        Group {
                            switch step {
                            case .meetAlex: EmptyView()
                            case .cover, .spread, .illustration, .voice, .story: alexBook(focus: alexFocus)
                            case .audience: audienceQuestion
                            case .name: nameQuestion
                            case .record: recordMemory
                            case .building, .reveal: personalizedReveal
                            }
                        }
                        .id(isBookTour ? "book-tour" : ([.building, .reveal].contains(step) ? "personal-page" : String(step.rawValue)))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.985)),
                            removal: .opacity
                        ))
                    }
                    .frame(maxWidth: isBookTour || step == .building || step == .reveal ? layout.bookContentWidth : layout.contentWidth)
                    .blur(radius: step == .building && !revealUnlocked ? 4 : 0)
                    .transition(.opacity)
                }
            }
            if pendingEditingDraft != nil && !showEditingDraftRecovery {
                colors.paper.ignoresSafeArea().zIndex(2)
                VStack(spacing: 20) {
                    Text("Your unfinished story is saved")
                        .font(.title2).fontWeight(.semibold)
                    Text("Continue it, or choose to discard it before starting another story.")
                        .font(.body).foregroundStyle(colors.muted)
                        .multilineTextAlignment(.center)
                    primaryButton("Continue saved story") { restoreEditingDraft() }
                    Button("Choose another story") { showEditingDraftRecovery = true }
                        .frame(minHeight: 44)
                }
                .padding(28)
                .zIndex(3)
            }
            if isPreparingAccount {
                colors.paper.opacity(0.8).ignoresSafeArea()
                ProgressView("Getting Memoir ready")
            }
            if step == .building && !revealUnlocked { buildingPage.transition(.opacity) }
            if accountPreparationFailed {
                colors.paper.ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Memoir couldn’t connect")
                        .font(.title2).fontWeight(.semibold)
                    Text(errorMessage ?? "Check your connection and try again.")
                        .font(.body).foregroundStyle(colors.muted)
                        .multilineTextAlignment(.center)
                    primaryButton("Reconnect") { Task { await prepareSession() } }
                }
                .padding(28)
            }
        }
    }

    private var observedContent: some View {
        mainContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { availableSize = $0 }
        .foregroundStyle(colors.ink)
        .animation(reduceMotion ? nil : (step == .meetAlex ? .easeInOut(duration: 0.45) : .spring(response: 0.55, dampingFraction: 0.88)), value: step)
        .analyticsScreen(String(describing: step))
        .task { await prepareSession() }
        .onDisappear { _ = recorder.stop(); persistEditingDraft(); sampleAudio.stop(); memoryPreflight.invalidate() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistEditingDraft() }
            guard didTrackStart, !didTrackCompletion else { return }
            if phase == .background {
                wasBackgrounded = true
                track("Onboarding Backgrounded", ["step_duration_ms": max(0, Int(Date().timeIntervalSince(stepEnteredAt) * 1000))])
            } else if phase == .active && wasBackgrounded {
                wasBackgrounded = false
                stepEnteredAt = Date()
                track("Onboarding Foregrounded")
            }
        }
        .onChange(of: inputReadiness) { _, readiness in
            if step == .record && !isPreparingAccount {
                track("Onboarding Input Readiness Changed", ["input_readiness": readiness.rawValue])
            }
        }
        .onChange(of: recorder.isRecording) { _, recording in
            track(recording ? "Onboarding Recording Started" : "Onboarding Recording Stopped", ["recording_duration": recorder.elapsed])
        }
        .onChange(of: sampleAudio.isPlaying) { _, playing in
            track(playing ? "Onboarding Sample Playback Started" : "Onboarding Sample Playback Stopped")
        }
        .onChange(of: storyDraft) { _, _ in memoryPreflight.invalidate(); persistEditingDraft() }
        .onChange(of: session.narratorName) { _, _ in memoryPreflight.invalidate(); persistEditingDraft() }
        .onChange(of: session.audience) { _, _ in memoryPreflight.invalidate(); persistEditingDraft() }
        .onChange(of: session.storyteller) { _, _ in memoryPreflight.invalidate(); persistEditingDraft() }
        .onChange(of: currentAudioURL) { _, _ in memoryPreflight.invalidate(); persistEditingDraft() }
        .onChange(of: recorder.liveTranscript) { _, value in
            if step == .record && recorder.audioURL != nil { storyDraft = value }
        }
        .onChange(of: recorder.isFinalizing) { _, finalizing in
            if !finalizing && recorder.audioURL != nil { storyDraft = recorder.liveTranscript }
        }
        .onChange(of: recorder.permissionOutcome) { _, outcome in
            if let outcome { track("Onboarding Recording Permission", ["permission_outcome": outcome]) }
        }
        .onChange(of: recorder.errorMessage) { _, value in
            if let value {
                errorMessage = value
                track("Onboarding Recording Failed", ["failure_stage": "recording"])
            }
        }
    }

    var body: some View {
        observedContent
        .fullScreenCover(isPresented: $showPaywall, onDismiss: finishAfterPaywall) {
            SubscriptionPaywallView(source: .onboarding, onOutcome: { outcome in
                switch outcome {
                case .presented:
                    offerPresented = true
                    track("Onboarding Offer Ready")
                    FacebookAnalytics.logPaywallViewed()
                case .entitlementActive:
                    entitlementActive = true
                case .dismissedWithoutOffer:
                    break
                }
            })
                .onAppear {
                    track("Onboarding Paywall Requested")
                }
        }
        .alert("Continue your first story?", isPresented: $showEditingDraftRecovery) {
            Button("Continue story") { restoreEditingDraft() }
            Button("Discard draft", role: .destructive) { discardEditingDraft() }
        } message: {
            Text("Your unsaved words and recording were kept on this device.")
        }
        .alert(CloudTranscriptionDisclosure.title, isPresented: $showCloudDisclosure) {
            Button("Continue") {
                track("Onboarding Recording Consent", ["consent_outcome": "accepted"])
                CloudTranscriptionDisclosure.accept()
                recorder.requestPermissionsAndStart()
            }
            Button("Not now", role: .cancel) { track("Onboarding Recording Consent", ["consent_outcome": "declined"]) }
        } message: { Text(CloudTranscriptionDisclosure.message) }
        .alert("Memoir needs a moment", isPresented: Binding<Bool>(
            get: { errorMessage != nil && !accountPreparationFailed },
            set: { if !$0 { errorMessage = nil } }
        )) {
            if accountPreparationFailed || Auth.auth().currentUser == nil {
                Button("Reconnect") { Task { await prepareSession() } }
            }
            if step == .record && !recorder.isRecording && !recorder.isFinalizing {
                Button("Write instead") {
                    inputMethod = "typing"
                    track("Onboarding Input Method Selected", ["input_method": "typing"])
                    storyEditorFocused = true
                }
            }
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button { goBack() } label: {
                    Image(systemName: "arrow.left")
                        .frame(width: 46, height: 44)
                        .contentShape(Rectangle())
                }
                    .accessibilityIdentifier("onboardingBack")
                    .opacity(step == .audience || step == .building ? 0 : 1)
                    .disabled(step == .audience || step == .building)
                    .accessibilityLabel("Back")
                Spacer()
                HStack(spacing: 7) {
                    Text("memoir")
                        .font(.custom("IowanOldStyle-Roman", size: 25, relativeTo: .largeTitle))
                    Image("MemoirBrandIcon")
                        .resizable().scaledToFit()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Memoir")
                Spacer()
                Button(OnboardingPreviewNavigationPolicy.canOpenPreview(hasImage: previewImage != nil, inputReady: audioReady) ? "See my\npage" : "Skip\ntour") {
                    if OnboardingPreviewNavigationPolicy.canOpenPreview(hasImage: previewImage != nil, inputReady: audioReady) {
                        sampleAudio.stop()
                        revealUnlocked = true
                        advance(to: .reveal)
                    } else {
                        track("Onboarding Action", ["action": "skip_tour"])
                        finishTour()
                    }
                }
                    .font(.custom("AvenirNext-Regular", size: 12, relativeTo: .body)).foregroundStyle(colors.muted)
                    .frame(width: 46, height: 44)
                    .opacity(isBookTour || step == .meetAlex ? 1 : 0)
                    .disabled(!(isBookTour || step == .meetAlex))
            }
            GeometryReader { proxy in
                Rectangle().fill(colors.moss.opacity(0.15))
                    .overlay(alignment: .leading) { Rectangle().fill(colors.moss).frame(width: proxy.size.width * progress) }
            }.frame(height: 2)
        }.foregroundStyle(colors.ink).padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 14)
    }

    private var isBookTour: Bool { [.cover, .spread, .illustration, .voice, .story].contains(step) }
    private var alexFocus: AlexFocus {
        switch step {
        case .cover: return .cover
        case .illustration: return .illustration
        case .voice: return .voice
        case .story: return .story
        default: return .spread
        }
    }

    private var progress: CGFloat {
        CGFloat(step.rawValue + 1) / CGFloat(OnboardingStep.allCases.count)
    }

    private var meetAlex: some View {
        OnboardingMeetAlexView(showsBackButton: !hasSubmittedMemory, onBack: goBack, onSkip: {
            track("Onboarding Action", ["action": "skip_tour"])
            finishTour()
        }) {
            track("Onboarding Action", ["action": "continue"])
            advance(to: .cover)
        }
    }

    enum AlexFocus: Equatable { case cover, spread, illustration, voice, story }

    private func alexBook(focus: AlexFocus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
            OnboardingBookStage(focus: focus)
                .frame(maxWidth: .infinity)
                .frame(height: layout.bookStageHeight)
                .clipped()
                VStack(alignment: .leading, spacing: 12) {
                    Text(alexKicker(focus)).font(.custom("AvenirNext-Bold", size: 9, relativeTo: .caption)).tracking(1.5).foregroundStyle(colors.rust)
                    Text(alexHeadline(focus)).font(.custom("IowanOldStyle-Roman", size: layout.tourHeadingSize, relativeTo: .largeTitle)).tracking(-1.1).foregroundStyle(colors.ink)
                    if !alexCaption(focus).isEmpty {
                        Text(alexCaption(focus)).font(.custom("AvenirNext-Regular", size: 13, relativeTo: .body)).foregroundStyle(colors.muted).lineSpacing(4)
                    }
                    if focus == .voice {
                        OnboardingSampleAudioView(audio: sampleAudio) {
                            track("Onboarding Action", ["action": sampleAudio.isPlaying ? "pause_sample" : "play_sample"])
                        }
                        if let error = sampleAudio.errorMessage { Text(error).font(.custom("AvenirNext-Regular", size: 13, relativeTo: .footnote)).foregroundStyle(colors.rust) }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            }
            primaryButton(focus == .story ? "See my page" : "Continue") {
                sampleAudio.stop()
                switch focus {
                case .cover: advance(to: .spread)
                case .spread: advance(to: .illustration)
                case .illustration: advance(to: .voice)
                case .voice: advance(to: .story)
                case .story: finishTour()
                }
            }.padding(.top, 8).padding(.bottom, 20)
        }
    }

    private func alexKicker(_ focus: AlexFocus) -> String {
        switch focus {
        case .cover: return "THE COVER"
        case .spread: return "INSIDE THE BOOK"
        case .illustration: return "THE MEMORY"
        case .voice: return "THE VOICE"
        case .story: return "THE STORY"
        }
    }
    private func alexHeadline(_ focus: AlexFocus) -> String {
        switch focus {
        case .cover: return "A life, made tangible."
        case .spread: return "One memory from Alex’s life."
        case .illustration: return "See the memory again."
        case .voice: return "A QR code stores their voice."
        case .story: return "Their story. Their details."
        }
    }
    private func alexCaption(_ focus: AlexFocus) -> String {
        switch focus {
        case .cover: return "Let’s flip through Alex’s memoir and see what a finished book could look like."
        case .spread: return ""
        case .illustration: return "A personal illustration brings the scene back to life."
        case .voice: return "Scan the code in the printed book to hear the original recording."
        case .story: return "The details of their story are preserved whether they speak or type."
        }
    }

    private var audienceQuestion: some View {
        questionShell(
            eyebrow: "YOUR MEMOIR",
            title: "What are you hoping to make?",
            subtitle: ""
        ) {
            VStack(spacing: 9) {
                ForEach(OnboardingAudience.allCases, id: \.self) { audience in
                    choiceButton(audience.title, selected: session.audience == audience) {
                        if session.audience != audience { session.storyteller = nil }
                        session.audience = audience
                        track("Onboarding Audience Selected", ["audience": audience.rawValue])
                        persistSession()

                    }
                }
                primaryButton("Continue", disabled: session.audience == nil, horizontalInset: 0) {
                    advance(to: session.audience == .notSure ? .meetAlex : .name)
                }.padding(.top, 16)
            }
        }
    }

    private var nameQuestion: some View {
        questionShell(
            eyebrow: "THE STORYTELLER",
            title: (session.audience == .someoneElse || session.audience == .parentOrGrandparent) ? "Whose stories are you preserving?" : "What should we call you?",
            subtitle: "We’ll put this name on the first page."
        ) {
            VStack(spacing: 18) {
                TextField("First name", text: Binding(
                    get: { session.narratorName },
                    set: {
                        ProductAnalytics.shared.inputStarted(field: "narrator_name", screen: "name")
                        if inputFieldsStarted.insert("narrator_name").inserted {
                            track("Onboarding Input Started", ["field": "narrator_name"])
                        }
                        session.narratorName = $0
                    }
                ))
                    .textContentType(.name)
                    .font(.custom("IowanOldStyle-Roman", size: 26, relativeTo: .title2))
                    .padding(.horizontal, 17).frame(minHeight: 64)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
                    .submitLabel(.continue)
                    .onSubmit { if validIdentity { advance(to: .record) } }
                primaryButton("Continue", disabled: !validIdentity, horizontalInset: 0) { advance(to: .record) }
            }
        }
    }

    private var validIdentity: Bool {
        validName
    }

    private var validName: Bool {
        let count = session.narratorName.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (1...100).contains(count)
    }

    private var inputReadiness: OnboardingInputReadiness {
        .evaluate(story: storyDraft, isRecording: recorder.isRecording,
                  isFinalizing: recorder.isFinalizing, audience: session.audience,
                  storyteller: session.storyteller)
    }

    private var recordMemory: some View {
        VStack(spacing: 12) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR FIRST MEMORY")
                        .font(.custom("AvenirNext-Bold", size: 9, relativeTo: .caption)).tracking(1.5)
                        .foregroundStyle(colors.rust)
                    Text(adaptivePrompt)
                        .font(.custom("IowanOldStyle-Roman", size: layout.headingSize, relativeTo: .largeTitle))
                        .tracking(-1.3).fixedSize(horizontal: false, vertical: true)
                    Text(adaptiveRecordingGuidance)
                        .font(.custom("AvenirNext-Regular", size: 14, relativeTo: .body))
                        .foregroundStyle(colors.muted).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if needsStorytellerChoice {
                        HStack {
                            choiceButton("I’ll tell it", compact: true, selected: session.storyteller == .helper) {
                                session.storyteller = .helper
                                track("Onboarding Storyteller Selected", ["storyteller": "helper"])
                                persistSession()
                            }
                            choiceButton(OnboardingRecordingCopy.subjectChoiceTitle(name: displayName), compact: true, selected: session.storyteller == .subject) {
                                session.storyteller = .subject
                                track("Onboarding Storyteller Selected", ["storyteller": "subject"])
                                persistSession()
                            }
                        }
                    }
                    Button {
                        if !recorder.isRecording {
                            inputMethod = "recording"
                            track("Onboarding Input Method Selected", ["input_method": "recording"])
                        }
                        track("Onboarding Action", ["action": recorder.isRecording ? "record_stop" : "record_start"])
                        if recorder.isRecording {
                            Task { storyDraft = await recorder.finish() }
                        } else if CloudTranscriptionDisclosure.isAccepted() {
                            recorder.requestPermissionsAndStart()
                        } else {
                            track("Onboarding Recording Consent Viewed")
                            showCloudDisclosure = true
                        }
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                let countdown = OnboardingRecordingCountdown(elapsed: recorder.elapsed)
                                Circle()
                                    .stroke(colors.moss.opacity(0.15), lineWidth: 4)
                                Circle()
                                    .trim(from: 0, to: countdown.remainingFraction)
                                    .stroke(
                                        recorder.isRecording && countdown.isUrgent ? colors.rust : colors.moss,
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 0.2), value: countdown.remainingFraction)
                                Circle()
                                    .fill(recorder.isRecording ? colors.rust : colors.moss)
                                    .padding(6)
                                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 22)).foregroundStyle(.white)
                            }
                            .frame(width: 52, height: 52)
                            .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recorder.isRecording ? "Recording your story" : "Tap to tell your story")
                                    .font(.custom("AvenirNext-DemiBold", size: 13, relativeTo: .body))
                                Text(recordingTimeDescription)
                                    .font(.custom("AvenirNext-Regular", size: 10, relativeTo: .caption))
                                    .foregroundStyle(recorder.isRecording && OnboardingRecordingCountdown(elapsed: recorder.elapsed).isUrgent ? colors.rust : colors.muted)
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 15).frame(minHeight: 70)
                        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(colors.moss.opacity(0.16)))
                    }
                    .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
                    .accessibilityValue(recorder.isRecording ? "\(OnboardingRecordingCountdown(elapsed: recorder.elapsed).remainingLabel) remaining" : "Up to 60 seconds")
                    .disabled(recorder.isFinalizing || (needsStorytellerChoice && session.storyteller == nil))
                    .opacity(needsStorytellerChoice && session.storyteller == nil ? 0.52 : 1)
                    if recorder.liveCaptionEnded && recorder.isRecording {
                        Text("Still recording. Your full story will be transcribed when you finish.")
                            .font(.custom("AvenirNext-Regular", size: 12, relativeTo: .footnote)).foregroundStyle(colors.muted)
                    }
                    HStack {
                        Text("Record or write your memory")
                            .font(.custom("AvenirNext-DemiBold", size: 12, relativeTo: .body))
                        Spacer(minLength: 8)
                        Button("Write instead") {
                            inputMethod = "typing"
                            track("Onboarding Input Method Selected", ["input_method": "typing"])
                            storyEditorFocused = true
                        }
                        .font(.custom("AvenirNext-DemiBold", size: 13, relativeTo: .body))
                        .frame(minHeight: 44)
                        .disabled(recorder.isRecording || recorder.isFinalizing)
                        .accessibilityIdentifier("onboardingWriteInstead")
                    }
                    .padding(.top, 6)
                    TextEditor(text: Binding(
                        get: { recorder.isRecording ? recorder.liveTranscript : storyDraft },
                        set: { if !recorder.isRecording {
                            ProductAnalytics.shared.inputStarted(field: "story", screen: "record")
                            inputMethod = "typing"
                            if inputFieldsStarted.insert("story").inserted {
                                track("Onboarding Input Started", ["field": "story"])
                            }
                            storyDraft = $0
                        } }
                    ))
                    .font(.custom("IowanOldStyle-Roman", size: 17, relativeTo: .body)).lineSpacing(4)
                    .focused($storyEditorFocused)
                    .scrollContentBackground(.hidden)
                    .disabled(recorder.isRecording || recorder.isFinalizing)
                    .padding(10).frame(height: layout.editorHeight)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.moss.opacity(0.2)))
                    .overlay(alignment: .topLeading) {
                        if storyDraft.isEmpty && recorder.liveTranscript.isEmpty {
                            Text("Your words will appear here. You can also type.")
                                .font(.custom("IowanOldStyle-Roman", size: 17, relativeTo: .body))
                                .foregroundStyle(colors.muted.opacity(0.75)).padding(18).allowsHitTesting(false)
                        }
                    }
                    .id("onboarding-story-editor")
                }
                .padding(.horizontal, 25).padding(.top, 16).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                if storyEditorFocused { proxy.scrollTo("onboarding-story-editor", anchor: .bottom) }
            }
            .onChange(of: storyEditorFocused) { _, focused in
                if focused { proxy.scrollTo("onboarding-story-editor", anchor: .bottom) }
            }
            }
            VStack(spacing: 4) {
                if inputReadiness == .needsStoryteller {
                    Text("Choose who is telling this story to continue.")
                        .font(.custom("AvenirNext-Medium", size: 12, relativeTo: .footnote))
                        .foregroundStyle(colors.muted)
                }
                if !storyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalizedStory == nil && !OnboardingMemoryValidation.exceedsMaximumLength(storyDraft) && !recorder.isRecording {
                    Text("Add a little more detail — at least six words — to make your first page.")
                        .font(.custom("AvenirNext-Regular", size: 12, relativeTo: .footnote))
                        .foregroundStyle(colors.muted)
                }
                if OnboardingMemoryValidation.exceedsMaximumLength(storyDraft) {
                    Text("Shorten this memory by \(OnboardingMemoryValidation.excessCharacterCount(storyDraft).formatted()) characters to continue.")
                        .font(.custom("AvenirNext-Medium", size: 12, relativeTo: .footnote))
                        .foregroundStyle(colors.rust)
                        .accessibilityIdentifier("onboardingStoryLengthError")
                }
            }
            .padding(.horizontal, 25).padding(.bottom, 8)
            primaryButton("Use this memory", disabled: normalizedStory == nil || recorder.isRecording || recorder.isFinalizing || (needsStorytellerChoice && session.storyteller == nil)) {
                do {
                    _ = try startMemoryPreflight()
                    hasSubmittedMemory = false
                    Task { await createPersonalizedPage() }
                } catch { errorMessage = error.localizedDescription }
            }
        }.padding(.bottom, 20)
    }

    private var buildingPage: some View {
        ZStack {
            Rectangle().fill(colors.paper.opacity(generationFailure == nil ? 0.38 : 1)).ignoresSafeArea()
            ScrollView {
            VStack(spacing: 14) {
                if generationFailure == nil && isGenerating {
                    ProgressView().controlSize(.large).tint(colors.moss)
                        .accessibilityLabel(generationStage)
                }
                Text(generationFailure != nil ? "Your preview isn’t ready" : (isGenerating ? generationStage : "Your first page is ready"))
                    .font(.custom("IowanOldStyle-Roman", size: 20, relativeTo: .title3)).multilineTextAlignment(.center)
                if let generationFailure {
                    Text(generationFailure).font(.custom("AvenirNext-Regular", size: 13, relativeTo: .footnote)).multilineTextAlignment(.center)
                    if previewRecovery == .retry || previewRecovery == .reconnect {
                        primaryButton(previewRecovery == .reconnect ? "Reconnect and try again" : "Try again") {
                            track("Onboarding Action", ["action": "retry_generation"])
                            Task {
                                if previewRecovery == .reconnect {
                                    _ = await AuthenticationService.shared.prepareAuthenticatedSessionForLaunch()
                                }
                                await createPersonalizedPage()
                            }
                        }
                    }
                    primaryButton("Continue to my memories") {
                        track("Onboarding Action", ["action": "continue_without_preview"])
                        finishAfterPaywall()
                    }
                } else if !isGenerating && previewImage != nil && audioReady {
                    Button {
                        track("Onboarding Action", ["action": "reveal"])
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) { revealUnlocked = true; advance(to: .reveal) }
                    } label: {
                        Text("Reveal your first page")
                            .font(.custom("AvenirNext-DemiBold", size: 12, relativeTo: .body))
                            .padding(.horizontal, 22).frame(minHeight: 44)
                            .foregroundStyle(.white).background(colors.moss, in: Capsule())
                    }
                }
            }.padding(.horizontal, 18).padding(.vertical, 24)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
                .frame(minHeight: max(0, availableSize.height - 24))
            }.offset(y: -12)
        }.foregroundStyle(colors.ink)
    }

    private var personalizedReveal: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(session.audience == .notSure ? "A first page." : "\(displayName)’s first page.")
                        .font(.custom("IowanOldStyle-Roman", size: layout.revealHeadingSize, relativeTo: .largeTitle)).foregroundStyle(colors.ink)
                    OnboardingPersonalPages(title: previewTitle, story: readingCopy ?? normalizedStory ?? storyDraft, image: previewImage, memoryID: session.memoryID, hasAudio: audioReady && currentAudioURL != nil)
                }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 30)
            }
            primaryButton("Create my memoir") { showPaywall = true }
                .opacity(step == .reveal ? 1 : 0).disabled(step != .reveal)
                .padding(.bottom, 20)
        }
        .accessibilityHidden(step != .reveal)

    }

    private var normalizedStory: String? {
        OnboardingMemoryValidation.normalizedTranscript(storyDraft.isEmpty ? recorder.liveTranscript : storyDraft)
    }

    private var adaptivePrompt: String {
        OnboardingRecordingCopy.prompt(for: session.audience, name: displayName)
    }

    private var adaptiveRecordingGuidance: String {
        OnboardingRecordingCopy.guidance(for: session.audience, name: displayName)
    }

    private var needsStorytellerChoice: Bool {
        OnboardingRecordingCopy.needsStorytellerChoice(for: session.audience)
    }

    private var displayName: String {
        let value = session.narratorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Your" : value
    }

    @ViewBuilder
    private func questionShell<Content: View>(eyebrow: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Spacer(minLength: 16)
                Text(eyebrow).font(.custom("AvenirNext-Bold", size: 9, relativeTo: .caption)).tracking(1.5).foregroundStyle(colors.rust)
                Text(title).font(.custom("IowanOldStyle-Roman", size: layout.headingSize, relativeTo: .largeTitle)).tracking(-1.3).fixedSize(horizontal: false, vertical: true).foregroundStyle(colors.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.custom("AvenirNext-Regular", size: 14, relativeTo: .body)).foregroundStyle(colors.muted).lineSpacing(3)
                }
                content().padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
    }

    private func choiceButton(_ title: String, subtitle: String? = nil, compact: Bool = false, selected: Bool, action: @escaping () -> Void) -> some View {
        let hasSubtitle = subtitle?.isEmpty == false
        return Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.custom("AvenirNext-DemiBold", size: compact ? 12 : 14, relativeTo: .body))
                    if let subtitle {
                        Text(subtitle).font(.custom("AvenirNext-Regular", size: 11, relativeTo: .caption))
                            .foregroundStyle(colors.muted)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").font(.system(size: 18, weight: .light))
            }
            .foregroundStyle(colors.ink)
            .padding(.horizontal, 16).padding(.vertical, compact ? 10 : (hasSubtitle ? 11 : 14))
            .frame(minHeight: compact ? 44 : (hasSubtitle ? 67 : 54))
            .background(selected ? Color(red: 229/255, green: 236/255, blue: 225/255) : Color(red: 251/255, green: 247/255, blue: 238/255), in: RoundedRectangle(cornerRadius: compact ? 22 : 13))
            .overlay(RoundedRectangle(cornerRadius: compact ? 22 : 13).stroke(colors.moss.opacity(selected ? 0.35 : 0.16)))
        }
    }

    private func primaryButton(_ title: String, disabled: Bool = false, horizontalInset: CGFloat = 25, action: @escaping () -> Void) -> some View {
        Button {
            track("Onboarding Action", ["action": "continue"])
            action()
        } label: {
            HStack {
                Text(title).font(.custom("AvenirNext-DemiBold", size: 14, relativeTo: .body))
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 17, weight: .regular))
            }
            .padding(.horizontal, 20).frame(maxWidth: .infinity).frame(minHeight: 56)
            .foregroundStyle(.white)
            .background(disabled ? colors.muted.opacity(0.35) : colors.moss, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(disabled)
        .padding(.horizontal, horizontalInset)
    }

    private func advance(to next: OnboardingStep) {
        guard next != step else { return }
        track("Onboarding Step Exited", ["step_duration_ms": max(0, Int(Date().timeIntervalSince(stepEnteredAt) * 1000))])
        if step == .name {
            ProductAnalytics.shared.inputCompleted(field: "narrator_name", screen: "name", characterCount: session.narratorName.count)
        }
        if step == .record {
            ProductAnalytics.shared.inputCompleted(field: "story", screen: "record", characterCount: storyDraft.count)
        }
        if step == .record && next != .record { _ = recorder.stop() }
        step = next
        session.stage = next.rawValue
        persistSession()
        stepEnteredAt = Date()
        track("Onboarding Step Viewed", ["step": next.rawValue])
        if next == .reveal && previewImage != nil && audioReady && !didTrackReveal {
            didTrackReveal = true
            track("Onboarding Personalized Reveal Viewed")
        }
    }

    private func finishTour() {
        track("Onboarding Tour Finished")
        sampleAudio.stop()
        if session.audience == .notSure {
            session.audience = .myself
            advance(to: .name)
        } else { advance(to: revealUnlocked ? .reveal : .building) }
    }

    private func goBack() {
        track("Onboarding Action", ["action": "back"])
        sampleAudio.stop()
        if step == .reveal { advance(to: .story); return }
        if step == .meetAlex {
            if hasSubmittedMemory { return }
            if session.audience == .notSure { advance(to: .audience); return }
        }
        guard let previous = OnboardingStep(rawValue: max(0, step.rawValue - 1)) else { return }
        advance(to: previous)
    }

    private func prepareSession() async {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITest"), arguments.contains("-UITestOnboardingAccountError") {
            isPreparingAccount = false
            accountPreparationFailed = true
            errorMessage = "Memoir couldn’t connect to your private account. Check your connection and try again."
            return
        }
        if arguments.contains("-UITest"), arguments.contains("-UITestOnboardingPreviewError") {
            isPreparingAccount = false
            step = .building
            generationFailure = "The preview image couldn’t be opened. You can continue to your saved memory."
            previewRecovery = .continueWithoutPreview
            return
        }
        #endif
        if !didTrackPresentation {
            didTrackPresentation = true
            track("Onboarding Presented")
        }
        let preparationStartedAt = Date()
        isPreparingAccount = true
        errorMessage = nil
        accountPreparationFailed = false
        guard await AuthenticationService.shared.prepareAuthenticatedSessionForLaunch(),
              let uid = Auth.auth().currentUser?.uid else {
            isPreparingAccount = false
            accountPreparationFailed = true
            errorMessage = "Memoir couldn’t connect to your private account. Check your connection and try again."
            track("Onboarding Preparation Failed", ["failure_stage": "auth"])
            return
        }
        guard !Task.isCancelled else { return }
        await profileVM.activateUser(uid)
        guard !Task.isCancelled else { return }
        #if DEBUG
        do {
            _ = try await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)
        } catch {
            isPreparingAccount = false
            accountPreparationFailed = true
            errorMessage = "Memoir couldn’t refresh this testing session. Check your connection and reconnect."
            return
        }
        #endif
        guard !Task.isCancelled else { return }
        if !didTrackStart {
            didTrackStart = true
            track("Onboarding Started")
        }
        if !didWarmPreviewService {
            didWarmPreviewService = true
            Task {
                let ready = await OnboardingPreviewService.shared.warmUp()
                #if DEBUG
                Logger(subsystem: "com.Buildr.MemoirAI", category: "OnboardingLatency")
                    .notice("Onboarding preview warmup ready=\(ready)")
                #endif
            }
        }
        editingOwner = uid
        editingProfileID = profileVM.selectedProfile.id
        session = OnboardingResumePolicy.scopedSession(
            sessionStore.load(userID: uid), profileID: profileVM.selectedProfile.id
        )
        step = .audience
        do {
            if let draft = try draftStore.load(userID: uid), draft.session.profileID == profileVM.selectedProfile.id {
                session = draft.session
                storyDraft = draft.story
                restoredRawTranscript = draft.rawTranscript
                restoredAudioURL = draft.audioURL
            } else {
                session.resetGeneratedIdentifiers()
                session.profileID = profileVM.selectedProfile.id
            }
            pendingEditingDraft = try editingDraftStore.load(userID: uid, profileID: profileVM.selectedProfile.id, flow: .onboarding)
            showEditingDraftRecovery = pendingEditingDraft?.hasContent == true
        } catch {
            editingDraftLoadFailed = true
            errorMessage = "The saved preview could not be restored. Your saved memories are still available in your account."
        }
        #if DEBUG && targetEnvironment(simulator)
        if OnboardingDebugConfiguration.audioFixtureRequested() {
            do {
                let fixture = try await OnboardingDebugConfiguration.loadAudioFixture()
                session.resetGeneratedIdentifiers()
                session.profileID = profileVM.selectedProfile.id
                storyDraft = fixture.draftTranscript
                restoredRawTranscript = fixture.draftTranscript
                restoredAudioURL = fixture.url
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        #endif
        if !OnboardingDebugConfiguration.replayOnLaunch {
            let destination = OnboardingResumePolicy.destination(for: session)
            switch destination {
            case .audience: step = .audience
            case .name: step = .name
            case .record: step = .record
            case .meetAlex: step = .meetAlex
            }
        }
        isPreparingAccount = false
        track("Onboarding Preparation Ready", ["duration_ms": max(0, Int(Date().timeIntervalSince(preparationStartedAt) * 1000))])
        if showEditingDraftRecovery {
            track("Onboarding Draft Recovery Offered")
        }
        session.stage = step.rawValue
        persistSession()
        stepEnteredAt = Date()
        track("Onboarding Step Viewed", ["step": step.rawValue])
    }

    private func persistEditingDraft() {
        guard !isPreparingAccount, !didTrackCompletion, !editingDraftLoadFailed, pendingEditingDraft == nil,
              let uid = editingOwner, let profileID = editingProfileID,
              uid == Auth.auth().currentUser?.uid else { return }
        let draft = StoryEditingDraft(text: storyDraft, audioURL: currentAudioURL,
                                      rawTranscript: recorder.audioURL != nil ? recorder.liveTranscript : restoredRawTranscript,
                                      narratorName: session.narratorName, audience: session.audience,
                                      storyteller: session.storyteller)
        do {
            if draft.hasContent {
                try editingDraftStore.save(draft, userID: uid, profileID: profileID, flow: .onboarding)
            } else {
                try editingDraftStore.clear(userID: uid, profileID: profileID, flow: .onboarding)
            }
        } catch {
            errorMessage = "Your draft could not be kept on this device. Keep Memoir open and try again after freeing some storage."
        }
    }

    private func restoreEditingDraft() {
        guard let draft = pendingEditingDraft else { return }
        storyDraft = draft.text
        restoredAudioURL = draft.audioURL
        restoredRawTranscript = draft.rawTranscript
        session.narratorName = draft.narratorName ?? session.narratorName
        session.audience = draft.audience
        session.storyteller = draft.storyteller
        pendingEditingDraft = nil
        track("Onboarding Draft Restored")
        advance(to: .record)
        persistSession()
        if let url = draft.audioURL, !FileManager.default.fileExists(atPath: url.path) {
            errorMessage = "Your written draft was restored, but its recording is missing. Its saved information has been kept."
        }
    }

    private func discardEditingDraft() {
        guard let uid = editingOwner, let profileID = editingProfileID else { return }
        do {
            try editingDraftStore.clear(userID: uid, profileID: profileID, flow: .onboarding)
            storyDraft = ""
            restoredAudioURL = nil
            restoredRawTranscript = nil
            pendingEditingDraft = nil
            track("Onboarding Draft Discarded")
        } catch {
            errorMessage = "Your draft could not be removed. Its files have been kept on this device."
        }
    }

    private func persistSession() {
        guard let uid = Auth.auth().currentUser?.uid, uid == editingOwner else { return }
        sessionStore.save(session, userID: uid)
    }

    @MainActor
    private func startMemoryPreflight() throws -> OnboardingMemoryPreflightKey {
        guard let story = normalizedStory, let uid = Auth.auth().currentUser?.uid, uid == editingOwner else {
            throw MemoryCreationError.cloudSyncFailed
        }
        var profile = profileVM.selectedProfile
        profile.name = displayName
        let raw = recorder.audioURL != nil ? recorder.liveTranscript : restoredRawTranscript
        let key = OnboardingMemoryPreflightKey(
            userID: uid, profileID: profile.id, name: displayName,
            audience: session.audience, storyteller: session.storyteller,
            prompt: adaptivePrompt, story: story, rawTranscript: raw,
            audioURL: currentAudioURL, audioDigest: try OnboardingMemoryPreflightKey.digest(of: currentAudioURL)
        )
        if memoryPreflight.key == key { return key }
        previewImage = nil
        readingCopy = nil
        audioReady = false
        revealUnlocked = false
        let previous = try draftStore.load(userID: uid)
        let sameMemory = previous.map {
            $0.story == story && $0.audioURL == currentAudioURL && $0.audioDigest == key.audioDigest &&
            $0.rawTranscript == raw && $0.session.profileID == profile.id &&
            $0.session.narratorName == session.narratorName &&
            $0.session.audience == session.audience && $0.session.storyteller == session.storyteller &&
            $0.photoData == nil
        } ?? false
        if memoryPreflight.key != nil || (previous != nil && !sameMemory) {
            session.resetGeneratedIdentifiers()
        }
        session.profileID = profile.id
        persistSession()
        let draft = OnboardingDraft(session: session, story: story, rawTranscript: raw,
                                    audioURL: currentAudioURL, photoData: nil,
                                    previewStory: sameMemory ? previous?.previewStory : nil, audioDigest: key.audioDigest)
        try draftStore.save(draft, userID: uid)
        let creation = MemoryCreationService()
        if PersistenceController.shared.entry(id: session.memoryID) == nil {
            try creation.saveOnboardingMemory(
                id: session.memoryID, prompt: adaptivePrompt, transcript: story,
                rawTranscript: raw, audioURL: currentAudioURL, profile: profile,
                firebaseUserID: uid, queueCloudSync: false
            )
            FacebookAnalytics.logFirstMemoryCreated()
            track("Onboarding Memory Saved Locally", ["has_audio": currentAudioURL != nil])
        }
        let memoryID = session.memoryID
        let savedProfile = profile
        let hasAudio = currentAudioURL != nil
        memoryPreflight.start(key: key) {
            try await creation.prepareOnboardingMemory(id: memoryID, profile: savedProfile,
                                                      firebaseUserID: uid, story: story, hasAudio: hasAudio)
        }
        return key
    }

    @MainActor
    private func createPersonalizedPage() async {
        guard !isGenerating, let story = normalizedStory else { return }
        guard let uid = Auth.auth().currentUser?.uid, uid == editingOwner else {
            errorMessage = "Reconnect to the account where you started this story before creating the page."
            return
        }
        isGenerating = true
        generationFailure = nil
        previewRecovery = .retry
        revealUnlocked = false
        generationStartedAt = Date()
        generationAttempt += 1
        didTrackReveal = false
        track("Onboarding Generation Started", ["has_audio": currentAudioURL != nil, "has_headshot": false])
        if !hasSubmittedMemory { advance(to: .meetAlex) }
        hasSubmittedMemory = true
        do {
            var profile = profileVM.selectedProfile
            if !OnboardingDebugConfiguration.replayOnLaunch {
                profile.name = displayName
                profileVM.updateSelectedProfile(with: profile)
            }
            session.profileID = profile.id
            persistSession()

            let preflightKey = try startMemoryPreflight()
            let previousDraft = try draftStore.load(userID: uid)
            let unchanged = previousDraft.map {
                $0.story == story && $0.session.narratorName == session.narratorName &&
                $0.session.audience == session.audience && $0.session.storyteller == session.storyteller && $0.audioURL == currentAudioURL &&
                $0.photoData == nil
            } ?? false
            if previousDraft != nil && !unchanged {
                session.requestID = UUID().uuidString
                persistSession()
            }
            let rawTranscript = recorder.audioURL != nil ? recorder.liveTranscript : restoredRawTranscript
            var submittedDraft = OnboardingDraft(
                session: session, story: story, rawTranscript: rawTranscript,
                audioURL: currentAudioURL, photoData: nil,
                previewStory: unchanged ? previousDraft?.previewStory : nil,
                audioDigest: preflightKey.audioDigest
            )
            try draftStore.save(submittedDraft, userID: uid)
            generationStage = "Preparing your story"
            let preparedStory = try await memoryPreflight.value(for: preflightKey)
            let completeStory = OnboardingCompletionPolicy.replayStory(
                savedRequestID: unchanged ? previousDraft?.session.requestID : nil,
                requestID: session.requestID, savedStory: submittedDraft.previewStory,
                preparedStory: preparedStory
            )
            guard Auth.auth().currentUser?.uid == uid else { throw MemoryCreationError.cloudSyncFailed }
            audioReady = true
            track("Onboarding Memory Synced", ["has_audio": currentAudioURL != nil])
            submittedDraft.previewStory = completeStory
            try draftStore.save(submittedDraft, userID: uid)
            generationStage = "Illustrating your memory"
            let result = try await OnboardingPreviewService.shared.create(
                expectedUserID: uid,
                requestID: session.requestID,
                profileID: profile.id,
                memoryID: session.memoryID,
                profileName: displayName,
                storyText: completeStory,
                storytellerRole: session.storyteller == .helper ? "helper" : "subject",
                subjectPhotoStoragePath: nil
            )
            guard result.status == .imageReady, let image = result.illustration else {
                throw OnboardingPreviewServiceError.invalidResponse
            }
            guard Auth.auth().currentUser?.uid == uid, memoryPreflight.key == preflightKey else {
                throw MemoryCreationError.cloudSyncFailed
            }
            audioReady = true
            readingCopy = result.readingText ?? completeStory
            previewImage = image
            previewTitle = result.title ?? previewTitle
            #if DEBUG
            Logger(subsystem: "com.Buildr.MemoirAI", category: "OnboardingLatency")
                .notice("Onboarding preview ready elapsed_ms=\(Int(Date().timeIntervalSince(generationStartedAt ?? Date()) * 1000)) cached=\(result.cached)")
            #endif
            track("Onboarding Preview Image Ready", [
                "duration_ms": Int(Date().timeIntervalSince(generationStartedAt ?? Date()) * 1000),
                "has_headshot": false,
                "cached": result.cached
            ])
            isGenerating = false
        } catch {
            isGenerating = false
            previewRecovery = OnboardingPreviewErrorPolicy.recovery(for: error)
            if previewRecovery == .cancelled {
                track("Onboarding Preview Cancelled")
                previewRecovery = .retry
                generationFailure = "Your preview was paused. Try again to continue with the same story."
                return
            }
            generationFailure = OnboardingPreviewErrorPolicy.message(for: error)
            if step == .building { errorMessage = nil }
            track("Onboarding Preview Failed", [
                "failure_kind": String(describing: type(of: error)),
                "failure_reason": OnboardingPreviewErrorPolicy.reason(for: error),
                "failure_stage": OnboardingPreviewErrorPolicy.stage(for: error) ?? (audioReady ? "generation" : "preflight"),
                "duration_ms": max(0, Int(Date().timeIntervalSince(generationStartedAt ?? Date()) * 1000))
            ])
        }
    }

    private func finishAfterPaywall() {
        guard !didTrackCompletion, OnboardingCompletionPolicy.shouldComplete(after: .paywallDismissed) else { return }
        guard let owner = editingOwner, Auth.auth().currentUser?.uid == owner else {
            errorMessage = "Your account changed. Reopen Memoir to continue in the right account. Your original draft has been kept."
            return
        }
        let outcome = OnboardingCompletionPolicy.outcome(
            previewReady: previewImage != nil && audioReady,
            offerPresented: offerPresented, entitlementActive: entitlementActive
        )
        didTrackCompletion = true
        if OnboardingCompletionPolicy.isSuccessful(outcome), !OnboardingDebugConfiguration.replayOnLaunch, let uid = Auth.auth().currentUser?.uid {
            sessionStore.clear(userID: uid)
            do {
                try draftStore.clear(userID: uid)
                if let profileID = editingProfileID {
                    try editingDraftStore.clear(userID: uid, profileID: profileID, flow: .onboarding)
                }
            } catch {
                print("Onboarding draft cleanup failed: \(error.localizedDescription)")
            }
        }
        iCloudManager.completeOnboarding()
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding_local")
        track("Onboarding Exited", ["onboarding_outcome": outcome])
        if OnboardingCompletionPolicy.isSuccessful(outcome) {
            FacebookAnalytics.logOnboardingCompleted()
            track("Onboarding Completed", ["onboarding_outcome": outcome])
        }
        onFinished?()
    }

    private func track(_ event: String, _ properties: [String: MixpanelType] = [:]) {
        if let editingOwner, editingOwner != Auth.auth().currentUser?.uid { return }
        var context: Properties = [
            "screen": String(describing: step), "onboarding_version": "native_v7",
            "flow_id": analyticsFlowID, "generation_attempt": generationAttempt, "analytics_version": 2,
            "generation_request_id": session.requestID
        ]
        if step == .record {
            context["input_readiness"] = inputReadiness.rawValue
            context["input_method"] = inputMethod
            context["has_text"] = !storyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            context["has_audio"] = currentAudioURL != nil
        }
        if let audience = session.audience { context["audience"] = audience.rawValue }
        if let storyteller = session.storyteller { context["storyteller"] = storyteller.rawValue }
        context.merge(properties) { _, new in new }
        ProductAnalytics.shared.track(event, context)
    }

    private func timeString(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }

    private var recordingTimeDescription: String {
        if recorder.isRecording {
            return "\(OnboardingRecordingCountdown(elapsed: recorder.elapsed).remainingLabel) remaining"
        }
        if recorder.audioURL != nil {
            return "\(timeString(recorder.elapsed)) recorded"
        }
        return "Up to 60 seconds"
    }
}

private struct OnboardingSampleAudioView: View {
    @ObservedObject var audio: OnboardingSampleAudioPlayer
    var onToggle: () -> Void
    private let colors = OnboardingColorTheme()

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: !audio.isPlaying)) { _ in
            let position = audio.position
            VStack(spacing: 14) {
                Rectangle().fill(colors.moss.opacity(0.18)).frame(height: 1)
                HStack(spacing: 14) {
                    Button { onToggle(); audio.toggle() } label: {
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.custom("AvenirNext-DemiBold", size: 17, relativeTo: .body))
                            .offset(x: audio.isPlaying ? 0 : 1)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(colors.moss, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(audio.isPlaying ? "Pause Alex’s memory" : "Listen to Alex’s memory")
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Listen to Alex’s memory")
                                .font(.custom("AvenirNext-DemiBold", size: 12, relativeTo: .body))
                                .foregroundStyle(colors.ink)
                            Spacer(minLength: 6)
                            Text(position.elapsedLabel)
                                .font(.custom("AvenirNext-Regular", size: 11, relativeTo: .caption).monospacedDigit())
                                .foregroundStyle(colors.muted)
                        }
                        GeometryReader { geometry in
                            HStack(spacing: 3) {
                                ForEach(0..<39, id: \.self) { index in
                                    Capsule()
                                        .fill(Double(index) / 39 < position.fraction ? colors.moss : Color(red: 152/255, green: 164/255, blue: 148/255))
                                        .frame(width: max(1, (geometry.size.width - 114) / 39), height: 4 + abs(sin(Double(index) * 1.71) * cos(Double(index) * 0.38)) * 18)
                                }
                            }.frame(height: 22)
                        }
                        .frame(height: 22)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Recording progress")
                        .accessibilityValue("\(position.elapsedLabel) of \(position.durationLabel)")
                    }
                }
            }
            .padding(.top, 14)
        }
    }
}

struct OnboardingAudioPosition {
    let elapsed: TimeInterval
    let duration: TimeInterval

    var fraction: Double {
        guard elapsed.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    var elapsedLabel: String { Self.label(elapsed) }
    var durationLabel: String { Self.label(duration) }

    private static func label(_ interval: TimeInterval) -> String {
        let seconds = interval.isFinite ? Int(min(86_400, max(0, interval))) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor
final class OnboardingSampleAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    private var player: AVAudioPlayer?
    private let recordingURL: URL?
    private var finished = false

    init(recordingURL: URL? = Bundle.main.url(forResource: "alex-sample", withExtension: "mp3")) {
        self.recordingURL = recordingURL
        super.init()
    }

    var position: OnboardingAudioPosition {
        OnboardingAudioPosition(elapsed: finished ? (player?.duration ?? 0) : (player?.currentTime ?? 0), duration: player?.duration ?? 0)
    }

    func toggle() {
        if isPlaying { stop(); return }
        guard let url = recordingURL else { errorMessage = "Alex’s recording is unavailable."; return }
        do {
            if player == nil { player = try AVAudioPlayer(contentsOf: url); player?.delegate = self }
            if finished { player?.currentTime = 0; finished = false }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            errorMessage = nil
            isPlaying = player?.play() == true
            if !isPlaying { errorMessage = "The recording couldn’t play. Please try again." }
        } catch { isPlaying = false; errorMessage = "The recording couldn’t play. Please try again." }
    }

    func stop() { player?.pause(); isPlaying = false }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finished = flag
            self.isPlaying = false
            if !flag { self.errorMessage = "The recording stopped unexpectedly. Please try again." }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.isPlaying = false
            self.errorMessage = "The recording couldn’t play. Please try again."
        }
    }
}

#Preview {
    OnboardingFlow()
        .environmentObject(ProfileViewModel())
        .environmentObject(iCloudManager.shared)
}
