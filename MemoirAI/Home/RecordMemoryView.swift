import SwiftUI
import AVFoundation
import Speech
import CoreData

enum PrimaryRecordingControlState: Equatable {
    case ready
    case recording
    case paused

    var accessibilityLabel: String {
        switch self {
        case .ready:
            return "Start recording"
        case .recording:
            return "Pause recording"
        case .paused:
            return "Resume recording"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .ready:
            return "Not recording"
        case .recording:
            return "Recording"
        case .paused:
            return "Paused"
        }
    }
}

enum PrimaryRecordingControlPolicy {
    static func state(isRecording: Bool, isPaused: Bool) -> PrimaryRecordingControlState {
        if isPaused {
            return .paused
        }
        return isRecording ? .recording : .ready
    }
}

struct RecordMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel
    @EnvironmentObject var tutorialCoordinator: TutorialCoordinator
    @StateObject private var viewModel = MemoryEntryViewModel()
    @StateObject private var usageTracker = UsageTracker.shared
    @StateObject private var audioMonitor = AudioLevelMonitor()
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var realTimeTranscription = RealTimeTranscriptionManager.shared
    @StateObject private var interruptionObserver = AudioSessionInterruptionObserver()

    @State private var selectedPrompt: String? = nil
    @State private var showTextEntry: Bool = false
    @State private var typedText: String = ""
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioURL: URL?
    @State private var showExitConfirm = false
    @State private var isSaving = false
    @State private var shouldDismissAfterSave = false
    @FocusState private var isTextFocused: Bool
    @State private var answeredPrompts: [String] = []
    @State private var suggestionPool: [String] = []
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var isKeyboardSavePressed = false
    @State private var showCloudTranscriptionDisclosure = false
    @State private var saveErrorMessage: String?
    
    // Timeout warning states
    @State private var showTimeoutWarning = false
    @State private var finalCountdown: Int? = nil

    // Interruption / backgrounding state — set whenever the recorder was paused
    // by the system (not by the user tapping Pause) so the UI can explain why.
    @State private var interruptionBannerMessage: String? = nil
    
    // Store picked/cropped images as raw JPEG/PNG data for Core-Data persistence
    
    // Constants
    private let maxRecordingDuration = RecordingDurationPolicy.maximumRecordingDuration
    private let warningThreshold = RecordingDurationPolicy.warningThreshold
    private let countdownStart = RecordingDurationPolicy.countdownStart
    
    private let passedPrompt: String?
    private let promptKey = "PromptOfTheDayCompleted"
    
    /// Accent color for all pop-ups and interactive text
    private let accent = Color(red: 0.10, green: 0.22, blue: 0.14)
    
    init(promptOfTheDay: String? = nil) {
        self.passedPrompt = promptOfTheDay
        _selectedPrompt = State(initialValue: promptOfTheDay)
    }
    
    let allPrompts: [String] = [
        // Family & traditions
        "What are your favorite family traditions?",
        "Tell me about when you first met Grandma.",
        "What is your favorite story about your parents?",
        "Describe a typical Sunday in your family growing up.",
        "What did family dinners look like when you were young?",
        "Tell me about a relative who made a big impression on you.",
        "What traditions did your family have around the holidays?",
        "Share a story about your grandparents.",
        "What's a family recipe you still remember?",
        "Tell me about a family vacation you'll never forget.",

        // Childhood
        "Describe your childhood home.",
        "What did you love to do as a kid?",
        "What was your favorite toy or game growing up?",
        "Tell me about your best childhood friend.",
        "What was school like for you?",
        "Describe your childhood bedroom.",
        "What's a mischievous thing you did as a kid?",
        "What did you want to be when you grew up?",
        "Tell me about a teacher who shaped you.",
        "What was your neighborhood like growing up?",

        // Love & relationships
        "Tell me about your wedding day.",
        "How did you meet your spouse?",
        "What was your first date like?",
        "Describe the moment you knew you were in love.",
        "Tell me about a love letter you wrote or received.",
        "What's the best advice you've received about love?",
        "Describe a friendship that has meant the most to you.",
        "Tell me about someone who believed in you.",

        // Career & work
        "What was your first job like?",
        "Tell me about a job you loved.",
        "What's the hardest thing you've ever worked on?",
        "Describe a proud moment in your career.",
        "Who was your best boss or mentor, and why?",
        "Tell me about a risk you took professionally.",

        // Memories & moments
        "What are your happiest holiday memories?",
        "Describe a funny moment from your youth.",
        "Tell me about a time you laughed until you cried.",
        "What's the best birthday you ever had?",
        "Tell me about a trip that changed you.",
        "Share a moment you felt truly proud.",
        "Describe a time you were scared but went through with it anyway.",
        "What's something you did that surprised even you?",

        // People
        "Who had the biggest influence on your life?",
        "Tell me about a stranger who made a difference.",
        "Describe someone who always made you feel safe.",
        "Who taught you the most about kindness?",
        "Tell me about a hero of yours.",

        // Lessons & reflection
        "What's the best advice you ever got?",
        "What's a mistake that taught you the most?",
        "What would you tell your younger self?",
        "What's a belief that has changed as you've gotten older?",
        "What are you most grateful for today?",
        "What do you hope people remember about you?",
        "What's a tradition you hope continues in your family?",
        "What's something you wish more people knew about you?",

        // Places & time
        "Describe a place that feels like home.",
        "Tell me about the house you raised your children in.",
        "What did your town look like when you were young?",
        "Share a memory from a place you'll never forget.",

        // Fun prompts
        "What songs take you right back in time?",
        "What was the best meal you ever ate?",
        "Tell me about a pet you loved.",
        "What's a skill you're proud of learning?"
    ]
    
    var micColor: Color {
        Color(red: 0.88, green: 0.52, blue: 0.28)
    }
    
    private var liveAudioLevel: Double {
        audioMonitor.getSmoothedLevel()
    }
    
    private var shouldShowVoiceRings: Bool {
        isRecording && !isPaused && (audioMonitor.isVoiceActive || liveAudioLevel > 0.08)
    }

    private var primaryRecordingControlState: PrimaryRecordingControlState {
        PrimaryRecordingControlPolicy.state(isRecording: isRecording, isPaused: isPaused)
    }

    private func voiceRing(index: Int) -> some View {
        let ringColor: Color = audioMonitor.isVoiceActive ? accent.opacity(0.2) : micColor.opacity(0.2)
        let side: CGFloat = CGFloat(140 + index * 20)
        let scale: Double = 1.0 + liveAudioLevel * (0.10 + Double(index) * 0.04)
        let ringOpacity: Double = 0.25 + liveAudioLevel * 0.45
        return Circle()
            .stroke(ringColor, lineWidth: 2)
            .frame(width: side, height: side)
            .scaleEffect(scale)
            .opacity(ringOpacity)
            .animation(.easeOut(duration: 0.12), value: liveAudioLevel)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 28) {
                    // Custom Back Button
                    HStack {
                        Button(action: {
                            guard !isSaving else { return }
                            if isRecording || isPaused {
                                stopRecording()
                            } else if hasMeaningfulData() {
                                showExitConfirm = true
                            } else {
                                dismiss()
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .medium))
                                .padding(10)
                                .background(Color.black.opacity(0.05))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    // Interruption / backgrounding banner — only shown when the
                    // system (not the user) paused an in-progress recording.
                    if let message = interruptionBannerMessage {
                        InterruptionPauseBanner(message: message, tint: micColor)
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Header + Prompt
                    VStack(spacing: 8) {
                        Text(selectedPrompt ?? "What story would you like to tell?")
                            .font(.customSerifFallback(size: 26))
                            .foregroundColor(accent)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Text("Tap the button and start speaking.")
                            .font(.system(size: 16))
                            .foregroundColor(accent.opacity(0.6))
                    }
                    
                    // Mic Button with enhanced visual feedback
                    Button {
                        if isRecording && !isPaused {
                            pauseRecording()
                        } else if isPaused {
                            resumeRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        ZStack {
                            // Rings only appear when actively recording and speech is detected.
                            if shouldShowVoiceRings {
                                ForEach(0..<3, id: \.self) { i in
                                    voiceRing(index: i)
                                }
                            }

                            // Main mic button with level-responsive scaling
                            Circle()
                                .fill(
                                    isRecording && !isPaused && audioMonitor.isVoiceActive ?
                                        accent : micColor
                                )
                                .frame(width: 120, height: 120)
                                .scaleEffect(
                                    isRecording && !isPaused ?
                                        (1.0 + liveAudioLevel * 0.1) : 1.0
                                )
                                .shadow(color: Color.orange.opacity(0.25),
                                        radius: 10, x: 0, y: 4)
                                .animation(.easeOut(duration: 0.1), value: liveAudioLevel)
                                .animation(.easeInOut(duration: 0.3), value: audioMonitor.isVoiceActive)

                            // Mic icon
                            Image(systemName: (isRecording && !isPaused) ? "pause.fill" : "mic.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(primaryRecordingControlState.accessibilityLabel)
                    .accessibilityValue(primaryRecordingControlState.accessibilityValue)
                    
                    // Real-time Waveform Visualization
                    RealTimeWaveformView(
                        audioMonitor: audioMonitor,
                        isRecording: isRecording,
                        isPaused: isPaused
                    )
                    .padding(.horizontal)
                    
                    // Real-time transcription display
                    if realTimeTranscription.isTranscribing && !realTimeTranscription.currentTranscript.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "text.bubble.fill")
                                    .foregroundColor(accent)
                                Text("Live Transcription:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            Text(realTimeTranscription.currentTranscript)
                                .font(.body)
                                .foregroundColor(accent)
                                .padding(12)
                                .background(Color(red: 1.0, green: 0.96, blue: 0.89))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(accent.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Recording Timer Display
                    if isRecording || isPaused {
                        VStack(spacing: 8) {
                            Text(formatTime(recordingTime))
                                .font(.system(size: 24, weight: .medium, design: .monospaced))
                                .foregroundColor(accent)
                            
                            Text(isPaused ? "Recording Paused" : "Recording...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isPaused ? accent.opacity(0.6) : micColor)
                        }
                        .padding(.top, 16)
                    }
                    
                    // Recording Controls
                    if isRecording || isPaused {
                        VStack(spacing: 16) {
                            HStack(spacing: 20) {
                                recordingControl(
                                    title: "Clear",
                                    icon: "arrow.counterclockwise",
                                    action: clearRecording
                                )
                                recordingControl(
                                    title: isPaused ? "Resume" : "Pause",
                                    icon: isPaused ? "play.fill" : "pause.fill"
                                ) {
                                    isPaused ? resumeRecording() : pauseRecording()
                                }
                                recordingControl(
                                    title: "Stop & Save",
                                    icon: "square.and.arrow.down"
                                ) {
                                    stopRecording()
                                    saveMemory()
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    
                    // Text Entry Toggle
                    if !isRecording && !isPaused {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation {
                                    showTextEntry.toggle()
                                    isTextFocused = true
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "pencil.tip")
                                        .font(.system(size: 20))
                                    Text("Or write here")
                                        .font(.system(size: 16))
                                        .foregroundColor(accent.opacity(0.6))
                                }
                                .padding(10)
                                .background(Color.black.opacity(0.05))
                                .clipShape(Capsule())
                            }
                            .padding(.horizontal)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Text Input
                    if showTextEntry && !isRecording {
                        VStack(spacing: 12) {
                            ZStack(alignment: .topLeading) {
                                if typedText.isEmpty {
                                    Text("Type your memory here...")
                                        .font(.system(size: 16))
                                        .foregroundColor(accent.opacity(0.5))
                                        .padding(.top, 14)
                                        .padding(.leading, 16)
                                }
                                
                                TextEditor(text: $typedText)
                                    .font(.system(size: 16))
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .focused($isTextFocused)
                            }
                            .frame(minHeight: 160, maxHeight: 200)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 1.0, green: 0.97, blue: 0.91))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(accent.opacity(0.2), lineWidth: 1.5)
                            )
                            .shadow(color: Color.black.opacity(0.03),
                                    radius: 3, x: 0, y: 2)
                            
                            // Word count indicator
                            if !typedText.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("\(typedText.split(separator: " ").count) words")
                                        .font(.caption)
                                        .foregroundColor(accent.opacity(0.5))
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Suggestions (max 3)
                    if !isRecording && !isPaused {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Suggestions")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(accent)
                                .padding(.horizontal)
                            
                            ForEach(suggestionPool.prefix(3), id: \.self) { suggestion in
                                Text(suggestion)
                                    .foregroundColor(.black)
                                    .padding()
                                    .frame(maxWidth: .infinity,
                                           alignment: .leading)
                                    .background(
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(
                                                    selectedPrompt == suggestion
                                                    ? Color(red: 0.96, green: 0.88, blue: 0.76)
                                                    : Color(red: 0.98, green: 0.93, blue: 0.80)
                                                )
                                            if selectedPrompt == suggestion {
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(micColor, lineWidth: 2)
                                            }
                                        }
                                    )
                                    .cornerRadius(16)
                                    .shadow(color: Color.black.opacity(0.03),
                                            radius: 3, x: 0, y: 2)
                                    .onTapGesture {
                                        selectedPrompt = suggestion
                                    }
                                    .padding(.horizontal)
                            }

                            HStack {
                                Spacer()
                                Button(action: regenerateSuggestions) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Show different questions")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundColor(accent.opacity(0.7))
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 14)
                                    .background(Color.black.opacity(0.04))
                                    .clipShape(Capsule())
                                }
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .tutorialAnchor(.recordingSaveMemory)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { tutorialCoordinator.reportAnchor(.recordingSaveMemory, rect: geo.frame(in: .global)) }
                            .onChange(of: geo.frame(in: .global)) { _, f in tutorialCoordinator.reportAnchor(.recordingSaveMemory, rect: f) }
                    }
                )
                .padding(.bottom, 48)
            }
            .onTapGesture {
                if selectedPrompt != nil {
                    selectedPrompt = nil
                }
                isTextFocused = false
            }
            
            // Timeout Warning Overlay
            if showTimeoutWarning {
                TimeoutWarningOverlay(
                    countdown: finalCountdown,
                    message: "Recording will save soon to protect your memory"
                )
            }
        }
        .background(Color(red: 1.0, green: 0.96, blue: 0.89)
            .ignoresSafeArea())
        .tint(accent)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    guard hasUnsavedData() else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    saveMemory()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Save Memory")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(hasUnsavedData() ? micColor : Color.gray.opacity(0.5))
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                    .scaleEffect(isKeyboardSavePressed ? 0.95 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isKeyboardSavePressed)
                    .animation(.easeInOut(duration: 0.15), value: hasUnsavedData())
                }
                .disabled(!hasUnsavedData() || isSaving)
                .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                    isKeyboardSavePressed = pressing
                }, perform: {})
                .accessibilityLabel("Save Memory")
                .accessibilityHint("Saves your current written or recorded memory")

                Button {
                    isTextFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18, weight: .medium))
                }
                .foregroundColor(accent)
            }
        }
        .allowsHitTesting(!isSaving)
        .fullScreenCover(isPresented: $isSaving, onDismiss: {
            guard shouldDismissAfterSave else { return }
            shouldDismissAfterSave = false
            dismiss()
        }) {
            ZStack {
                Color(red: 1.0, green: 0.96, blue: 0.89)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(accent)
                    Text("Saving your memory…")
                        .font(.headline)
                        .foregroundColor(accent)
                }
            }
            .interactiveDismissDisabled()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Saving your memory")
        }
        .alert("Exit without saving?", isPresented: $showExitConfirm) {
            Button("Discard and Exit", role: .destructive) {
                clearRecording()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("You have an unsaved memory in progress. If you exit now, your current recording and text will be lost.")
        }
        .alert("Private Cloud Transcription", isPresented: $showCloudTranscriptionDisclosure) {
            Button("Not Now", role: .cancel) { }
            Button("Continue") {
                CloudTranscriptionDisclosure.accept()
                startRecording()
            }
        } message: {
            Text("Saved recordings are uploaded to your private MemoirAI account and sent to OpenAI to create a transcript. You can delete the recording and transcript at any time.")
        }
        .alert(
            "Memory Not Saved",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Please try again.")
        }
        .onAppear {
            tutorialCoordinator.setVisibleScreen(.recordMemory)
            answeredPrompts = viewModel.entries.compactMap { $0.prompt }
            if suggestionPool.isEmpty {
                suggestionPool = unansweredPrompts().shuffled()
            }
            showExitConfirm = false
            tutorialCoordinator.onRecordMemoryViewAppeared(profileID: profileVM.selectedProfile.id)
            
            // Ensure speech recognition permission is requested up-front
            SFSpeechRecognizer.requestAuthorization { status in
                print("🔑 Speech auth status (RecordMemoryView):", status.rawValue)
            }

            configureInterruptionObserver()
        }
        .onDisappear {
            stopRecording()
            interruptionObserver.onInterruptionBegan = nil
            interruptionObserver.onInterruptionEnded = nil
            interruptionObserver.onRouteChangeDeviceUnavailable = nil
            interruptionObserver.onAppBackgrounded = nil
            tutorialCoordinator.clearAnchor(.recordingSaveMemory)
            if tutorialCoordinator.visibleScreen == .recordMemory {
                tutorialCoordinator.setVisibleScreen(.unknown)
            }
        }
        .navigationBarHidden(true)
        // Permission alerts
        .fullScreenCover(isPresented: $permissionManager.showMicrophonePermissionAlert) {
            MicrophonePermissionAlert(
                isPresented: $permissionManager.showMicrophonePermissionAlert,
                onSettingsTap: permissionManager.openSettings
            )
        }
    }
    
    func recordingControl(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(accent)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                Color(red: 1.0, green: 0.96, blue: 0.89)
            )
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
        .disabled(isSaving)
    }

    
    // MARK: - Helpers
    func unansweredPrompts() -> [String] {
        allPrompts.filter { !answeredPrompts.contains($0) }
    }

    func regenerateSuggestions() {
        let unanswered = unansweredPrompts()
        guard !unanswered.isEmpty else {
            suggestionPool = []
            return
        }
        let currentlyShown = Set(suggestionPool.prefix(3))
        let remaining = unanswered.filter { !currentlyShown.contains($0) }
        let nextPool = remaining.count >= 3 ? remaining.shuffled() : unanswered.shuffled()
        withAnimation(.easeInOut(duration: 0.25)) {
            suggestionPool = nextPool
        }
    }
    
    func hasUnsavedData() -> Bool {
        selectedPrompt != nil || !typedText.isEmpty || audioURL != nil
    }
    
    func hasMeaningfulData() -> Bool {
        !typedText.isEmpty || audioURL != nil
    }
    
    // Format time for display (MM:SS)
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // Start recording timer
    func startRecordingTimer(resetElapsedTime: Bool = true) {
        if resetElapsedTime {
            recordingTime = 0
        }
        stopRecordingTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [self] _ in
            guard let recorder = audioRecorder else { return }
            recordingTime = recorder.currentTime
            
            // Check for timeout warnings
            if recordingTime >= countdownStart && recordingTime < maxRecordingDuration {
                // Start 3-second countdown
                let remaining = Int(ceil(maxRecordingDuration - recordingTime))
                finalCountdown = remaining
            } else if recordingTime >= warningThreshold && recordingTime < countdownStart {
                // Show warning overlay (30 seconds before limit)
                showTimeoutWarning = true
            } else if recordingTime >= maxRecordingDuration || !recorder.isRecording {
                // Auto-stop and save
                stopRecording()
                saveMemory()
            }
        }
    }
    
    // Stop recording timer
    func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    // MARK: - Recording
    func startRecording() {
        guard CloudTranscriptionDisclosure.isAccepted() else {
            showCloudTranscriptionDisclosure = true
            return
        }
        // Check microphone permission before starting
        guard permissionManager.isMicrophoneAuthorized else {
            permissionManager.requestMicrophonePermission()
            return
        }
        
        // Configure audio session for optimal speech recognition
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.measurement)
            try session.setActive(true)
            if session.isInputGainSettable {
                try session.setInputGain(1.0)
            }
        } catch {
            print("🔴 Enhanced audio session setup error: \(error.localizedDescription)")
        }
        
        let fileName = UUID().uuidString + ".m4a"
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        
        // Use optimal recording format for speech recognition
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record(forDuration: RecordingDurationPolicy.maximumRecordingDuration) else {
                print("❌ Recorder refused to start")
                return
            }
            audioRecorder = recorder
            Haptics.tap()
            audioURL = fileURL
            isRecording = true
            isPaused = false
            
            // Start audio level monitoring
            if let recorder = audioRecorder {
                audioMonitor.startMonitoring(recorder: recorder)
            }
            
            // Start real-time transcription for better accuracy
            realTimeTranscription.startTranscription()
            
            startRecordingTimer()
        } catch {
            print("❌ Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    func pauseRecording() {
        Haptics.selection()
        audioRecorder?.pause()
        isPaused = true
        recordingTimer?.invalidate() // Pause the timer
        audioMonitor.setIdleState()

        // Pause real-time transcription
        realTimeTranscription.pauseTranscription()

        // Clear live meter visuals immediately while paused.
    }

    func resumeRecording() {
        Haptics.selection()
        guard let recorder = audioRecorder else { return }
        let remaining = RecordingDurationPolicy.remainingDuration(after: recorder.currentTime)
        guard remaining > 0, recorder.record(forDuration: remaining) else {
            stopRecording()
            saveMemory()
            return
        }
        isPaused = false
        interruptionBannerMessage = nil

        // Resume real-time transcription
        realTimeTranscription.resumeTranscription()

        startRecordingTimer(resetElapsedTime: false)
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        interruptionBannerMessage = nil
        stopRecordingTimer() // Stop the timer

        // Hide timeout warning
        showTimeoutWarning = false
        finalCountdown = nil

        // Stop audio level monitoring
        audioMonitor.stopMonitoring()

        // Live text is only a recording aid. The saved memoir is transcribed
        // from the complete audio file after it has uploaded.
        realTimeTranscription.stopTranscription()
        _ = realTimeTranscription.getFinalTranscript()
    }

    func clearRecording() {
        stopRecording()
        if let audioURL, audioURL.isFileURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        audioURL = nil
        recordingTime = 0 // Reset timer
    }

    // MARK: - Interruption / Backgrounding

    /// Wires the shared observer so a phone call, Siri, unplugged headphones, or
    /// the app moving to the background pauses recording the same way tapping
    /// Pause does, instead of silently letting the timer/UI drift out of sync
    /// with reality.
    private func configureInterruptionObserver() {
        interruptionObserver.onInterruptionBegan = {
            guard isRecording, !isPaused else { return }
            pauseRecording()
            interruptionBannerMessage = "Recording paused. Audio was interrupted"
        }
        interruptionObserver.onInterruptionEnded = { _ in
            // Do not auto-resume: keep the existing paused UI and Resume button
            // so the user makes the call themselves.
            guard isPaused else { return }
            interruptionBannerMessage = "Recording paused. Tap Resume to continue"
        }
        interruptionObserver.onRouteChangeDeviceUnavailable = {
            guard isRecording, !isPaused else { return }
            pauseRecording()
            interruptionBannerMessage = "Recording paused. Audio device disconnected"
        }
        interruptionObserver.onAppBackgrounded = {
            guard isRecording, !isPaused else { return }
            pauseRecording()
            interruptionBannerMessage = "Recording paused while MemoirAI was in the background"
        }
    }
    // MARK: – Save & Transcribe (ENHANCED VERSION)
    func saveMemory() {
        guard hasUnsavedData(), !isSaving else { return }
        guard let firebaseUserId = MemoryUserScope.currentFirebaseUserId else {
            saveErrorMessage = "MemoirAI is still connecting to your private account. Your recording is unchanged; check your connection and try saving again."
            return
        }
        isSaving = true
        
        let promptToSave  = selectedPrompt ?? "Untitled Prompt"
        let textToSave    = typedText          // capture before UI reset
        let audioURLToSave = audioURL          // capture
        let profile = profileVM.selectedProfile
        
        // 🔥 ENHANCED: Use background context like RecordingView
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.perform {
            let audioDataToSave = audioURLToSave.flatMap { try? Data(contentsOf: $0) }
            guard audioURLToSave == nil || audioDataToSave?.isEmpty == false else {
                print("❌ Could not read the completed recording; memory was not saved")
                DispatchQueue.main.async {
                    isSaving = false
                    saveErrorMessage = "The completed recording could not be read. Your recording was not deleted; try saving again."
                }
                return
            }

            // 1️⃣ Create & save the entry in background context
            let newEntry = MemoryEntry(context: bgContext)
            newEntry.id           = UUID()
            newEntry.prompt       = promptToSave
            newEntry.text         = textToSave.isEmpty ? nil : textToSave
            newEntry.audioFileURL = audioURLToSave?.absoluteString
            newEntry.transcriptionEditedText = audioURLToSave == nil || textToSave.isEmpty ? nil : textToSave
            newEntry.transcriptionStatus = audioURLToSave == nil ? nil : "queued"
            newEntry.transcriptionLanguage = "en"
            newEntry.audioData    = audioDataToSave
            newEntry.createdAt    = Date()
            newEntry.profileID    = profile.id
            newEntry.firebaseUserId = firebaseUserId
            
            do {
                try bgContext.save()
                FirestoreSyncService.shared.queueMemorySyncWithProfile(
                    newEntry,
                    profile: profile
                )
                
                // 2️⃣ Notify on main thread immediately
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .memorySaved, object: nil)
                    
                    // Track successful recording for review prompts
                    usageTracker.recordingCompleted()
                }
            } catch {
                print("❌ Error saving MemoryEntry:", error)
                DispatchQueue.main.async {
                    isSaving = false
                    saveErrorMessage = "This memory could not be saved on your device. Your draft is unchanged; free some storage and try again."
                }
                return
            }
            
            // 3️⃣ Generate title if needed (if prompt is "Untitled Prompt" and we have text)
            if promptToSave == "Untitled Prompt" || promptToSave == "Untitled" {
                let textForTitle = textToSave.isEmpty ? nil : textToSave
                
                // If we have text now, generate title immediately
                if let text = textForTitle, !text.isEmpty {
                    let entryObjectID = newEntry.objectID
                    Task {
                        await generateAndUpdateTitle(for: entryObjectID, text: text)
                    }
                } else {
                    // If we're waiting for transcription, title will be generated after transcription completes
                }
            }
            DispatchQueue.main.async {
                typedText = ""
                selectedPrompt = nil
                audioURL = nil
                isRecording = false
                isPaused = false
                showExitConfirm = false
                showTextEntry = false
                shouldDismissAfterSave = true
                isSaving = false

                if promptToSave == passedPrompt {
                    UserDefaults.standard.set(true, forKey: promptKey)
                }
            }
        }
    }
    
    // MARK: - Title Generation Helper
    private func generateAndUpdateTitle(for objectID: NSManagedObjectID, text: String) async {
        let titleService = MemoryTitleService()
        if let generatedTitle = await titleService.generateTitle(from: text) {
            let context = PersistenceController.shared.container.newBackgroundContext()
            let saved = await context.perform {
                guard let entry = try? context.existingObject(with: objectID) as? MemoryEntry else {
                    return false
                }
                entry.prompt = generatedTitle
                do {
                    try context.save()
                    return true
                } catch {
                    print("❌ Generated title could not be saved: \(error.localizedDescription)")
                    return false
                }
            }
            guard saved else { return }

            // Post notification on main thread after save completes
            await MainActor.run {
                NotificationCenter.default.post(name: .memorySaved, object: nil)
                print("✅ Title generated and updated: '\(generatedTitle)'")
            }
        }
    }
}

// MARK: - Interruption Pause Banner
/// Small, non-blocking banner shown when the system (not the user) paused an
/// in-progress recording — phone call, Siri, disconnected headphones, or the
/// app moving to the background. Reused by the other recording surfaces.
struct InterruptionPauseBanner: View {
    let message: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Timeout Warning Overlay
struct TimeoutWarningOverlay: View {
    let countdown: Int?
    let message: String
    
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Pulsing background flash
            Color.red.opacity(0.2)
                .ignoresSafeArea()
                .scaleEffect(pulseScale)
                .animation(
                    Animation.easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true),
                    value: pulseScale
                )
                .onAppear {
                    pulseScale = 1.1
                }
            
            // Warning card
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.red)
                
                Text(message)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if let countdown = countdown {
                    Text("\(countdown)")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
    }
}
