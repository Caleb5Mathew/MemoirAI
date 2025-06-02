import SwiftUI
import AVFoundation
import Speech

struct RecordMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel
    @StateObject private var viewModel = MemoryEntryViewModel()
    @StateObject private var usageTracker = UsageTracker.shared
    @StateObject private var audioMonitor = AudioLevelMonitor()
    
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
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    
    private let passedPrompt: String?
    private let promptKey = "PromptOfTheDayCompleted"
    
    /// Accent color for all pop-ups and interactive text
    private let accent = Color(red: 0.10, green: 0.22, blue: 0.14)
    
    init(promptOfTheDay: String? = nil) {
        self.passedPrompt = promptOfTheDay
        _selectedPrompt = State(initialValue: promptOfTheDay)
    }
    
    let allPrompts: [String] = [
        "What are your favorite family traditions?",
        "Describe your childhood home.",
        "Tell me about when you first met Grandma.",
        "What was your first job like?",
        "What are your happiest holiday memories?",
        "Describe a funny moment from your youth.",
        "What did you love to do as a kid?",
        "Who had the biggest influence on your life?",
        "Tell me about your wedding day."
    ]
    
    var micColor: Color {
        Color(red: 0.88, green: 0.52, blue: 0.28)
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
                        // Animated rings for recording state
                        if isRecording || isPaused {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .stroke(
                                        audioMonitor.isVoiceActive ? 
                                            accent.opacity(0.2) : 
                                            micColor.opacity(0.2), 
                                        lineWidth: 2
                                    )
                                    .frame(width: CGFloat(140 + i * 20),
                                           height: CGFloat(140 + i * 20))
                                    .scaleEffect(audioMonitor.isVoiceActive ? 1.3 : 1.2)
                                    .animation(
                                        Animation.easeOut(duration: audioMonitor.isVoiceActive ? 1.0 : 1.5)
                                            .repeatForever()
                                            .delay(Double(i) * 0.3),
                                        value: isRecording || isPaused
                                    )
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
                                    (1.0 + audioMonitor.getSmoothedLevel() * 0.1) : 1.0
                            )
                            .shadow(color: Color.orange.opacity(0.25),
                                    radius: 10, x: 0, y: 4)
                            .animation(.easeOut(duration: 0.1), value: audioMonitor.getSmoothedLevel())
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
                                        .foregroundColor(accent.opacity(0.6))
                                        .padding(.top, 10)
                                        .padding(.leading, 12)
                                }
                                
                                TextEditor(text: $typedText)
                                    .padding(8)
                                    .focused($isTextFocused)
                            }
                            .frame(height: 140)
                            .background(Color(red: 0.98, green: 0.94, blue: 0.86))
                            .cornerRadius(18)
                            .shadow(color: Color.black.opacity(0.04),
                                    radius: 4, x: 0, y: 2)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Suggestions (max 3)
                    if !isRecording && !isPaused {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Suggestions")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(accent)
                                .padding(.horizontal)
                            
                            ForEach(unansweredPrompts().prefix(3), id: \.self) { suggestion in
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
                        }
                    }
                }
                .padding(.bottom, 48)
            }
            .onTapGesture {
                if selectedPrompt != nil {
                    selectedPrompt = nil
                }
                isTextFocused = false
            }
            
            // Floating Save Button
            if hasUnsavedData() {
                Button(action: saveMemory) {
                    Text("Save Memory")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(micColor)
                        .cornerRadius(18)
                        .shadow(color: Color.black.opacity(0.1),
                                radius: 4, x: 0, y: 2)
                }
                .padding()
                .transition(.scale)
            }
        }
        .background(Color(red: 1.0, green: 0.96, blue: 0.89)
            .ignoresSafeArea())
        .tint(accent)
        .confirmationDialog("Exit without saving?", isPresented: $showExitConfirm) {
            Button("Discard and Exit", role: .destructive) {
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
        .onAppear {
            answeredPrompts = viewModel.entries.compactMap { $0.prompt }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if !granted {
                    print("🔒 Microphone permission not granted")
                }
            }
        }
        .navigationBarHidden(true)
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
    func startRecordingTimer() {
        recordingTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingTime += 1
        }
    }
    
    // Stop recording timer
    func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    // MARK: - Recording
    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.default)
            try session.setActive(true)
            if session.isInputGainSettable {
                try session.setInputGain(2.0)
            }
        } catch {
            print("🔴 Audio session setup error: \(error.localizedDescription)")
        }
        
        let fileName = UUID().uuidString + ".caf"
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
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
            
            startRecordingTimer()
        } catch {
            print("❌ Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
        recordingTimer?.invalidate() // Pause the timer
        
        // Note: We keep audio monitoring active during pause so user can see
        // that audio input is still being detected, just not recorded
    }
    
    func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
        // Resume timer from current time
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingTime += 1
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        stopRecordingTimer() // Stop the timer
        
        // Stop audio level monitoring
        audioMonitor.stopMonitoring()
    }
    
    func clearRecording() {
        stopRecording()
        audioURL = nil
        recordingTime = 0 // Reset timer
        
        // Audio monitor is already stopped in stopRecording()
    }
    // MARK: – Save & Transcribe
    func saveMemory() {
        guard hasUnsavedData() else { return }
        
        let promptToSave = selectedPrompt ?? "Untitled Prompt"
        
        // 1️⃣ Create & save the raw entry
        let newEntry = MemoryEntry(context: context)
        newEntry.id           = UUID()
        newEntry.prompt       = promptToSave
        newEntry.text         = typedText.isEmpty ? nil : typedText
        newEntry.audioFileURL = audioURL?.absoluteString
        newEntry.createdAt    = Date()
        newEntry.profileID    = profileVM.selectedProfile.id
        
        do {
            try context.save()
            NotificationCenter.default.post(name: .memorySaved, object: nil)
            
            // Track successful recording for review prompts
            usageTracker.recordingCompleted()
        } catch {
            print("❌ Error saving MemoryEntry:", error)
        }
        
        // 2️⃣ Start URL‐based transcription
        if let urlString = newEntry.audioFileURL,
           let fileURL = URL(string: urlString) {
            SFSpeechRecognizer.requestAuthorization { status in
                guard status == .authorized else { return }
                let request = SFSpeechURLRecognitionRequest(url: fileURL)
                SFSpeechRecognizer()?.recognitionTask(with: request) { result, error in
                    if let r = result, r.isFinal {
                        let transcript = r.bestTranscription.formattedString
                        context.perform {
                            newEntry.text = transcript
                            try? context.save()
                            // notify again so your list/detail views update
                            NotificationCenter.default.post(name: .memorySaved,
                                                            object: nil)
                        }
                    }
                }
            }
        }
        
        // 3️⃣ Reset UI immediately
        typedText       = ""
        selectedPrompt  = nil
        audioURL        = nil
        isRecording     = false
        isPaused        = false
        showTextEntry   = false
        
        // Persist prompt‐of‐the‐day if needed
        if promptToSave == passedPrompt {
            UserDefaults.standard.set(true, forKey: promptKey)
        }
    }
}
