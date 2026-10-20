import SwiftUI
import CoreData

struct RecentMemoriesView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileVM: ProfileViewModel
    @StateObject private var permissionManager = PermissionManager.shared
    
    // Optional binding for tab selection - only set when used in MainTabView
    var selectedTab: Binding<Int>? = nil
    /// When true, this becomes the scoped enhancement queue instead of the full library.
    var enhancementMode: Bool = false
    var initialMemoirMode: MemoirMode? = nil

    @State private var entries: [MemoryEntry] = []
    @State private var sortAscending = false
    @State private var showSortOptions = false
    @State private var selectedMemoryID: UUID? = nil
    @State private var showCreateMemory = false
    @State private var selectedMemoirMode: MemoirMode? = nil

    // Design tokens - consistent with app theme
    private let backgroundColor = LinenTheme.paper
    private let terracotta = LinenTheme.accent
    private let cardBackground = LinenTheme.card
    private let textPrimary = LinenTheme.ink
    private let textSecondary = LinenTheme.secondary

    private var candidateEntries: [MemoryEntry] {
        enhancementMode ? entries.filter(isEnhanceCandidate(_:)) : entries
    }

    private var availableMemoirModes: [MemoirMode] {
        MemoirModeFilterPolicy.availableModes(in: entries.map(\.memoirMetadata))
    }

    private var filteredEntries: [MemoryEntry] {
        if enhancementMode, selectedMemoirMode == nil {
            return []
        }
        return candidateEntries.filter {
            MemoirModeFilterPolicy.includes($0.memoirMetadata, mode: selectedMemoirMode)
        }
    }

    // Sort entries by date
    var sortedEntries: [MemoryEntry] {
        filteredEntries.sorted {
            let d1 = $0.createdAt ?? .distantPast
            let d2 = $1.createdAt ?? .distantPast
            return sortAscending ? d1 < d2 : d1 > d2
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Custom header - aligned and polished
                    customHeader
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)

                    if enhancementMode {
                        memoirFilterBar
                            .padding(.horizontal, 24)
                            .padding(.bottom, 10)
                    }
                    
                    if sortedEntries.isEmpty {
                        Spacer()

                        // Enhanced empty state with gradient
                        VStack(spacing: 24) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                terracotta.opacity(0.1),
                                                terracotta.opacity(0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 120, height: 120)

                                Image(systemName: "book.closed.fill")
                                    .font(LinenTheme.body(56, weight: .light))
                                    .foregroundColor(terracotta.opacity(0.6))
                            }

                            VStack(spacing: 12) {
                                Text(enhancementMode
                                     ? "No \(selectedMemoirMode?.libraryTitle ?? "scoped") memories to enhance"
                                     : "No memories yet")
                                    .font(LinenTheme.heading(25))
                                    .foregroundColor(textPrimary)

                                Text(enhancementMode
                                     ? "Choose another memoir above, or add more detail from a saved memory."
                                     : "Start recording or writing your stories.\nThey'll appear here.")
                                    .font(LinenTheme.body(17, weight: .regular))
                                    .foregroundColor(textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(6)
                            }
                        }
                        .padding(.horizontal, 40)

                        Spacer()
                    } else {
                        // Enhanced list of memories
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(sortedEntries) { entry in
                                    MemoryCard(
                                        entry: entry,
                                        colors: CardColors(
                                            backgroundColor: backgroundColor,
                                            terracotta: terracotta,
                                            textPrimary: textPrimary,
                                            textSecondary: textSecondary
                                        ),
                                        selectedMemoryID: $selectedMemoryID
                                    )
                                    .contextMenu {
                                        Button(role: .destructive, action: {
                                            delete(entry)
                                        }) {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                        }
                    }

                }
                .adaptiveContentWidth(AdaptiveLayoutPolicy.readableMaxWidth)
                .navigationBarHidden(true)
                .navigationDestination(isPresented: $showCreateMemory) {
                    MemoirView()
                        .environmentObject(TutorialCoordinator.shared)
                }
                .navigationDestination(item: $selectedMemoryID) { memoryID in
                    Group {
                        if let memory = entries.first(where: { $0.id == memoryID }) {
                            MemoryDetailView(memory: memory)
                                .environmentObject(profileVM)
                                .onAppear {
                                    print("Navigating to memory detail")
                                }
                        } else {
                            VStack {
                                Text("Memory not found")
                                    .font(LinenTheme.body(16, weight: .semibold))
                                Text("ID: \(memoryID.uuidString)")
                                    .font(LinenTheme.body(12))
                                    .foregroundColor(.gray)
                            }
                            .onAppear {
                                print("❌ Memory not found for ID: \(memoryID.uuidString.prefix(8))…")
                                print("📋 Available memory count: \(entries.count)")
                            }
                        }
                    }
                }
                .onAppear { 
                    fetchEntries(for: profileVM.selectedProfile.id)
                    selectInitialMemoirModeIfNeeded()
                    // Check for untranscribed memories and request permissions if needed
                    checkPermissionsAndTranscribe()
                }
                .onChange(of: profileVM.selectedProfile.id) { newID in
                    print("🔄 Switched profile (ID: \(newID.uuidString.prefix(8))…)")
                    selectedMemoirMode = enhancementMode ? initialMemoirMode : nil
                    fetchEntries(for: newID)
                    // Check permissions again when switching profiles
                    checkPermissionsAndTranscribe()
                }
                .onReceive(NotificationCenter.default.publisher(for: .memorySaved)) { _ in
                    // Refresh entries when a memory is saved/updated
                    fetchEntries(for: profileVM.selectedProfile.id)
                    // Refresh permission manager state
                    permissionManager.refreshUntranscribedCount()
                }
                // Permission alerts
                .fullScreenCover(isPresented: $permissionManager.showSpeechPermissionAlert) {
                    SpeechRecognitionPermissionAlert(
                        isPresented: $permissionManager.showSpeechPermissionAlert,
                        onSettingsTap: permissionManager.openSettings
                    )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !enhancementMode {
                    createNewMemoryButton
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .adaptiveContentWidth(AdaptiveLayoutPolicy.readableMaxWidth)
                        .background(backgroundColor)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .analyticsScreen("memories")
        }
    }

    // MARK: - Custom Header
    private var customHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            // Back button - perfectly aligned
            Button(action: {
                // If we're in a TabView context (selectedTab is provided), switch to Home tab
                // Otherwise, use dismiss() for other navigation contexts
                if let tabBinding = selectedTab {
                    tabBinding.wrappedValue = 0 // Switch to Home tab (tag 0)
                    print("🔙 Back button: Switching to Home tab")
                } else {
                    dismiss()
                    print("🔙 Back button: Using dismiss()")
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(LinenTheme.body(16, weight: .semibold))
                    .foregroundColor(textPrimary.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(LinenTheme.surface, in: Circle())
            }
            .accessibilityLabel("Back")
            
            if enhancementMode {
                Spacer(minLength: 0)
                Text("Enhance Memories")
                    .font(LinenTheme.heading(25))
                    .foregroundColor(textPrimary)
                    .tracking(-0.5)
                Spacer(minLength: 0)
            } else {
                memoirFilterBar
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Sort button - perfectly aligned with back button
            Button(action: { showSortOptions.toggle() }) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(LinenTheme.body(14, weight: .semibold))
                    .foregroundColor(textPrimary.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(LinenTheme.surface, in: Circle())
            }
            .accessibilityLabel("Sort memories")
            .confirmationDialog("Sort Memories", isPresented: $showSortOptions, titleVisibility: .visible) {
                Button("Newest First") { sortAscending = false }
                Button("Oldest First") { sortAscending = true }
                Button("Cancel", role: .cancel) {}
            }
        }
        .frame(minHeight: 50)
    }

    @ViewBuilder
    private var memoirFilterBar: some View {
        if !enhancementMode || !availableMemoirModes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !enhancementMode {
                        memoirFilterButton(title: "All", mode: nil)
                    }
                    ForEach(availableMemoirModes, id: \.self) { mode in
                        memoirFilterButton(title: mode.libraryTitle, mode: mode)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("memoirLibraryFilter")
        }
    }

    private func memoirFilterButton(title: String, mode: MemoirMode?) -> some View {
        let isSelected = selectedMemoirMode == mode
        return Button {
            selectedMemoirMode = mode
        } label: {
            Text(title)
                .font(LinenTheme.body(14, weight: .semibold))
                .foregroundColor(isSelected ? .white : textPrimary.opacity(0.78))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(isSelected ? terracotta : LinenTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(terracotta.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("memoirFilter_\(mode?.rawValue ?? "all")")
    }

    private var createNewMemoryButton: some View {
        Button(action: {
            showCreateMemory = true
        }) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "plus")
                    .font(LinenTheme.body(18, weight: .bold))
                Text("Create new memory")
                    .font(LinenTheme.heading(18))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .frame(minHeight: 56, alignment: .center)
            .foregroundColor(terracotta)
            .background(
                Color(red: 1.0, green: 0.95, blue: 0.88)
            )
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(terracotta)
            )
        }
        .accessibilityIdentifier("createNewMemoryButton")
    }
    
    // MARK: - Data Operations
    private func isEnhanceCandidate(_ memory: MemoryEntry) -> Bool {
        let hasText = !(memory.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasCharacterDetails = memory.parsedCharacterDetails?.characters.isEmpty == false
        let hasPendingDraft: Bool = {
            guard let id = memory.id, let draft = EnhancementSessionDraft.load(memoryId: id) else { return false }
            return !draft.currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }()
        return hasText && (!hasCharacterDetails || hasPendingDraft)
    }

    private func fetchEntries(for profileID: UUID) {
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = MemoryUserScope.profilePredicate(profileID: profileID)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]

        do {
            entries = try context.fetch(request)
            reconcileSelectedMemoirMode()
            print("📂 Fetched \(entries.count) memories for active profile")
            
            // Generate titles for existing memories that still have "Untitled Prompt"
            generateTitlesForUntitledMemories()
        } catch {
            print("❌ Failed to fetch: \(error)")
        }
    }

    private func selectInitialMemoirModeIfNeeded() {
        guard enhancementMode else { return }
        selectedMemoirMode = initialMemoirMode
        reconcileSelectedMemoirMode()
    }

    private func reconcileSelectedMemoirMode() {
        guard enhancementMode else { return }
        if let selectedMemoirMode, availableMemoirModes.contains(selectedMemoirMode) {
            return
        }
        selectedMemoirMode = availableMemoirModes.first
    }
    
    // MARK: - Title Generation for Existing Memories
    private func generateTitlesForUntitledMemories() {
        let titleService = MemoryTitleService()
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        
        for entry in entries {
            // Check if memory needs a title
            let needsTitle = (entry.prompt == "Untitled Prompt" || entry.prompt == "Untitled" || entry.prompt?.isEmpty == true)
            guard needsTitle, let text = entry.text, !text.isEmpty else { continue }
            
            // Capture the object ID for background context
            let objectID = entry.objectID
            
            // Generate title in background
            Task {
                if let generatedTitle = await titleService.generateTitle(from: text) {
                    do {
                        let didSave = try await bgContext.perform {
                            guard let bgEntry = try bgContext.existingObject(with: objectID) as? MemoryEntry,
                                  !bgEntry.isDeleted else {
                                return false
                            }
                            bgEntry.prompt = generatedTitle
                            try bgContext.save()
                            return true
                        }

                        // The entry may have been deleted while title generation was running.
                        guard didSave,
                              let mainEntry = try context.existingObject(with: objectID) as? MemoryEntry,
                              !mainEntry.isDeleted else {
                            return
                        }
                        context.refresh(mainEntry, mergeChanges: true)
                        NotificationCenter.default.post(name: .memorySaved, object: nil)
                        print("✅ Generated title for existing memory")
                    } catch {
                        print("❌ Failed to save generated memory title: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func delete(_ entry: MemoryEntry) {
        guard MemoryUserScope.belongsToCurrentUser(entry),
              let memoryId = entry.id,
              let firebaseUserId = MemoryUserScope.currentFirebaseUserId else {
            print("⚠️ Refusing to delete a memory outside the active account")
            return
        }
        let profileId = entry.profileID
        let localAudioURL = entry.audioFileURL.flatMap(URL.init(string:))

        FirestoreSyncService.shared.registerPendingMemoryDeletion(
            memoryId: memoryId,
            profileId: profileId,
            firebaseUserId: firebaseUserId
        )
        context.delete(entry)
        do {
            try context.save()
        } catch {
            context.rollback()
            FirestoreSyncService.shared.cancelPendingMemoryDeletion(
                memoryId: memoryId,
                firebaseUserId: firebaseUserId
            )
            print("❌ Failed to delete local memory: \(error.localizedDescription)")
            return
        }

        EnhancementSessionDraft.clear(memoryId: memoryId)
        UserDefaults.standard.removeObject(forKey: "characterDetails_\(memoryId.uuidString)")
        if let localAudioURL, localAudioURL.isFileURL,
           let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           localAudioURL.standardizedFileURL.path.hasPrefix(documentsURL.standardizedFileURL.path + "/") {
            do {
                try FileManager.default.removeItem(at: localAudioURL)
            } catch {
                if (error as NSError).code != NSFileNoSuchFileError {
                    print("⚠️ Failed to remove local memory audio: \(error.localizedDescription)")
                }
            }
        }
        fetchEntries(for: profileVM.selectedProfile.id)
        Task {
            await FirestoreSyncService.shared.deleteMemory(
                memoryId: memoryId,
                profileId: profileId,
                firebaseUserId: firebaseUserId
            )
        }
    }
    
    // MARK: - Permission Management
    
    private func checkPermissionsAndTranscribe() {
        // Check if there are untranscribed memories
        permissionManager.refreshUntranscribedCount()
        
        // If there are untranscribed memories and speech recognition is not authorized,
        // request permission with a professional popup
        if permissionManager.hasUntranscribedMemories && !permissionManager.isSpeechRecognitionAuthorized {
            // Small delay to ensure UI is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                permissionManager.requestSpeechRecognitionPermission()
            }
        }
    }
}

// MARK: - Card Colors
struct CardColors {
    let backgroundColor: Color
    let terracotta: Color
    let textPrimary: Color
    let textSecondary: Color
}

// MARK: - Enhanced Memory Card
struct MemoryCard: View {
    @ObservedObject var entry: MemoryEntry
    let colors: CardColors
    @Binding var selectedMemoryID: UUID?
    @EnvironmentObject private var profileVM: ProfileViewModel
    @StateObject private var transcriptionManager = BatchTranscriptionManager.shared
    @State private var showCharacterDetails = false
    @State private var showEnhancementCoordinator = false
    @State private var isPressed = false
    
    // Extract a better title from the memory
    private var displayTitle: String {
        if let prompt = entry.prompt, !prompt.isEmpty, prompt != "Untitled" {
            return prompt
        }
        // Use first sentence or first 50 chars of text as title
        if let text = entry.text, !text.isEmpty {
            let firstSentence = text.components(separatedBy: ".").first ?? text
            if firstSentence.count > 50 {
                return String(firstSentence.prefix(47)) + "..."
            }
            return firstSentence
        }
        return "Untitled Memory"
    }
    
    // Format date as relative time
    private var formattedDate: String {
        guard let date = entry.createdAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        
        // If more than a week ago, show actual date
        let daysDiff = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysDiff > 7 {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
        return relative
    }
    
    // Check if memory has text content
    private var hasText: Bool {
        entry.text != nil && !(entry.text?.isEmpty ?? true)
    }

    /// True while this specific memory's audio is actively being transcribed
    /// (either by the record flow that created it or a batch retry).
    private var isTranscribingNow: Bool {
        if entry.transcriptionStatus == "queued" || entry.transcriptionStatus == "processing" {
            return true
        }
        guard entry.hasAudio, let id = entry.id else { return false }
        return transcriptionManager.isInFlight(id)
    }
    
    // Check if memory has character details
    private var hasCharacterDetails: Bool {
        entry.parsedCharacterDetails?.characters.isEmpty == false
    }

    /// Guided flow draft still has a question waiting for an answer (user exited mid-session).
    private var hasPendingDraftQuestion: Bool {
        guard let memoryId = entry.id else { return false }
        guard let draft = EnhancementSessionDraft.load(memoryId: memoryId) else { return false }
        return !draft.currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Green "Enhanced" state: has saved character cards and no unanswered pending question in draft.
    private var shouldShowEnhancedState: Bool {
        hasCharacterDetails && !hasPendingDraftQuestion
    }

    // Check if memory should show Enhance button
    private var shouldShowEnhanceButton: Bool {
        hasText && !shouldShowEnhancedState
    }
    
    var body: some View {
        Button(action: {
            print("🔵 MemoryCard tapped - Memory ID: \(entry.id?.uuidString.prefix(8) ?? "nil")…")
            if let id = entry.id {
                selectedMemoryID = id
                print("🔵 Set selectedMemoryID to: \(id.uuidString.prefix(8))…")
            } else {
                print("❌ Memory entry has no ID!")
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header section with title and badges
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayTitle)
                            .font(LinenTheme.heading(20))
                            .foregroundColor(colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Media type indicator with date
                        HStack(spacing: 10) {
                            // Media icon with subtle background
                            Group {
                                if entry.hasAudio {
                                    HStack(spacing: 4) {
                                        Image(systemName: "waveform")
                                            .font(LinenTheme.body(11, weight: .semibold))
                                        Text("Audio")
                                            .font(LinenTheme.body(11, weight: .medium))
                                    }
                                    .foregroundColor(colors.terracotta)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(colors.terracotta.opacity(0.12))
                                    )
                                } else if let text = entry.text, !text.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "text.alignleft")
                                            .font(LinenTheme.body(11, weight: .semibold))
                                        Text("Text")
                                            .font(LinenTheme.body(11, weight: .medium))
                                    }
                                    .foregroundColor(Color(red: 0.3, green: 0.5, blue: 0.7))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.3, green: 0.5, blue: 0.7).opacity(0.12))
                                    )
                                }
                            }
                            
                            // Date with subtle styling
                            Text(formattedDate)
                                .font(LinenTheme.body(12, weight: .regular))
                                .foregroundColor(colors.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Status badges
                    VStack(alignment: .trailing, spacing: 8) {
                        // Enhancement status - show Enhance button if memory has text but no character details
                        if shouldShowEnhanceButton {
                            Button(action: {
                                if GuidedMemoryEnhancementFeature.isEnabled {
                                    showEnhancementCoordinator = true
                                } else {
                                    showCharacterDetails = true
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "sparkles")
                                        .font(LinenTheme.body(11, weight: .semibold))
                                    Text("Enhance")
                                        .font(LinenTheme.body(12, weight: .semibold))
                                }
                                .foregroundColor(colors.terracotta)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    colors.terracotta.opacity(0.15),
                                                    colors.terracotta.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(colors.terracotta.opacity(0.25), lineWidth: 1.5)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if shouldShowEnhancedState {
                            Button(action: { 
                                showCharacterDetails = true 
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(LinenTheme.body(11, weight: .semibold))
                                    Text("Enhanced")
                                        .font(LinenTheme.body(12, weight: .semibold))
                                }
                                .foregroundColor(Color(red: 0.15, green: 0.55, blue: 0.25))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.15, green: 0.55, blue: 0.25).opacity(0.15),
                                                    Color(red: 0.15, green: 0.55, blue: 0.25).opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(Color(red: 0.15, green: 0.55, blue: 0.25).opacity(0.25), lineWidth: 1.5)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 18)
            
            // Divider with gradient
            LinearGradient(
                colors: [
                    colors.textSecondary.opacity(0.15),
                    colors.textSecondary.opacity(0.05),
                    colors.textSecondary.opacity(0.15)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 22)
            
                // Content preview
                if let text = entry.text, !text.isEmpty {
                    Text(text)
                        .font(LinenTheme.body(15, weight: .regular))
                        .foregroundColor(colors.textPrimary.opacity(0.75))
                        .lineLimit(3)
                        .lineSpacing(5)
                        .padding(.horizontal, 22)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                } else {
                    // No transcript yet — distinguish "actively transcribing" from
                    // "queued for automatic retry" so grandparents aren't left
                    // wondering whether anything is happening.
                    HStack(spacing: 10) {
                        if isTranscribingNow {
                            ProgressView()
                                .scaleEffect(0.75)
                            Text("Transcribing…")
                                .font(LinenTheme.body(15, weight: .medium))
                                .foregroundColor(colors.textSecondary)
                        } else if entry.transcriptionStatus == "failed" || entry.transcriptionStatus == "needsRerecording" {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(LinenTheme.body(18))
                                .foregroundColor(colors.terracotta.opacity(0.8))
                            Text(entry.transcriptionStatus == "needsRerecording" ?
                                 "This audio needs to be recorded again." :
                                 "Transcript failed. Open this memory to retry.")
                                .font(LinenTheme.body(14, weight: .medium))
                                .foregroundColor(colors.textSecondary)
                        } else if entry.transcriptionStatus == nil,
                                  URL(string: entry.audioFileURL ?? "")?.pathExtension.lowercased() != "m4a" {
                            Image(systemName: "mic.badge.plus")
                                .font(LinenTheme.body(18))
                                .foregroundColor(colors.terracotta.opacity(0.7))
                            Text("Re-record this older audio to create a transcript.")
                                .font(LinenTheme.body(14, weight: .medium))
                                .foregroundColor(colors.textSecondary)
                        } else if entry.hasAudio {
                            Image(systemName: "waveform.circle.fill")
                                .font(LinenTheme.body(18))
                                .foregroundColor(colors.terracotta.opacity(0.7))
                            Text("Audio saved. Transcript coming soon, we'll retry automatically.")
                                .font(LinenTheme.body(14, weight: .medium))
                                .foregroundColor(colors.textSecondary)
                        } else {
                            Image(systemName: "waveform.circle.fill")
                                .font(LinenTheme.body(18))
                                .foregroundColor(colors.terracotta.opacity(0.7))
                            Text("Audio recording")
                                .font(LinenTheme.body(15, weight: .medium))
                                .foregroundColor(colors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }
            .background(LinenTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(shouldShowEnhancedState ? LinenTheme.forest.opacity(0.3) : LinenTheme.line, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .fullScreenCover(isPresented: $showCharacterDetails) {
            CharacterDetailsQuestionView(memory: entry)
                .environmentObject(profileVM)
        }
        .fullScreenCover(isPresented: $showEnhancementCoordinator) {
            MemoryEnhancementCoordinatorView(memory: entry)
                .environmentObject(profileVM)
        }
    }
}

// MARK: - Notification
extension Notification.Name {
    static let memorySaved = Notification.Name("memorySaved")
}

// MARK: – Backwards Compatibility Alias
// Some older views may still reference `RecentMemoryView`. Provide a type-alias so builds don't break.
typealias RecentMemoryView = RecentMemoriesView

struct AnimatedMemoryBorder: View {
    let colors: [Color]
    @State private var rotation: Double = 0
    
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(
                AngularGradient(
                    colors: colors,
                    center: .center,
                    startAngle: .degrees(rotation),
                    endAngle: .degrees(rotation + 360)
                ),
                lineWidth: 2
            )
            .onAppear {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
