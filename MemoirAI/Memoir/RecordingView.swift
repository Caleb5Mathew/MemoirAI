import SwiftUI
import AVFoundation
import CoreData
import PhotosUI
import Speech
import Mixpanel

struct RecordingView: View {
    @State private var debugBanner: String?
    let prompt: MemoryPrompt
    let chapterTitle: String
    var namespace: Namespace.ID
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel
    @StateObject private var audioMonitor = AudioLevelMonitor()

    @State private var typedText: String = ""
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioURL: URL?
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var showExitConfirm = false
    @State private var showSaveToast = false
    @State private var powerLevel: Float = 0.0
    @State private var timer: Timer?
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedImagesData: [Data] = []

    // Colors
    let terracotta = Color(red: 210/255, green: 112/255, blue: 45/255)
    let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)
    let overlayBlack = Color.black.opacity(0.4)
    let accent = Color(red: 0.10, green: 0.22, blue: 0.14)

    // Haptic feedback generators
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    // Grid layout for up to 8 images (4 columns)
    private var columns: [GridItem] {
        Array(repeating: .init(.flexible(), spacing: 8), count: 4)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background image + overlay
                Image(chapterTitle.lowercased())
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                overlayBlack.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer(minLength: geo.size.height * 0.08)

                    // Prompt & audio controls
                    VStack(spacing: 20) {
                        Text(prompt.text)
                            .matchedGeometryEffect(id: prompt.id, in: namespace)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(terracotta)
                            .cornerRadius(16)

                        // Main Recording Button (replaces auto-start)
                        if !isRecording && !isPaused && audioURL == nil {
                            Button(action: startRecording) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(terracotta)
                                            .frame(width: 80, height: 80)
                                            .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                                        
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text("Tap to Record")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                        }

                        // Real-time Waveform Visualization
                        RealTimeWaveformView(
                            audioMonitor: audioMonitor,
                            isRecording: isRecording,
                            isPaused: isPaused
                        )
                        .frame(maxWidth: geo.size.width * 0.8)

                        // Recording Timer Display
                        if isRecording || isPaused {
                            VStack(spacing: 4) {
                                Text(formatTime(recordingTime))
                                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                Text(isPaused ? "Recording Paused" : "Recording...")
                                    .font(.caption)
                                    .foregroundColor(isPaused ? .white.opacity(0.7) : terracotta)
                            }
                        }

                        // Recording Controls (only show when recording or paused)
                        if isRecording || isPaused || audioURL != nil {
                            HStack(spacing: 40) {
                                controlButton(icon: "arrow.counterclockwise", label: "Clear") {
                                    triggerHaptic(.impact(.medium))
                                    clearRecording()
                                }
                                
                                if isRecording || isPaused {
                                    controlButton(icon: isPaused ? "play.fill" : "pause.fill",
                                                  label: isPaused ? "Resume" : "Pause") {
                                        triggerHaptic(.impact(.light))
                                        isPaused ? resumeRecording() : pauseRecording()
                                    }
                                }
                                
                                controlButton(icon: "checkmark.circle.fill", label: "Save") {
                                    triggerHaptic(.impact(.heavy))
                                    stopRecording()
                                    saveMemory()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: geo.size.width * 0.9)
                    .multilineTextAlignment(.center)

                    // — replace your existing "Or" + button HStack with this —
                    ZStack {
                        // centered "Or"
                        Text("Or")
                            .font(.caption)
                            .foregroundColor(.white)

                        // trailing "Save Memory"
                        HStack {
                            Spacer()
                            Button(action: {
                                triggerHaptic(.impact(.heavy))
                                if isRecording { stopRecording() }
                                saveMemory()
                            }) {
                                Text("Save Memory")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(terracotta)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, geo.size.width * 0.05)
                    .offset(y: -12)   // tweak this value to move it up/down

                    // Text entry
                    ZStack(alignment: .topLeading) {
                        if typedText.isEmpty {
                            Text("Type your answer...")
                                .foregroundColor(.gray)
                                .padding(.top, 12)
                                .padding(.leading, 36)
                        }
                        TextEditor(text: $typedText)
                            .font(.system(size: 14))
                            .foregroundColor(.black)
                            .frame(minHeight: 60, maxHeight: 120)
                            .padding(.top, 8)
                            .padding(.leading, 32)
                            .scrollContentBackground(.hidden)
                            .background(softCream)
                            .onTapGesture {
                                triggerHaptic(.selection)
                            }
                        Image(systemName: "pencil")
                            .foregroundColor(.gray)
                            .padding(.top, 14)
                            .padding(.leading, 10)
                    }
                    .background(softCream)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, geo.size.width * 0.05)

                    Text("Add Memory Pictures Here!")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.top, 8)

                    let gridWidth = geo.size.width * 0.9
                    let thumbSize = (gridWidth - 3 * 8) / 4

                    // Photo picker / grid preview
                    PhotosPicker(
                        selection: $photoItems,
                        maxSelectionCount: 8,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        if selectedImagesData.isEmpty {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(softCream)
                                    .frame(height: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.black, style: StrokeStyle(lineWidth: 2, dash: [5]))
                                    )
                                VStack {
                                    Image(systemName: "photo.on.rectangle.angled")
                                    Text("Tap to upload")
                                }
                                .foregroundColor(.gray)
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(0..<8, id: \.self) { idx in
                                    ZStack {
                                        if idx < selectedImagesData.count,
                                           let ui = UIImage(data: selectedImagesData[idx]) {
                                            Image(uiImage: ui)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: thumbSize, height: thumbSize)
                                                .clipped()
                                                .cornerRadius(8)
                                        } else {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(softCream)
                                                .frame(width: thumbSize, height: thumbSize)
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.black, style: StrokeStyle(lineWidth: 2, dash: [5]))
                                                .frame(width: thumbSize, height: thumbSize)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, geo.size.width * 0.05)
                            .frame(height: thumbSize * 2 + 8)
                        }
                    }
                    .padding(.horizontal, geo.size.width * 0.05)
                    .onChange(of: photoItems) { newItems in
                        triggerHaptic(.selection)
                        selectedImagesData.removeAll()
                        for item in newItems {
                            Task {
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    selectedImagesData.append(data)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: geo.size.width)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Back button
                VStack {
                    HStack {
                        Button(action: {
                            triggerHaptic(.impact(.light))
                            if hasUnsavedData() {
                                showExitConfirm = true
                            } else {
                                dismiss()
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.25))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)

                // Save toast
                if showSaveToast {
                    VStack {
                        Spacer()
                        Text("Memory Saved!")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .padding(.bottom, 60)
                            .transition(.opacity)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .confirmationDialog("Exit without saving?", isPresented: $showExitConfirm) {
                Button("Discard and Exit", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: setupAudioSession)
            .onDisappear(perform: cleanup)
        }
    }

    // MARK: - Control Button Helper
    func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(20)
                    .background(terracotta)
                    .clipShape(Circle())
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 0.1), value: isRecording)
            }
            Text(label)
                .foregroundColor(.white)
                .font(.caption)
        }
    }

    // MARK: - Haptic Feedback
    enum HapticType {
        case impact(UIImpactFeedbackGenerator.FeedbackStyle)
        case selection
    }
    
    func triggerHaptic(_ type: HapticType) {
        switch type {
        case .impact(let style):
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.impactOccurred()
        case .selection:
            selectionFeedback.selectionChanged()
        }
    }

    // MARK: - Time Formatting
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Recording Timer
    func startRecordingTimer() {
        recordingTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingTime += 1
        }
    }
    
    func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    // MARK: - Recorder Lifecycle
    func setupAudioSession() {
        // Only set up the audio session, don't start recording automatically
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.default)
            try session.setActive(true)
            if session.isInputGainSettable {
                try session.setInputGain(2.0)
            }
        } catch {
            print("⚠️ Audio session setup error: \(error)")
        }
    }

    func startRecording() {
        triggerHaptic(.impact(.medium))
        
        // Generate a unique filename with a CAF extension for uncompressed PCM
        let filename = UUID().uuidString + ".caf"
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        
        let settings: [String: Any] = [
            AVFormatIDKey:               kAudioFormatLinearPCM,
            AVSampleRateKey:             44_100,
            AVNumberOfChannelsKey:       1,
            AVLinearPCMBitDepthKey:      16,
            AVLinearPCMIsFloatKey:       false,
            AVLinearPCMIsBigEndianKey:   false
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            
            audioURL = fileURL
            isRecording = true
            isPaused = false
            
            // Track recording started
            Mixpanel.mainInstance().track(event: "Started Recording", properties: [
                "chapter_title": chapterTitle,
                "prompt_text": prompt.text
            ])
            
            // Start audio level monitoring
            if let recorder = audioRecorder {
                audioMonitor.startMonitoring(recorder: recorder)
            }
            
            startRecordingTimer()
            debugBanner = "Recording started with PCM @44.1kHz"
        } catch {
            print("⚠️ Error starting recorder: \(error.localizedDescription)")
            debugBanner = "Recorder error: \(error.localizedDescription)"
        }
    }

    func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
        recordingTimer?.invalidate()
    }

    func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingTime += 1
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        stopRecordingTimer()
        audioMonitor.stopMonitoring()
    }

    func clearRecording() {
        stopRecording()
        audioURL = nil
        recordingTime = 0
        typedText = ""
        selectedImagesData.removeAll()
        photoItems.removeAll()
    }
    // MARK: – Save & Transcribe (background + disk photos)
    // MARK: – Save & Transcribe (background + external-storage blobs)
    func saveMemory() {
        // 0️⃣ Don't do anything if there's nothing to save
        guard hasUnsavedData() else { return }
        isSaving = true       // you can overlay a ProgressView if desired

        // Track memory saved
        Mixpanel.mainInstance().track(event: "Saved Memory", properties: [
            "chapter_title": chapterTitle,
            "prompt_text": prompt.text,
            "has_audio": audioURL != nil,
            "has_text": !typedText.isEmpty,
            "has_photos": !selectedImagesData.isEmpty,
            "recording_duration": recordingTime
        ])

        // 1️⃣ Spin up a private background context so we never block the UI
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.perform {
            // 2️⃣ Create the MemoryEntry in the background
            let entry = MemoryEntry(context: bgContext)
            entry.id           = UUID()
            entry.prompt       = prompt.text
            entry.text         = typedText.isEmpty ? nil : typedText
            entry.audioData    = audioURL.flatMap { try? Data(contentsOf: $0) }
            entry.audioFileURL = audioURL?.absoluteString
            entry.createdAt    = Date()
            entry.chapter      = chapterTitle
            entry.profileID    = profileVM.selectedProfile.id

            // 3️⃣ Persist each selected image—Core Data will externalize large blobs
            for data in selectedImagesData {
                let photo = Photo(context: bgContext)
                photo.id           = UUID()
                photo.data         = data
                photo.memoryEntry  = entry
            }

            // 4️⃣ Save the background context
            do {
                try bgContext.save()
            } catch {
                print("❌ BG save failed:", error)
            }

            // 5️⃣ Immediately notify that a new memory was saved (even if no audio)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .memorySaved, object: nil)
            }

            // 6️⃣ Kick off speech-to-text if we have an audio URL
            if let urlString = entry.audioFileURL,
               let fileURL = URL(string: urlString) {
                SFSpeechRecognizer.requestAuthorization { status in
                    guard status == .authorized else { return }
                    let request = SFSpeechURLRecognitionRequest(url: fileURL)
                    SFSpeechRecognizer()?.recognitionTask(with: request) { result, _ in
                        if let r = result, r.isFinal {
                            let transcript = r.bestTranscription.formattedString
                            bgContext.perform {
                                entry.text = transcript
                                try? bgContext.save()
                                // 7️⃣ Post again once transcription finishes (optional)
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: .memorySaved, object: nil)
                                }
                            }
                        }
                    }
                }
            }

            // 8️⃣ Back on the main thread: show toast, then dismiss
            DispatchQueue.main.async {
                isSaving = false
                showSaveToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showSaveToast = false
                    dismiss()
                }
            }
        }
    }


    // Helper – writes image data to disk, returns URL
    func writeImageDataToDisk(data: Data) -> URL? {
        let fileName = UUID().uuidString + ".jpg"
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("❌ Could not write image: \(error)")
            return nil
        }
    }


    // MARK: - Unsaved Data Check & Cleanup
    func hasUnsavedData() -> Bool {
        !typedText.isEmpty || audioURL != nil || !selectedImagesData.isEmpty
    }

    func cleanup() {
        recordingTimer?.invalidate()
        audioMonitor.stopMonitoring()
    }
}
