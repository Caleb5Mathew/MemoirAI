import SwiftUI
import AVFoundation
import CoreData
import PhotosUI
import Speech

struct RecordingView: View {
    @State private var debugBanner: String?
    let prompt: MemoryPrompt
    let chapterTitle: String
    var namespace: Namespace.ID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel

    @State private var typedText: String = ""
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioURL: URL?
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var showExitConfirm = false
    @State private var showSaveToast = false
    @State private var powerLevel: Float = 0.0
    @State private var timer: Timer?

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedImagesData: [Data] = []

    // Colors
    let terracotta = Color(red: 210/255, green: 112/255, blue: 45/255)
    let softCream = Color(red: 253/255, green: 234/255, blue: 198/255)
    let overlayBlack = Color.black.opacity(0.4)

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
                            .multilineTextAlignment(.center)    // center and wrap long text
                            .fixedSize(horizontal: false, vertical: true)  // allow vertical expansion
                            .lineLimit(nil)                      // no limit on lines
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(terracotta)
                            .cornerRadius(16)                    // rounded rect instead of capsule


                        HStack(spacing: 12) {
                            ForEach(0..<3) { i in
                                Circle()
                                    .fill(terracotta)
                                    .frame(width: 12 + CGFloat(i * 2), height: 12 + CGFloat(i * 2))
                                    .scaleEffect(CGFloat(1 + (powerLevel * Float(i + 1))))
                                    .animation(.easeInOut(duration: 0.2), value: powerLevel)
                            }
                        }

                        HStack(spacing: 40) {
                            controlButton(icon: "gobackward", label: "Restart") { clearRecording() }
                            controlButton(icon: isPaused ? "play.fill" : "pause.fill",
                                          label: isPaused ? "Resume" : "Pause") {
                                isPaused ? resumeRecording() : pauseRecording()
                            }
                            controlButton(icon: "square.and.arrow.down", label: "Save") {
                                stopRecording()
                                saveMemory()
                            }
                        }
                    }
                    .frame(maxWidth: geo.size.width * 0.9)
                    .multilineTextAlignment(.center)

                    Text("Or")
                        .foregroundColor(.white)
                        .font(.caption)

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
            .onAppear(perform: setupRecorder)
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
            }
            Text(label)
                .foregroundColor(.white)
                .font(.caption)
        }
    }

    // MARK: - Recorder Lifecycle
    func setupRecorder() {
        // Generate a unique filename with a CAF extension for uncompressed PCM
        let filename = UUID().uuidString + ".caf"
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        
        // 1. Configure your audio session for full mic gain and speaker playback
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setMode(.default)
            try session.setActive(true)
            // If possible, bump the input gain all the way up
            if session.isInputGainSettable {
                try session.setInputGain(1.0)
            }
        } catch {
            print("⚠️ Audio session setup error: \(error)")
        }
        
        // 2. Use uncompressed Linear PCM so you capture full dynamic range
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
            
            // Save state for UI/debugging
            audioURL = fileURL
            isRecording = true
            startMonitoringLevels()
            
            debugBanner = "Recording started with PCM @44.1kHz"
        } catch {
            print("⚠️ Error starting recorder: \(error.localizedDescription)")
            debugBanner = "Recorder error: \(error.localizedDescription)"
        }
    }


    func startMonitoringLevels() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            guard let recorder = audioRecorder else { return }
            recorder.updateMeters()
            let level = max(0.05,
                            min(1.0,
                                pow(10, recorder.averagePower(forChannel: 0) / 20)))
            powerLevel = level
        }
    }

    func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
        isRecording = false
    }

    func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
        isRecording = true
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isPaused = false
        timer?.invalidate()
    }

    func clearRecording() {
        stopRecording()
        audioURL = nil
        typedText = ""
        selectedImagesData.removeAll()
        photoItems.removeAll()
    }

    func saveMemory() {
        let profileID = profileVM.selectedProfile.id
        let newEntry = MemoryEntry(context: context)
        newEntry.id = UUID()
        newEntry.prompt = prompt.text
        newEntry.text = typedText.isEmpty ? nil : typedText
        newEntry.audioFileURL = audioURL?.absoluteString
        newEntry.createdAt = Date()
        newEntry.chapter = chapterTitle
        newEntry.profileID = profileID

        // Create Photo entities and add to the relationship
        for imgData in selectedImagesData {
            let photo = Photo(context: context)
            photo.id = UUID()
            photo.data = imgData
            photo.memoryEntry = newEntry
            // The line above replaces the addToPhotos call
        }

        do {
            try context.save()
            NotificationCenter.default.post(name: .memorySaved, object: nil)

            // Kick off background transcription
            if let urlString = newEntry.audioFileURL,
               let fileURL = URL(string: urlString) {
                SFSpeechRecognizer.requestAuthorization { status in
                    guard status == .authorized else { return }
                    let request = SFSpeechURLRecognitionRequest(url: fileURL)
                    SFSpeechRecognizer()?.recognitionTask(with: request) { result, error in
                        if let r = result, r.isFinal {
                            let transcription = r.bestTranscription.formattedString
                            context.perform {
                                newEntry.text = transcription
                                try? context.save()
                            }
                        }
                    }
                }
            }

            withAnimation { showSaveToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation {
                    showSaveToast = false
                    dismiss()
                }
            }

        } catch {
            print("❌ Error saving Memory: \(error)")
        }
    }

    // MARK: - Unsaved Data Check & Cleanup
    func hasUnsavedData() -> Bool {
        !typedText.isEmpty || audioURL != nil || !selectedImagesData.isEmpty
    }

    func cleanup() {
        timer?.invalidate()
    }
}
