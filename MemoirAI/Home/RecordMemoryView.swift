import SwiftUI
import AVFoundation
import Speech
import CoreData

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
    @FocusState private var isTextFocused: Bool
    @State private var answeredPrompts: [String] = []
    @State private var suggestionPool: [String] = []
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var checkpointTimer: Timer?
    @State private var checkpointFiles: [URL] = []
    @State private var lastCheckpointTime: TimeInterval = 0
    @State private var isKeyboardSavePressed = false
    
    // Timeout warning states
    @State private var showTimeoutWarning = false
    @State private var finalCountdown: Int? = nil

    // Interruption / backgrounding state — set whenever the recorder was paused
    // by the system (not by the user tapping Pause) so the UI can explain why.
    @State private var interruptionBannerMessage: String? = nil
    
    // Store picked/cropped images as raw JPEG/PNG data for Core-Data persistence
    @State private var selectedImagesData: [Data] = []
    
    // Constants
    private let maxRecordingDuration: TimeInterval = 3600 // 60 minutes in seconds
    private let checkpointInterval: TimeInterval = 600 // 10 minutes in seconds
    private let warningThreshold: TimeInterval = 3570 // 59:30 (30 seconds before limit)
    private let countdownStart: TimeInterval = 3597 // 59:57 (3 seconds before limit)
    
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
                    .onTapGesture {
                        if isRecording && !isPaused {
                            pauseRecording()
                        } else if isPaused {
                            resumeRecording()
                        } else {
                            startRecording()
                        }
                    }
                    
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
                .disabled(!hasUnsavedData())
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
        .alert("Exit without saving?", isPresented: $showExitConfirm) {
            Button("Discard and Exit", role: .destructive) {
                dismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("You have an unsaved memory in progress. If you exit now, your current recording and text will be lost.")
        }
        .onAppear {
            tutorialCoordinator.setVisibleScreen(.recordMemory)
            answeredPrompts = viewModel.entries.compactMap { $0.prompt }
            if suggestionPool.isEmpty {
                suggestionPool = unansweredPrompts().shuffled()
            }
            showExitConfirm = false
            tutorialCoordinator.onRecordMemoryViewAppeared(profileID: profileVM.selectedProfile.id)
            
            // Request microphone permission if not already granted
            if !permissionManager.isMicrophoneAuthorized {
                permissionManager.requestMicrophonePermission()
            }

            // Ensure speech recognition permission is requested up-front
            SFSpeechRecognizer.requestAuthorization { status in
                print("🔑 Speech auth status (RecordMemoryView):", status.rawValue)
            }

            configureInterruptionObserver()
        }
        .onDisappear {
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
        selectedPrompt != nil || !typedText.isEmpty || audioURL != nil || !selectedImagesData.isEmpty
    }
    
    func hasMeaningfulData() -> Bool {
        !typedText.isEmpty || audioURL != nil || !selectedImagesData.isEmpty
    }
    
    // Format time for display (MM:SS)
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // Start recording timer
    func startRecordingTimer() {
        recordingTime = 0
        checkpointFiles.removeAll()
        lastCheckpointTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            recordingTime += 1
            
            // Check for timeout warnings
            if recordingTime >= countdownStart && recordingTime < maxRecordingDuration {
                // Start 3-second countdown
                let remaining = Int(maxRecordingDuration - recordingTime)
                finalCountdown = remaining
            } else if recordingTime >= warningThreshold && recordingTime < countdownStart {
                // Show warning overlay (30 seconds before limit)
                showTimeoutWarning = true
            } else if recordingTime >= maxRecordingDuration {
                // Auto-stop and save
                stopRecording()
                saveMemory()
            }
            
            // Checkpoint every 10 minutes (only trigger once per interval)
            if recordingTime - lastCheckpointTime >= checkpointInterval && recordingTime > 0 {
                saveCheckpoint()
                lastCheckpointTime = recordingTime
            }
        }
    }
    
    // Save checkpoint (every 10 minutes)
    func saveCheckpoint() {
        guard let currentURL = audioURL else { return }
        
        // Copy current file as checkpoint
        let checkpointURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("checkpoint_\(UUID().uuidString).caf")
        
        do {
            try FileManager.default.copyItem(at: currentURL, to: checkpointURL)
            checkpointFiles.append(checkpointURL)
            print("✅ Checkpoint saved at \(formatTime(recordingTime))")
        } catch {
            print("❌ Failed to save checkpoint: \(error)")
        }
    }
    
    // Stop recording timer
    func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    // MARK: - Recording
    func startRecording() {
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
        
        let fileName = UUID().uuidString + ".caf"
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        
        // Use optimal recording format for speech recognition
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, // Use 32-bit for better quality
            AVLinearPCMIsFloatKey: true, // Use float for better precision
            AVLinearPCMIsBigEndianKey: false
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
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
        audioRecorder?.pause()
        isPaused = true
        recordingTimer?.invalidate() // Pause the timer
        audioMonitor.setIdleState()

        // Pause real-time transcription
        realTimeTranscription.pauseTranscription()

        // Clear live meter visuals immediately while paused.
    }

    func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
        interruptionBannerMessage = nil

        // Resume real-time transcription
        realTimeTranscription.resumeTranscription()

        // Resume timer from current time
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingTime += 1
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        interruptionBannerMessage = nil
        stopRecordingTimer() // Stop the timer

        // Stop checkpoint timer
        checkpointTimer?.invalidate()
        checkpointTimer = nil

        // Hide timeout warning
        showTimeoutWarning = false
        finalCountdown = nil

        // Stop audio level monitoring
        audioMonitor.stopMonitoring()

        // Stop real-time transcription and get final transcript
        realTimeTranscription.stopTranscription()
        let realTimeTranscript = realTimeTranscription.getFinalTranscript()
        if !realTimeTranscript.isEmpty {
            typedText = realTimeTranscript
        }
    }

    func clearRecording() {
        stopRecording()
        audioURL = nil
        recordingTime = 0 // Reset timer

        // Clean up checkpoint files
        for checkpointURL in checkpointFiles {
            try? FileManager.default.removeItem(at: checkpointURL)
        }
        checkpointFiles.removeAll()

        // Audio monitor is already stopped in stopRecording()
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
        guard hasUnsavedData() else { return }
        
        let promptToSave  = selectedPrompt ?? "Untitled Prompt"
        let textToSave    = typedText          // capture before UI reset
        let audioURLToSave = audioURL          // capture
        let imagesToSave   = selectedImagesData // capture
        
        // 🔥 ENHANCED: Use background context like RecordingView
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.perform {
            // 1️⃣ Create & save the entry in background context
            let newEntry = MemoryEntry(context: bgContext)
            newEntry.id           = UUID()
            newEntry.prompt       = promptToSave
            newEntry.text         = textToSave.isEmpty ? nil : textToSave
            newEntry.audioFileURL = audioURLToSave?.absoluteString
            newEntry.audioData    = audioURLToSave.flatMap { try? Data(contentsOf: $0) }
            newEntry.createdAt    = Date()
            newEntry.profileID    = profileVM.selectedProfile.id
            newEntry.firebaseUserId = MemoryUserScope.currentFirebaseUserId
            if newEntry.firebaseUserId == nil {
                print("⚠️ Saving memory without firebaseUserId in RecordMemoryView")
            }
            
            // Photo saving disabled - uncomment below to re-enable
            /*
            for data in imagesToSave {
                let photo = Photo(context: bgContext)
                photo.id = UUID()
                photo.data = data
                photo.memoryEntry = newEntry
            }
            */
            
            do {
                try bgContext.save()
                
                // 2️⃣ Notify on main thread immediately
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .memorySaved, object: nil)
                    
                    // Track successful recording for review prompts
                    usageTracker.recordingCompleted()
                }
            } catch {
                print("❌ Error saving MemoryEntry:", error)
            }
            
            // 3️⃣ Generate title if needed (if prompt is "Untitled Prompt" and we have text)
            if promptToSave == "Untitled Prompt" || promptToSave == "Untitled" {
                let textForTitle = textToSave.isEmpty ? nil : textToSave
                
                // If we have text now, generate title immediately
                if let text = textForTitle, !text.isEmpty {
                    Task {
                        await generateAndUpdateTitle(for: newEntry, text: text, context: bgContext)
                    }
                } else {
                    // If we're waiting for transcription, title will be generated after transcription completes
                }
            }
            
            // 4️⃣ Start transcription using same background context
            if let urlString = newEntry.audioFileURL,
               let fileURL = URL(string: urlString) {
                let entryID = newEntry.id
                if let entryID {
                    BatchTranscriptionManager.shared.markInFlight(entryID)
                }
                // Use enhanced transcription with better accuracy
                SpeechTranscriber.shared.transcribe(url: fileURL) { result in
                    switch result {
                    case .success(let transcript):
                        bgContext.perform {
                            newEntry.text = transcript

                            // Generate title if prompt is still "Untitled Prompt"
                            if newEntry.prompt == "Untitled Prompt" || newEntry.prompt == "Untitled" {
                                Task {
                                    await generateAndUpdateTitle(for: newEntry, text: transcript, context: bgContext)
                                }
                            }

                            try? bgContext.save()

                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .memorySaved, object: nil)
                                print("✅ Enhanced transcription completed: \(transcript.prefix(50))...")
                            }
                        }
                    case .failure(let error):
                        // Leave newEntry.text unset so BatchTranscriptionManager's
                        // "needs transcription" predicate still matches and retries later.
                        print("❌ Enhanced transcription failed: \(error.localizedDescription)")
                    }
                    if let entryID {
                        BatchTranscriptionManager.shared.markComplete(entryID)
                    }
                }
            }
        }
        
        // 4️⃣ Reset UI immediately on main thread (but don't dismiss yet)
        typedText       = ""
        selectedPrompt  = nil
        audioURL        = nil
        isRecording     = false
        isPaused        = false
        showExitConfirm = false
        showTextEntry   = false
        
        // Persist prompt‐of‐the‐day if needed
        if promptToSave == passedPrompt {
            UserDefaults.standard.set(true, forKey: promptKey)
        }
        
        // 🔥 ENHANCED: Brief delay to allow transcription to start, then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
    
    // MARK: - Title Generation Helper
    private func generateAndUpdateTitle(for entry: MemoryEntry, text: String, context: NSManagedObjectContext) async {
        let titleService = MemoryTitleService()
        if let generatedTitle = await titleService.generateTitle(from: text) {
            // Use performAndWait since we're already in an async context and want to wait for the save
            context.performAndWait {
                entry.prompt = generatedTitle
                try? context.save()
            }
            
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
