import SwiftUI
import CoreData

struct FamilyView: View {
    @StateObject private var familyManager = FamilyManager.shared
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.managedObjectContext) private var context
    
    @State private var showCreateFamily = false
    @State private var showInviteMembers = false
    @State private var showJoinFamily = false
    @State private var selectedTab = 0
    @State private var memoryEntries: [MemoryEntry] = []
    
    // Colors matching your app theme
    private let backgroundColor = Color(red: 0.98, green: 0.94, blue: 0.86)
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundColor.ignoresSafeArea()
                
                if familyManager.currentFamily == nil {
                    // No family state
                    noFamilyView
                } else {
                    // Family exists - show main interface
                    familyMainView
                }
            }
        }
        .onAppear {
            fetchMemoryEntries()
        }
    }
    
    // MARK: - No Family State
    
    private var noFamilyView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 60))
                    .foregroundColor(terracotta)
                
                Text("Start Your Family Stories")
                    .font(.customSerifFallback(size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(accentColor)
                    .multilineTextAlignment(.center)
                
                Text("Create a family group to share your memories with loved ones, or join an existing family.")
                    .font(.body)
                    .foregroundColor(.black.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 16) {
                // Create Family Button
                Button(action: { showCreateFamily = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Family Group")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(terracotta)
                    .cornerRadius(12)
                }
                
                // Join Family Button
                Button(action: { showJoinFamily = true }) {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Join Existing Family")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(accentColor)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(accentColor, lineWidth: 1.5)
                    )
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .sheet(isPresented: $showCreateFamily) {
            CreateFamilyView()
                .environmentObject(familyManager)
                .environmentObject(profileVM)
        }
        .sheet(isPresented: $showJoinFamily) {
            JoinFamilyView()
                .environmentObject(familyManager)
        }
    }
    
    // MARK: - Main Family Interface
    
    private var familyMainView: some View {
        VStack(spacing: 0) {
            // Family Header
            familyHeader
            
            // Tab Selection
            familyTabSelector
            
            // Content based on selected tab
            TabView(selection: $selectedTab) {
                // Family Feed
                FamilyFeedView(memoryEntries: memoryEntries)
                    .environmentObject(familyManager)
                    .tag(0)
                
                // Family Members
                FamilyMembersView()
                    .environmentObject(familyManager)
                    .tag(1)
                
                // Family Settings
                FamilySettingsView()
                    .environmentObject(familyManager)
                    .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .navigationBarHidden(true)
    }
    
    private var familyHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(familyManager.currentFamily?.name ?? "Family")
                        .font(.customSerifFallback(size: 24))
                        .fontWeight(.bold)
                        .foregroundColor(accentColor)
                    
                    Text("\(familyManager.familyMembers.count) members")
                        .font(.subheadline)
                        .foregroundColor(.black.opacity(0.6))
                }
                
                Spacer()
                
                // Invite button for admins
                if familyManager.canUserInviteMembers() {
                    Button(action: { showInviteMembers = true }) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 18))
                            .foregroundColor(terracotta)
                            .padding(10)
                            .background(Color.white)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.1), radius: 2)
                    }
                }
            }
            .padding(.horizontal)
            
            // Family member avatars
            familyMemberAvatars
        }
        .padding(.vertical)
        .background(backgroundColor)
        .sheet(isPresented: $showInviteMembers) {
            InviteFamilyView()
                .environmentObject(familyManager)
        }
    }
    
    private var familyMemberAvatars: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(familyManager.familyMembers.prefix(8)) { member in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(terracotta.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Group {
                                    if let imageData = member.profileImage,
                                       let image = UIImage(data: imageData) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Text(String(member.name.prefix(1)))
                                            .font(.headline)
                                            .foregroundColor(accentColor)
                                    }
                                }
                            )
                            .clipShape(Circle())
                        
                        Text(member.name.split(separator: " ").first ?? "")
                            .font(.caption)
                            .foregroundColor(.black.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                
                if familyManager.familyMembers.count > 8 {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text("+\(familyManager.familyMembers.count - 8)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.black.opacity(0.7))
                        )
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var familyTabSelector: some View {
        HStack(spacing: 0) {
            ForEach(0..<3) { index in
                Button(action: { selectedTab = index }) {
                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: tabIcon(for: index))
                            Text(tabTitle(for: index))
                        }
                        .font(.system(size: 14, weight: selectedTab == index ? .semibold : .medium))
                        .foregroundColor(selectedTab == index ? terracotta : .black.opacity(0.6))
                        
                        Rectangle()
                            .fill(selectedTab == index ? terracotta : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .background(Color.white.opacity(0.8))
    }
    
    private func tabIcon(for index: Int) -> String {
        switch index {
        case 0: return "newspaper"
        case 1: return "person.2"
        case 2: return "gearshape"
        default: return "questionmark"
        }
    }
    
    private func tabTitle(for index: Int) -> String {
        switch index {
        case 0: return "Stories"
        case 1: return "Members"
        case 2: return "Settings"
        default: return ""
        }
    }
    
    // MARK: - Data Fetching
    
    private func fetchMemoryEntries() {
        let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "profileID == %@", profileVM.selectedProfile.id as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntry.createdAt, ascending: false)]
        
        do {
            memoryEntries = try context.fetch(request)
        } catch {
            print("Failed to fetch memory entries: \(error)")
        }
    }
}

// MARK: - Family Feed View

struct FamilyFeedView: View {
    @EnvironmentObject var familyManager: FamilyManager
    let memoryEntries: [MemoryEntry]
    
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let backgroundColor = Color(red: 0.98, green: 0.94, blue: 0.86)
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if familyManager.sharedStories.isEmpty {
                    // Empty state
                    emptyFeedState
                } else {
                    // Shared stories
                    ForEach(familyManager.sharedStories) { sharedStory in
                        if let memoryEntry = memoryEntries.first(where: { $0.id == sharedStory.memoryEntryId }) {
                            SharedStoryCard(sharedStory: sharedStory, memoryEntry: memoryEntry)
                                .environmentObject(familyManager)
                        }
                    }
                }
                
                // Share your stories section
                shareYourStoriesSection
            }
            .padding()
        }
        .background(backgroundColor)
    }
    
    private var emptyFeedState: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 50))
                .foregroundColor(accentColor.opacity(0.6))
            
            Text("No Family Stories Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(accentColor)
            
            Text("Start sharing your memories with family members. They'll appear here for everyone to enjoy and react to.")
                .font(.body)
                .foregroundColor(.black.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 60)
    }
    
    private var shareYourStoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share Your Recent Stories")
                .font(.headline)
                .foregroundColor(accentColor)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(memoryEntries.prefix(5)) { entry in
                        UnsharedStoryCard(memoryEntry: entry)
                            .environmentObject(familyManager)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 20)
    }
}

// MARK: - Supporting Views

struct SharedStoryCard: View {
    @EnvironmentObject var familyManager: FamilyManager
    let sharedStory: SharedStory
    let memoryEntry: MemoryEntry
    
    private let cardBackground = Color(red: 0.98, green: 0.93, blue: 0.80)
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Story header
            HStack {
                Circle()
                    .fill(accentColor.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text("U") // Would be actual user initial
                            .font(.headline)
                            .foregroundColor(accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared by User")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(sharedStory.sharedDate, style: .relative)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            // Story content
            Text(memoryEntry.prompt ?? "Untitled Story")
                .font(.headline)
                .foregroundColor(accentColor)
            
            if let text = memoryEntry.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.black.opacity(0.8))
                    .lineLimit(3)
            }
            
            // Reactions
            reactionBar
            
            // Comments preview
            if !sharedStory.comments.isEmpty {
                commentsPreview
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
    
    private var reactionBar: some View {
        HStack {
            ForEach(StoryReaction.ReactionType.allCases, id: \.self) { reactionType in
                Button(action: {
                    familyManager.addReaction(to: sharedStory.id, reaction: reactionType)
                }) {
                    HStack(spacing: 4) {
                        Text(reactionType.rawValue)
                        
                        let count = sharedStory.reactions.filter { $0.reactionType == reactionType }.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(8)
                }
            }
            
            Spacer()
        }
    }
    
    private var commentsPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sharedStory.comments.prefix(2)) { comment in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.userName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(accentColor)
                        
                        Text(comment.text)
                            .font(.caption)
                            .foregroundColor(.black.opacity(0.7))
                    }
                    
                    Spacer()
                }
            }
            
            if sharedStory.comments.count > 2 {
                Text("View all \(sharedStory.comments.count) comments")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.top, 8)
    }
}

struct UnsharedStoryCard: View {
    @EnvironmentObject var familyManager: FamilyManager
    let memoryEntry: MemoryEntry
    
    private let cardBackground = Color.white
    private let accentColor = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let terracotta = Color(red: 0.88, green: 0.52, blue: 0.28)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(memoryEntry.prompt ?? "Untitled")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(accentColor)
                .lineLimit(2)
            
            if let text = memoryEntry.text, !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .foregroundColor(.black.opacity(0.7))
                    .lineLimit(3)
            }
            
            Button(action: {
                if let familyId = familyManager.currentFamily?.id {
                    familyManager.shareStory(memoryEntry, with: familyId)
                }
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(terracotta)
                .cornerRadius(8)
            }
        }
        .padding()
        .frame(width: 180)
        .background(cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    FamilyView()
        .environmentObject(ProfileViewModel())
} 