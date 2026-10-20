import AVFoundation
import FirebaseAuth
import Mixpanel
import OSLog
import SwiftUI
import UIKit

// Completion remains tied to seeing and dismissing the paywall.
enum OnboardingCompletionPolicy {
    enum Event { case finalContinueTapped, paywallDismissed }
    static func shouldComplete(after event: Event) -> Bool { event == .paywallDismissed }
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
    case audience, name, record, photo, meetAlex, cover, spread, illustration, voice, story, building, reveal
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
    @State private var didTrackStart = false
    @State private var generationAttempt = 0
    @State private var didTrackReveal = false
    @State private var step: OnboardingStep = .audience
    @State private var session = OnboardingSession()
    @State private var storyDraft = ""
    @State private var selectedPhoto: UIImage?
    @State private var previewImage: UIImage?
    @State private var submittedPhotoData: Data?
    @State private var restoredAudioURL: URL?
    @State private var restoredRawTranscript: String?
    @State private var readingCopy: String?
    @State private var generationFailure: String?
    @State private var audioReady = false
    @State private var generationStage = "Preparing your first page"
    @State private var hasSubmittedMemory = false
    @State private var previewTitle = "A memory I carry"
    @State private var showPaywall = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showCloudDisclosure = false
    @State private var didWarmPreviewService = false
    @State private var isPreparingAccount = true
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generationStartedAt: Date?
    @State private var revealUnlocked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colors = OnboardingColorTheme()
    private let sessionStore = OnboardingSessionStore()
    private let draftStore = OnboardingDraftStore()
    private var currentAudioURL: URL? { recorder.audioURL ?? restoredAudioURL }

    var body: some View {
        ZStack {
            colors.paper.ignoresSafeArea()
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
                        case .photo: photoCapture
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
            if isPreparingAccount {
                colors.paper.opacity(0.8).ignoresSafeArea()
                ProgressView("Opening your private workspace")
            }
            if step == .building && !revealUnlocked { buildingPage.transition(.opacity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { availableSize = $0 }
        .foregroundStyle(colors.ink)
        .animation(reduceMotion ? nil : (step == .meetAlex ? .easeInOut(duration: 0.45) : .spring(response: 0.55, dampingFraction: 0.88)), value: step)
        .analyticsScreen(String(describing: step))
        .task { await prepareSession() }
        .onDisappear { _ = recorder.stop(); sampleAudio.stop(); memoryPreflight.invalidate() }
        .onChange(of: scenePhase) { _, phase in
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
        .onChange(of: recorder.isRecording) { _, recording in
            track(recording ? "Onboarding Recording Started" : "Onboarding Recording Stopped", ["recording_duration": recorder.elapsed])
        }
        .onChange(of: sampleAudio.isPlaying) { _, playing in
            track(playing ? "Onboarding Sample Playback Started" : "Onboarding Sample Playback Stopped")
        }
        .onChange(of: storyDraft) { _, _ in memoryPreflight.invalidate() }
        .onChange(of: session.narratorName) { _, _ in memoryPreflight.invalidate() }
        .onChange(of: session.audience) { _, _ in memoryPreflight.invalidate() }
        .onChange(of: session.storyteller) { _, _ in memoryPreflight.invalidate() }
        .onChange(of: currentAudioURL) { _, _ in memoryPreflight.invalidate() }
        .onChange(of: recorder.liveTranscript) { _, value in
            if step == .record && recorder.audioURL != nil { storyDraft = value }
        }
        .onChange(of: recorder.isFinalizing) { _, finalizing in
            if !finalizing && recorder.audioURL != nil { storyDraft = recorder.liveTranscript }
        }
        .onChange(of: recorder.errorMessage) { _, value in
            if let value {
                errorMessage = value
                track("Onboarding Recording Failed", ["failure_stage": "recording"])
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView { acceptPhoto($0, source: "camera") }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            LibraryPickerView { acceptPhoto($0, source: "library") }
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPaywall, onDismiss: finishAfterPaywall) {
            SubscriptionPaywallView()
                .onAppear {
                    track("Onboarding Paywall Viewed")
                    FacebookAnalytics.logPaywallViewed()
                }
        }
        .alert(CloudTranscriptionDisclosure.title, isPresented: $showCloudDisclosure) {
            Button("Continue") {
                CloudTranscriptionDisclosure.accept()
                recorder.requestPermissionsAndStart()
            }
            Button("Not now", role: .cancel) { }
        } message: { Text(CloudTranscriptionDisclosure.message) }
        .alert("Memoir needs a moment", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            if Auth.auth().currentUser == nil {
                Button("Reconnect") { Task { await prepareSession() } }
            }
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button { goBack() } label: { Image(systemName: "arrow.left").frame(width: 46, height: 44) }
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
                Button("Skip\ntour") {
                    track("Onboarding Action", ["action": "skip_tour"])
                    finishTour()
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
        OnboardingMeetAlexView(onBack: goBack, onSkip: {
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
            subtitle: "We’ll shape the experience around you."
        ) {
            VStack(spacing: 9) {
                ForEach(OnboardingAudience.allCases, id: \.self) { audience in
                    choiceButton(audience.title, subtitle: audience.subtitle, selected: session.audience == audience) {
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
                        session.narratorName = $0
                    }
                ))
                    .textContentType(.name)
                    .font(.custom("IowanOldStyle-Roman", size: 26, relativeTo: .title2))
                    .padding(.horizontal, 17).frame(minHeight: 64)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
                    .submitLabel(.continue)
                    .onSubmit { if validIdentity { advance(to: .record) } }
                if session.audience == .someoneElse || session.audience == .parentOrGrandparent {
                    Text("Who will tell this memory?").font(.custom("AvenirNext-DemiBold", size: 12, relativeTo: .body))
                    HStack {
                        choiceButton("I will", compact: true, selected: session.storyteller == .helper) { session.storyteller = .helper; persistSession() }
                        choiceButton("\(displayName) will", compact: true, selected: session.storyteller == .subject) { session.storyteller = .subject; persistSession() }
                    }
                }
                primaryButton("Continue", disabled: !validIdentity, horizontalInset: 0) { advance(to: .record) }
            }
        }
    }

    private var validIdentity: Bool {
        validName && (!(session.audience == .someoneElse || session.audience == .parentOrGrandparent) || session.storyteller != nil)
    }

    private var validName: Bool {
        let count = session.narratorName.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (1...100).contains(count)
    }

    private var recordMemory: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR FIRST MEMORY")
                        .font(.custom("AvenirNext-Bold", size: 9, relativeTo: .caption)).tracking(1.5)
                        .foregroundStyle(colors.rust)
                    Text(adaptivePrompt)
                        .font(.custom("IowanOldStyle-Roman", size: layout.headingSize, relativeTo: .largeTitle))
                        .tracking(-1.3).fixedSize(horizontal: false, vertical: true)
                    Text("Tap the microphone below and answer the question to get started.")
                        .font(.custom("AvenirNext-Regular", size: 14, relativeTo: .body))
                        .foregroundStyle(colors.muted).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        track("Onboarding Action", ["action": recorder.isRecording ? "record_stop" : "record_start"])
                        if recorder.isRecording {
                            Task { storyDraft = await recorder.finish() }
                        } else if CloudTranscriptionDisclosure.isAccepted() {
                            recorder.requestPermissionsAndStart()
                        } else { showCloudDisclosure = true }
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle().fill(recorder.isRecording ? colors.rust : colors.moss).frame(width: 46, height: 46)
                                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 22)).foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recorder.isRecording ? "Recording your story" : "Tap to tell your story")
                                    .font(.custom("AvenirNext-DemiBold", size: 13, relativeTo: .body))
                                Text(recorder.isRecording ? timeString(recorder.elapsed) : "Usually 30–90 seconds")
                                    .font(.custom("AvenirNext-Regular", size: 10, relativeTo: .caption))
                                    .foregroundStyle(colors.muted).monospacedDigit()
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 15).frame(minHeight: 70)
                        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(colors.moss.opacity(0.16)))
                    }
                    .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
                    .disabled(recorder.isFinalizing)
                    if recorder.liveCaptionEnded && recorder.isRecording {
                        Text("Still recording. Your full story will be transcribed when you finish.")
                            .font(.custom("AvenirNext-Regular", size: 12, relativeTo: .footnote)).foregroundStyle(colors.muted)
                    }
                    Text("Your words").font(.custom("AvenirNext-DemiBold", size: 12, relativeTo: .body)).padding(.top, 6)
                    TextEditor(text: Binding(
                        get: { recorder.isRecording ? recorder.liveTranscript : storyDraft },
                        set: { if !recorder.isRecording {
                            ProductAnalytics.shared.inputStarted(field: "story", screen: "record")
                            storyDraft = $0
                        } }
                    ))
                    .font(.custom("IowanOldStyle-Roman", size: 17, relativeTo: .body)).lineSpacing(4)
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
                    Button("Use a sample answer") {
                        track("Onboarding Action", ["action": "sample_answer"])
                        recorder.discard()
                        restoredAudioURL = nil
                        restoredRawTranscript = nil
                        storyDraft = "Every summer, my cousins and I built a fort under the big tree in our backyard. We dragged out old blankets and ate peach slices with sticky fingers. One afternoon it started raining, and we stayed under our leaky roof, laughing until my mum called us inside."
                    }
                    .font(.custom("AvenirNext-DemiBold", size: 12, relativeTo: .body))
                    .underline().foregroundStyle(colors.moss).frame(minHeight: 44)
                    .disabled(recorder.isRecording || recorder.isFinalizing)
                }
                .padding(.horizontal, 25).padding(.top, 16).padding(.bottom, 12)
            }
            primaryButton("Use this memory", disabled: normalizedStory == nil || recorder.isRecording || recorder.isFinalizing) {
                do {
                    _ = try startMemoryPreflight()
                    hasSubmittedMemory = false
                    advance(to: .photo)
                } catch { errorMessage = error.localizedDescription }
            }
        }.padding(.bottom, 20)
    }

    private var photoCapture: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
            Text("MAKE IT LOOK LIKE YOU")
                .font(.custom("AvenirNext-Bold", size: 9, relativeTo: .caption)).tracking(1.5)
                .foregroundStyle(colors.rust)
            Text(adaptivePhotoTitle)
                .font(.custom("IowanOldStyle-Roman", size: layout.headingSize, relativeTo: .largeTitle))
                .tracking(-1.3).fixedSize(horizontal: false, vertical: true)
            Text(adaptivePhotoBody)
                .font(.custom("AvenirNext-Regular", size: 14, relativeTo: .body)).foregroundStyle(colors.muted)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            if let selectedPhoto {
                Image(uiImage: selectedPhoto).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: layout.photoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.72))
                    .frame(maxWidth: .infinity).frame(height: layout.photoHeight)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.rectangle").font(.system(size: 48)).foregroundStyle(colors.moss)
                            Text("Face the camera in good light").font(.custom("AvenirNext-Medium", size: 14, relativeTo: .body))
                        }
                    }
            }
            HStack(spacing: 12) {
                secondaryButton("Camera", icon: "camera.fill") { track("Onboarding Action", ["action": "photo_camera"]); showCamera = true }
                secondaryButton("Library", icon: "photo.fill") { track("Onboarding Action", ["action": "photo_library"]); showLibrary = true }
            }

                }.padding(.horizontal, 25).padding(.top, 24).padding(.bottom, 20)
            }
            if selectedPhoto == nil {
                Button("Continue without a photo") {
                    track("Onboarding Action", ["action": "photo_skip"])
                    Task { await createPersonalizedPage() }
                }
                    .font(.custom("AvenirNext-Medium", size: 12, relativeTo: .body))
                    .foregroundStyle(colors.muted)
            }
            primaryButton("Next", disabled: selectedPhoto == nil || isPreparingAccount) {
                Task { await createPersonalizedPage() }
            }
        }
        .padding(.bottom, 24)
    }

    private var buildingPage: some View {
        ZStack {
            Rectangle().fill(colors.paper.opacity(0.38)).ignoresSafeArea()
            ScrollView {
            VStack(spacing: 14) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(generationStartedAt ?? context.date))
                    let value = previewImage != nil && audioReady ? 1.0 : min(0.94, 1 - exp(-elapsed / 25))
                    ZStack {
                        Circle().stroke(colors.moss.opacity(0.12), lineWidth: 6)
                        Circle().trim(from: 0, to: value).stroke(colors.moss, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(Int(value * 100))% ").font(.custom("IowanOldStyle-Roman", size: 22, relativeTo: .title2)).monospacedDigit()
                    }.frame(width: 116, height: 116)
                }
                Text(generationFailure != nil ? "Your memory is safe" : (isGenerating ? generationStage : "Your first page is ready"))
                    .font(.custom("IowanOldStyle-Roman", size: 20, relativeTo: .title3)).multilineTextAlignment(.center)
                if let generationFailure {
                    Text(generationFailure).font(.custom("AvenirNext-Regular", size: 13, relativeTo: .footnote)).multilineTextAlignment(.center)
                    primaryButton("Try again") {
                        ProductAnalytics.shared.action("retry_generation", screen: "building")
                        Task { await createPersonalizedPage() }
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
        (session.audience == .myself || session.audience == .myChildren || session.storyteller == .subject)
            ? "What’s a favorite childhood memory?"
            : "What is one of \(displayName)’s favorite childhood memories?"
    }

    private var adaptivePhotoTitle: String {
        switch session.audience {
        case .myself, .myChildren: return "Add a photo of yourself"
        case .parentOrGrandparent: return "Add a photo of \(displayName)"
        default: return "Add a photo of \(displayName)"
        }
    }

    private var adaptivePhotoBody: String {
        "Choose a clear, front-facing photo in natural light. It stays private to your account."
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
                Text(subtitle).font(.custom("AvenirNext-Regular", size: 14, relativeTo: .body)).foregroundStyle(colors.muted).lineSpacing(3)
                content().padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
    }

    private func choiceButton(_ title: String, subtitle: String? = nil, compact: Bool = false, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
            .padding(.horizontal, 16).padding(.vertical, compact ? 10 : 11)
            .frame(minHeight: compact ? 44 : 67)
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

    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.custom("AvenirNext-DemiBold", size: 13, relativeTo: .body))
                .frame(maxWidth: .infinity).frame(minHeight: 44)
                .foregroundStyle(colors.ink)
                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
        }
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
        isPreparingAccount = true
        guard await AuthenticationService.shared.prepareAuthenticatedSessionForLaunch(),
              let uid = Auth.auth().currentUser?.uid else {
            isPreparingAccount = false
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
        session = sessionStore.load(userID: uid)
        session.profileID = profileVM.selectedProfile.id
        // Draft audio and photos are not restored by the session store. Start at
        // the questionnaire rather than showing a later screen with missing inputs.
        step = .audience
        do {
            if let draft = try draftStore.load(userID: uid) {
                session = draft.session
                storyDraft = draft.story
                restoredRawTranscript = draft.rawTranscript
                restoredAudioURL = draft.audioURL
                selectedPhoto = draft.photoData.flatMap(UIImage.init(data:))
                submittedPhotoData = draft.photoData
            } else {
                session.resetGeneratedIdentifiers()
            }
        } catch {
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
                submittedPhotoData = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        #endif
        if selectedPhoto == nil { selectedPhoto = OnboardingDebugConfiguration.simulatorHeadshot }
        isPreparingAccount = false
        persistSession()
        stepEnteredAt = Date()
        track("Onboarding Step Viewed", ["step": step.rawValue])
    }

    private func persistSession() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        sessionStore.save(session, userID: uid)
    }

    private func acceptPhoto(_ image: UIImage, source: String) {
        selectedPhoto = image
        submittedPhotoData = nil
        track("Onboarding Photo Added", ["source": source])
    }

    @MainActor
    private func startMemoryPreflight() throws -> OnboardingMemoryPreflightKey {
        guard let story = normalizedStory, let uid = Auth.auth().currentUser?.uid else {
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
            $0.session.audience == session.audience && $0.session.storyteller == session.storyteller
        } ?? false
        if memoryPreflight.key != nil || (previous != nil && !sameMemory) {
            session.resetGeneratedIdentifiers()
        }
        session.profileID = profile.id
        persistSession()
        let draft = OnboardingDraft(session: session, story: story, rawTranscript: raw,
                                    audioURL: currentAudioURL, photoData: sameMemory ? previous?.photoData : nil,
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
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Reconnect to your private account before creating the page."
            return
        }
        isGenerating = true
        generationFailure = nil
        revealUnlocked = false
        generationStartedAt = Date()
        generationAttempt += 1
        didTrackReveal = false
        track("Onboarding Generation Started", ["has_audio": currentAudioURL != nil, "has_headshot": selectedPhoto != nil])
        if !hasSubmittedMemory { advance(to: .meetAlex) }
        hasSubmittedMemory = true
        do {
            var profile = profileVM.selectedProfile
            if !OnboardingDebugConfiguration.replayOnLaunch {
                profile.name = displayName
                profile.photoData = selectedPhoto?.jpegData(compressionQuality: 0.82)
                profileVM.updateSelectedProfile(with: profile)
            }
            session.profileID = profile.id
            persistSession()

            let preflightKey = try startMemoryPreflight()
            let submittedPhoto = submittedPhotoData ?? selectedPhoto.flatMap(OnboardingPhotoPreparation.jpeg(from:))
            let previousDraft = try draftStore.load(userID: uid)
            let unchanged = previousDraft.map {
                $0.story == story && $0.session.narratorName == session.narratorName &&
                $0.session.audience == session.audience && $0.session.storyteller == session.storyteller && $0.audioURL == currentAudioURL &&
                $0.photoData == submittedPhoto
            } ?? false
            if previousDraft != nil && !unchanged {
                session.requestID = UUID().uuidString
                persistSession()
            }
            submittedPhotoData = submittedPhoto
            let rawTranscript = recorder.audioURL != nil ? recorder.liveTranscript : restoredRawTranscript
            var submittedDraft = OnboardingDraft(
                session: session, story: story, rawTranscript: rawTranscript,
                audioURL: currentAudioURL, photoData: submittedPhoto, audioDigest: preflightKey.audioDigest
            )
            try draftStore.save(submittedDraft, userID: uid)
            async let uploadedPhoto = OnboardingPreviewService.shared.uploadPhoto(
                submittedPhoto, requestID: session.requestID, userID: uid
            )
            generationStage = "Preparing your story"
            let completeStory = try await memoryPreflight.value(for: preflightKey)
            guard Auth.auth().currentUser?.uid == uid else { throw MemoryCreationError.cloudSyncFailed }
            audioReady = true
            track("Onboarding Memory Synced", ["has_audio": currentAudioURL != nil])
            submittedDraft.previewStory = completeStory
            try draftStore.save(submittedDraft, userID: uid)
            let photoPath = try await uploadedPhoto
            generationStage = "Illustrating your memory"
            let result = try await OnboardingPreviewService.shared.create(
                requestID: session.requestID,
                profileID: profile.id,
                memoryID: session.memoryID,
                profileName: displayName,
                storyText: completeStory,
                storytellerRole: session.storyteller == .helper ? "helper" : "subject",
                subjectPhotoStoragePath: photoPath
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
                "has_headshot": selectedPhoto != nil,
                "cached": result.cached
            ])
            isGenerating = false
        } catch {
            isGenerating = false
            generationFailure = OnboardingPreviewErrorPolicy.message(for: error)
            if step == .building { errorMessage = nil }
            track("Onboarding Preview Failed", ["failure_kind": String(describing: type(of: error))])
        }
    }

    private func finishAfterPaywall() {
        guard !didTrackCompletion, OnboardingCompletionPolicy.shouldComplete(after: .paywallDismissed) else { return }
        didTrackCompletion = true
        if !OnboardingDebugConfiguration.replayOnLaunch, let uid = Auth.auth().currentUser?.uid { sessionStore.clear(userID: uid) }
        iCloudManager.completeOnboarding()
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding_local")
        FacebookAnalytics.logOnboardingCompleted()
        track("Onboarding Completed")
        onFinished?()
    }

    private func track(_ event: String, _ properties: [String: MixpanelType] = [:]) {
        var context: Properties = [
            "screen": String(describing: step), "onboarding_version": "native_v5",
            "flow_id": analyticsFlowID, "generation_attempt": generationAttempt
        ]
        context.merge(properties) { _, new in new }
        ProductAnalytics.shared.track(event, context)
    }

    private func timeString(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
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
