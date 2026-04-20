import SwiftUI
import CoreData

struct RecentMemoriesView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileVM: ProfileViewModel
    @StateObject private var permissionManager = PermissionManager.shared
    
    // Optional binding for tab selection - only set when used in MainTabView
    var selectedTab: Binding<Int>? = nil
    /// When true, place memories that can be enhanced at the top.
    /// Used by Storybook's "Enhance" entry point only.
    var prioritizeEnhanceCandidates: Bool = false

    @State private var entries: [MemoryEntry] = []
    @State private var sortAscending = false
    @State private var showSortOptions = false
    @State private var selectedMemoryID: UUID? = nil
    @State private var showCreateMemory = false

    // Design tokens - consistent with app theme
    private let backgroundColor = Color(red: 0.98, green: 0.96, blue: 0.89) // softCream
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    private let cardBackground = Color.white
    private let textPrimary = Color(red: 0.2, green: 0.2, blue: 0.2)
    private let textSecondary = Color(red: 0.5, green: 0.5, blue: 0.5)

    // Sort entries by date
    var sortedEntries: [MemoryEntry] {
        let dateSorted = entries.sorted {
            let d1 = $0.createdAt ?? .distantPast
            let d2 = $1.createdAt ?? .distantPast
            return sortAscending ? d1 < d2 : d1 > d2
        }

        guard prioritizeEnhanceCandidates else {
            return dateSorted
        }

        let enhanceable = dateSorted.filter(isEnhanceCandidate(_:))
        let nonEnhanceable = dateSorted.filter { !isEnhanceCandidate($0) }
        return enhanceable + nonEnhanceable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Custom header - aligned and polished
                    customHeader
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    
                    if entries.isEmpty {
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
                                    .font(.system(size: 56, weight: .light))
                                    .foregroundColor(terracotta.opacity(0.6))
                            }
                            
                            VStack(spacing: 12) {
                                Text("No memories yet")
                                    .font(.system(size: 28, weight: .bold, design: .serif))
                                    .foregroundColor(textPrimary)
                                
                                Text("Start recording or writing your stories.\nThey'll appear here.")
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundColor(textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(6)
                            }
                        }
                        .padding(.horizontal, 40)
                        
                        Spacer()
                        Spacer()
                    } else {
                        // Enhanced list of memories
                        ScrollView {
                            LazyVStack(spacing: 20) {
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
                                
                                // Create New Memory Button
                                Button(action: {
                                    showCreateMemory = true
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 18, weight: .bold))
                                        Text("Create new memory")
                                            .font(.system(size: 18, weight: .bold, design: .serif))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
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
                                .padding(.horizontal, 4)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .navigationBarHidden(true)
                .navigationDestination(isPresented: $showCreateMemory) {
                    RecordMemoryView()
                        .environmentObject(TutorialCoordinator.shared)
                }
                .navigationDestination(item: $selectedMemoryID) { memoryID in
                    Group {
                        if let memory = entries.first(where: { $0.id == memoryID }) {
                            MemoryDetailView(memory: memory)
                                .environmentObject(profileVM)
                                .onAppear {
                                    print("✅ Navigating to MemoryDetailView for memory: \(memory.prompt ?? "Untitled")")
                                }
                        } else {
                            VStack {
                                Text("Memory not found")
                                    .font(.headline)
                                Text("ID: \(memoryID.uuidString)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .onAppear {
                                print("❌ Memory not found for ID: \(memoryID.uuidString)")
                                print("📋 Available memory IDs: \(entries.compactMap { $0.id?.uuidString })")
                            }
                        }
                    }
                }
                .onAppear { 
                    fetchEntries(for: profileVM.selectedProfile.id)
                    // Check for untranscribed memories and request permissions if needed
                    checkPermissionsAndTranscribe()
                }
                .onChange(of: profileVM.selectedProfile.id) { newID in
                    print("🔄 Switched to profile: \(profileVM.selectedProfile.name ?? "Unnamed") (ID: \(newID))")
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
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Custom Header
    private var customHeader: some View {
        HStack(alignment: .center, spacing: 0) {
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textPrimary.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.8),
                                        Color.white.opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                    )
            }
            
            Spacer()
            
            // Title - elegant, bold, serif
            Text("Memories")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundColor(textPrimary)
                .tracking(-0.5) // Tighter letter spacing for elegance
            
            Spacer()
            
            // Sort button - perfectly aligned with back button
            Button(action: { showSortOptions.toggle() }) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(textPrimary.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.8),
                                        Color.white.opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                    )
            }
            .confirmationDialog("Sort Memories", isPresented: $showSortOptions, titleVisibility: .visible) {
                Button("Newest First") { sortAscending = false }
                Button("Oldest First") { sortAscending = true }
                Button("Cancel", role: .cancel) {}
            }
        }
        .frame(height: 50)
    }
    
    // MARK: - Data Operations
    private func isEnhanceCandidate(_ memory: MemoryEntry) -> Bool {
        let hasText = !(memory.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasCharacterDetails = memory.parsedCharacterDetails?.characters.isEmpty == false
        return hasText && !hasCharacterDetails
    }

    private func fetchEntries(for profileID: UUID) {
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = MemoryUserScope.profilePredicate(profileID: profileID)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]

        do {
            entries = try context.fetch(request)
            print("📂 Fetched \(entries.count) memories for profile \(profileVM.selectedProfile.name ?? "Unnamed")")
            
            // Generate titles for existing memories that still have "Untitled Prompt"
            generateTitlesForUntitledMemories()
        } catch {
            print("❌ Failed to fetch: \(error)")
        }
    }
    
    // MARK: - Title Generation for Existing Memories
    private func generateTitlesForUntitledMemories() {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String else {
            print("⚠️ Cannot generate titles: API key not found")
            return
        }
        
        let titleService = MemoryTitleService(apiKey: apiKey)
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
                    bgContext.performAndWait {
                        // Fetch the entry in the background context using objectID
                        let bgEntry = bgContext.object(with: objectID) as! MemoryEntry
                        bgEntry.prompt = generatedTitle
                        try? bgContext.save()
                        
                        // Refresh the main context
                        DispatchQueue.main.async {
                            context.refresh(entry, mergeChanges: true)
                            NotificationCenter.default.post(name: .memorySaved, object: nil)
                            print("✅ Generated title for existing memory: '\(generatedTitle)'")
                        }
                    }
                }
            }
        }
    }

    private func delete(_ entry: MemoryEntry) {
        context.delete(entry)
        try? context.save()
        fetchEntries(for: profileVM.selectedProfile.id)
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
    let entry: MemoryEntry
    let colors: CardColors
    @Binding var selectedMemoryID: UUID?
    @EnvironmentObject private var profileVM: ProfileViewModel
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
    
    // Subtle gradient based on memory type
    private var cardGradient: LinearGradient {
        if entry.hasAudio {
            return LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.98, blue: 0.95),
                    Color(red: 0.98, green: 0.97, blue: 0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.99, green: 0.98, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Check if memory has text content
    private var hasText: Bool {
        entry.text != nil && !(entry.text?.isEmpty ?? true)
    }
    
    // Check if memory has character details
    private var hasCharacterDetails: Bool {
        entry.parsedCharacterDetails?.characters.isEmpty == false
    }
    
    // Check if memory should show Enhance button
    private var shouldShowEnhanceButton: Bool {
        hasText && !hasCharacterDetails
    }
    
    var body: some View {
        Button(action: {
            print("🔵 MemoryCard tapped - Memory ID: \(entry.id?.uuidString ?? "nil")")
            if let id = entry.id {
                selectedMemoryID = id
                print("🔵 Set selectedMemoryID to: \(id.uuidString)")
            } else {
                print("❌ Memory entry has no ID!")
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Header section with title and badges
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayTitle)
                            .font(.system(size: 20, weight: .bold, design: .serif))
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
                                            .font(.system(size: 11, weight: .semibold))
                                        Text("Audio")
                                            .font(.system(size: 11, weight: .medium))
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
                                            .font(.system(size: 11, weight: .semibold))
                                        Text("Text")
                                            .font(.system(size: 11, weight: .medium))
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
                                .font(.system(size: 12, weight: .regular))
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
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Enhance")
                                        .font(.system(size: 12, weight: .semibold))
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
                        } else if hasCharacterDetails {
                            Button(action: { 
                                showCharacterDetails = true 
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Enhanced")
                                        .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(colors.textPrimary.opacity(0.75))
                        .lineLimit(3)
                        .lineSpacing(5)
                        .padding(.horizontal, 22)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                } else {
                    // Audio-only memory placeholder
                    HStack(spacing: 10) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(colors.terracotta.opacity(0.7))
                        Text("Audio recording")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }
            .background(
                ZStack {
                    // Main gradient background
                    cardGradient
                    
                    // Subtle overlay for depth
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
            )
            .cornerRadius(20)
            .overlay(
                AnimatedMemoryBorder(
                    colors: hasCharacterDetails ? [
                        Color(red: 0.1, green: 0.4, blue: 0.2),   // Dark green
                        Color(red: 0.15, green: 0.55, blue: 0.25), // Medium green (matching Enhanced badge)
                        Color(red: 0.2, green: 0.65, blue: 0.35),  // Lighter green
                        Color(red: 0.15, green: 0.55, blue: 0.25), // Medium green
                        Color(red: 0.1, green: 0.45, blue: 0.2),   // Dark green
                        Color(red: 0.15, green: 0.55, blue: 0.25), // Medium green
                        Color(red: 0.1, green: 0.4, blue: 0.2)     // Dark green (complete loop)
                    ] : [
                        colors.terracotta,
                        colors.terracotta,
                        Color(red: 1.0, green: 0.8, blue: 0.4), // Yellow-orange
                        colors.terracotta,
                        Color(red: 0.9, green: 0.3, blue: 0.2), // Red-ish
                        colors.terracotta,
                        colors.terracotta
                    ]
                )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
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
