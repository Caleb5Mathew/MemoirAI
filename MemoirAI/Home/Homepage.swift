// HomepageView.swift
// MemoirAI

import SwiftUI
import PhotosUI
import CoreData

// Wrapper to allow Data to be used with .sheet(item:)
struct IdentifiableData: Identifiable {
    let id = UUID()
    let data: Data
}

struct HomepageView: View {
    // MARK: – Environment & Context
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.managedObjectContext) private var context

    // MARK: – State
    @State private var selectedTab = 0
    let promptOfTheDay = "Tell me about your first job."
    @State private var promptCompleted: Bool = false

    @State private var entries: [MemoryEntry] = []
    private let totalChapters = allChapters.count

    @State private var isShowingPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem? = nil
    @State private var selectedPhotoData: IdentifiableData? = nil

    @State private var disableCameraWiggle: Bool = {
        let localValue = UserDefaults.standard.bool(forKey: HomepageView.cameraWiggleDisabledKey)
        if !localValue {
            // Try iCloud backup
            NSUbiquitousKeyValueStore.default.synchronize()
            let cloudValue = NSUbiquitousKeyValueStore.default.bool(forKey: "memoir_\(HomepageView.cameraWiggleDisabledKey)")
            if cloudValue {
                UserDefaults.standard.set(true, forKey: HomepageView.cameraWiggleDisabledKey)
                return true
            }
        }
        return localValue
    }()
    private static let cameraWiggleDisabledKey = "cameraWiggleDisabledKey_v1"

    @State private var showingAddProfile = false

    @State private var showMemoryRecoveryAlert = false
    @State private var recoveredMemoryCount = 0

    // Animation flag for glowing gradient around the Book Preview button
    @State private var animatePreviewGlow = false

    // MARK: – Computed Properties

    /// How many full chapters have been completed?
    private func completedChaptersCount() -> Int {
        allChapters.filter { chapter in
            let countForChapter = entries.filter {
                ($0.chapter ?? "") == chapter.title &&
                chapter.prompts.map(\.text).contains($0.prompt ?? "")
            }.count
            return countForChapter >= chapter.prompts.count
        }.count
    }

    /// The text to show under "Continue Your Memoir"
    private var progressText: String {
        let done = completedChaptersCount()
        if done == 0 {
            return "No chapters completed yet"
        } else {
            return "\(done) of \(totalChapters) chapters completed"
        }
    }

    // MARK: – Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ─── TOP BAR ─────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memoir")
                            .font(.customSerifFallback(size: 22))
                            .foregroundColor(Color(red: 0.10, green: 0.22, blue: 0.14))

                        if !profileVM.profiles.isEmpty && !profileVM.selectedProfile.name.isEmpty {
                            Text("Hello, \(profileVM.selectedProfile.name)")
                                .font(.subheadline)
                                .foregroundColor(.black.opacity(0.7))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Profile Photo + Title
                        ProfilePhotoView(
                            viewModel: profileVM,
                            disableWiggle: $disableCameraWiggle
                        ) {
                            showingAddProfile = true
                            if !disableCameraWiggle {
                                disableCameraWiggle = true
                                UserDefaults.standard.set(true, forKey: HomepageView.cameraWiggleDisabledKey)
                                
                                // Backup to iCloud for persistence
                                NSUbiquitousKeyValueStore.default.set(true, forKey: "memoir_\(HomepageView.cameraWiggleDisabledKey)")
                                NSUbiquitousKeyValueStore.default.synchronize()
                            }
                        }

                        VStack(spacing: 10) {
                            Text("Your voice.\nYour legacy.")
                                .font(.customSerifFallback(size: 30))
                                .foregroundColor(Color(red: 0.10, green: 0.22, blue: 0.14))
                                .multilineTextAlignment(.center)

                            Text("Capture your stories for future generations — no typing, just talking.")
                                .font(.subheadline)
                                .foregroundColor(Color.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // START RECORDING
                        NavigationLink(destination: RecordMemoryView().environmentObject(profileVM)) {
                            Text("Start Recording")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color(red: 0.83, green: 0.45, blue: 0.14))
                                )
                                .padding(.horizontal)
                                .shadow(color: Color.orange.opacity(0.25), radius: 6, x: 0, y: 3)
                        }

                        // CONTINUE YOUR MEMOIR
                        NavigationLink(destination: MemoirView().environmentObject(profileVM)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Continue Your Memoir")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    Text(progressText)
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.7))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color(red: 0.98, green: 0.93, blue: 0.80))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                            .padding(.horizontal)
                        }

                        // 📖 LIVE MEMOIR PREVIEW (Coming Soon Screen)
                        NavigationLink(destination: buildEditor()) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Memoir Preview")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    Text("Coming Soon - Browse generated pages")
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.7))
                                }
                                Spacer()
                                Image(systemName: "book")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color(red: 0.98, green: 0.93, blue: 0.80))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                            .padding(.horizontal)
                        }
                        
                        // YOUR BOOK (Premium Gradient Outline)
                        NavigationLink(destination: StoryPage()
                            .environmentObject(profileVM)
                        ) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Your Book")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    Text("Generate your life story here!")
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.7))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(red: 0.98, green: 0.93, blue: 0.80))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                AngularGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.orange,
                                                        Color.yellow,
                                                        Color.red.opacity(0.8),
                                                        Color.orange
                                                    ]),
                                                    center: .center,
                                                    angle: .degrees(animatePreviewGlow ? 360 : 0)
                                                ),
                                                lineWidth: 3
                                            )
                                    )
                            )
                            .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
                            .padding(.horizontal)
                            .onAppear {
                                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                                    animatePreviewGlow = true
                                }
                            }
                        }

                        Spacer(minLength: 36)
                    }
                    .padding(.top, 24)
                }
                .onAppear {
                    resetDailyPromptIfNeeded()
                    fetchEntries()
                }
                .onChange(of: profileVM.selectedProfile.id) { _ in
                    fetchEntries()
                }
            }
            .background(Color(red: 0.98, green: 0.94, blue: 0.86).ignoresSafeArea())
            .sheet(isPresented: $showingAddProfile) {
                AddProfileView()
                    .environmentObject(profileVM)
            }
            .photosPicker(isPresented: $isShowingPhotoPicker, selection: $photoSelection, matching: .images)
            .onChange(of: photoSelection) { newItem in
                if let newItem = newItem {
                    loadPhotoData(newItem)
                }
            }
            .sheet(item: $selectedPhotoData) { wrapper in
                CropSheetView(photoData: wrapper.data) { croppedData in
                    // profileVM.addProfile(...) as needed
                }
            }
            .alert("Memories Recovered!", isPresented: $showMemoryRecoveryAlert) {
                Button("Great!") {}
            } message: {
                Text("We found and recovered \(recoveredMemoryCount) of your memories that were previously missing.")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MemoriesRecovered"))) { notification in
                if let count = notification.object as? Int, count > 0 {
                    recoveredMemoryCount = count
                    showMemoryRecoveryAlert = true
                }
            }
            .statusBarHidden(true)
        }
    }

    // MARK: – Data Fetching & Helpers

    private func fetchEntries() {
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSPredicate(
            format: "profileID == %@", profileVM.selectedProfile.id as CVarArg
        )
        do {
            entries = try context.fetch(request)
        } catch {
            print("Failed to fetch entries:", error)
        }
    }

    private func loadPhotoData(_ newItem: PhotosPickerItem) {
        Task {
            do {
                if let data = try await newItem.loadTransferable(type: Data.self) {
                    selectedPhotoData = IdentifiableData(data: data)
                }
            } catch {
                print("Failed to load data:", error)
            }
        }
    }

    private func resetDailyPromptIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = UserDefaults.standard.object(forKey: "PromptCompletedDate") as? Date

        if lastDate == nil ||
           Calendar.current.compare(today, to: lastDate!, toGranularity: .day) != .orderedSame {
            UserDefaults.standard.set(false, forKey: promptOfTheDay)
            UserDefaults.standard.set(today, forKey: "PromptCompletedDate")
            
            // Backup to iCloud for persistence
            NSUbiquitousKeyValueStore.default.set(false, forKey: "memoir_\(promptOfTheDay)")
            NSUbiquitousKeyValueStore.default.set(today, forKey: "memoir_PromptCompletedDate")
            NSUbiquitousKeyValueStore.default.synchronize()
        }

        // Try local first, then iCloud backup
        var localCompleted = UserDefaults.standard.bool(forKey: promptOfTheDay)
        if !localCompleted {
            NSUbiquitousKeyValueStore.default.synchronize()
            localCompleted = NSUbiquitousKeyValueStore.default.bool(forKey: "memoir_\(promptOfTheDay)")
            if localCompleted {
                UserDefaults.standard.set(true, forKey: promptOfTheDay)
            }
        }
        
        promptCompleted = localCompleted
    }

    // Helper to build editor view lazily
    private func buildEditor() -> some View {
        let ctx = context
        let profID = profileVM.selectedProfile.id
        var pages: [EditorPage] = {
            let req: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
            req.predicate = NSPredicate(format: "profileID == %@", profID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let mems = (try? ctx.fetch(req)) ?? []
            return EditorPage.pages(from: mems, context: ctx)
        }()

        // Insert cover page at front
        let coverKey = "coverSettings_\(profID.uuidString)"
        let cover: CoverSettings = {
            if let data = UserDefaults.standard.data(forKey: coverKey),
               let ct = try? JSONDecoder().decode(CoverSettings.self, from: data) {
                return ct
            }
            return CoverSettings(title: "Stories of My Life", subtitle: "", accentHex: "000000", coverPhotoData: nil)
        }()

        let coverPage = EditorPage(title: cover.title, body: "", photo: cover.coverPhotoData, memory: nil, context: ctx, isCover: true)
        pages.insert(coverPage, at: 0)
        return BookEditorPrototypeView(profileID: profID, pages: pages)
    }
}

struct HomepageView_Previews: PreviewProvider {
    static var previews: some View {
        HomepageView()
            .environmentObject(ProfileViewModel())
    }
}
