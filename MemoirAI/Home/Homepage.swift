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

    @State private var disableCameraWiggle: Bool =
        UserDefaults.standard.bool(forKey: HomepageView.cameraWiggleDisabledKey)
    private static let cameraWiggleDisabledKey = "cameraWiggleDisabledKey_v1"

    @State private var showingAddProfile = false

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

                        // YOUR BOOK
                        NavigationLink(destination: StoryPage()) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Your Book")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    Text("Create your life story here!")
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
            .navigationBarHidden(true)
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
        }

        promptCompleted = UserDefaults.standard.bool(forKey: promptOfTheDay)
    }
}

struct HomepageView_Previews: PreviewProvider {
    static var previews: some View {
        HomepageView()
            .environmentObject(ProfileViewModel())
    }
}
