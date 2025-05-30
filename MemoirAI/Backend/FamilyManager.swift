import Foundation
import SwiftUI
import MessageUI

// MARK: - Family Data Models

struct FamilyMember: Identifiable, Codable {
    let id = UUID()
    let name: String
    let email: String
    let profileImage: Data?
    let joinedDate: Date
    let role: FamilyRole
    let isActive: Bool
    
    enum FamilyRole: String, CaseIterable, Codable {
        case admin = "admin"
        case member = "member"
        case viewer = "viewer"  // Can only listen, not record
        
        var displayName: String {
            switch self {
            case .admin: return "Family Admin"
            case .member: return "Family Member"
            case .viewer: return "Listener"
            }
        }
        
        var canRecord: Bool {
            return self != .viewer
        }
        
        var canInviteOthers: Bool {
            return self == .admin
        }
    }
}

struct FamilyGroup: Identifiable, Codable {
    let id = UUID()
    let name: String
    let createdDate: Date
    let adminId: UUID
    var members: [FamilyMember]
    var inviteCode: String?
    
    var memberCount: Int {
        members.filter { $0.isActive }.count
    }
}

struct SharedStory: Identifiable, Codable {
    let id = UUID()
    let memoryEntryId: UUID
    let sharedBy: UUID
    let sharedDate: Date
    let familyGroupId: UUID
    var reactions: [StoryReaction]
    var comments: [StoryComment]
    var isVisible: Bool
}

struct StoryReaction: Identifiable, Codable {
    let id = UUID()
    let userId: UUID
    let userName: String
    let reactionType: ReactionType
    let date: Date
    
    enum ReactionType: String, CaseIterable, Codable {
        case heart = "❤️"
        case laugh = "😄"
        case cry = "😢"
        case wow = "😮"
        case tellMore = "📖"
        
        var displayName: String {
            switch self {
            case .heart: return "Love"
            case .laugh: return "Funny"
            case .cry: return "Touching"
            case .wow: return "Amazing"
            case .tellMore: return "Tell me more"
            }
        }
    }
}

struct StoryComment: Identifiable, Codable {
    let id = UUID()
    let userId: UUID
    let userName: String
    let text: String
    let audioURL: String?  // Voice comment
    let date: Date
    let isVoiceMessage: Bool
}

struct FamilyInvitation: Identifiable, Codable {
    let id = UUID()
    let familyGroupId: UUID
    let familyName: String
    let invitedBy: String
    let invitedEmail: String
    let inviteCode: String
    let expirationDate: Date
    let status: InvitationStatus
    
    enum InvitationStatus: String, Codable {
        case pending = "pending"
        case accepted = "accepted"
        case declined = "declined"
        case expired = "expired"
    }
}

// MARK: - Family Manager

@MainActor
class FamilyManager: ObservableObject {
    static let shared = FamilyManager()
    
    @Published var currentFamily: FamilyGroup?
    @Published var familyMembers: [FamilyMember] = []
    @Published var sharedStories: [SharedStory] = []
    @Published var pendingInvitations: [FamilyInvitation] = []
    @Published var recentActivity: [FamilyActivity] = []
    
    private let userDefaults = UserDefaults.standard
    private let familyKey = "current_family_group"
    private let membersKey = "family_members"
    private let sharedStoriesKey = "shared_stories"
    
    private init() {
        loadFamilyData()
    }
    
    // MARK: - Family Creation & Management
    
    func createFamily(name: String, adminProfile: Profile) {
        let admin = FamilyMember(
            name: adminProfile.name,
            email: "admin@family.local", // Profile doesn't have email, use placeholder
            profileImage: adminProfile.photoData,
            joinedDate: Date(),
            role: .admin,
            isActive: true
        )
        
        let family = FamilyGroup(
            name: name,
            createdDate: Date(),
            adminId: admin.id,
            members: [admin],
            inviteCode: generateInviteCode()
        )
        
        currentFamily = family
        familyMembers = [admin]
        saveFamilyData()
        
        print("🏠 Created family: \(name) with admin: \(adminProfile.name)")
    }
    
    func generateInviteCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Removed confusing characters
        return String((0..<6).map { _ in characters.randomElement()! })
    }
    
    func inviteFamilyMember(email: String, name: String, role: FamilyMember.FamilyRole = .member) {
        guard let family = currentFamily else { return }
        
        let invitation = FamilyInvitation(
            familyGroupId: family.id,
            familyName: family.name,
            invitedBy: getCurrentUserName(),
            invitedEmail: email,
            inviteCode: family.inviteCode ?? generateInviteCode(),
            expirationDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
            status: .pending
        )
        
        pendingInvitations.append(invitation)
        sendInviteEmail(invitation: invitation)
        saveFamilyData()
    }
    
    private func sendInviteEmail(invitation: FamilyInvitation) {
        // This would integrate with your email service
        // For now, we'll generate a shareable link
        let inviteLink = "memoirai://join?code=\(invitation.inviteCode)&family=\(invitation.familyGroupId)"
        print("📧 Invite link generated: \(inviteLink)")
    }
    
    func joinFamilyWithCode(_ code: String) -> Bool {
        // In a real app, this would validate the code with your backend
        // For now, we'll simulate success
        if let invitation = pendingInvitations.first(where: { $0.inviteCode == code && $0.status == .pending }) {
            let newMember = FamilyMember(
                name: "New Member", // This would come from user input
                email: invitation.invitedEmail,
                profileImage: nil,
                joinedDate: Date(),
                role: .member,
                isActive: true
            )
            
            familyMembers.append(newMember)
            currentFamily?.members.append(newMember)
            
            // Update invitation status
            if let index = pendingInvitations.firstIndex(where: { $0.id == invitation.id }) {
                pendingInvitations[index] = FamilyInvitation(
                    familyGroupId: invitation.familyGroupId,
                    familyName: invitation.familyName,
                    invitedBy: invitation.invitedBy,
                    invitedEmail: invitation.invitedEmail,
                    inviteCode: invitation.inviteCode,
                    expirationDate: invitation.expirationDate,
                    status: .accepted
                )
            }
            
            saveFamilyData()
            return true
        }
        return false
    }
    
    // MARK: - Story Sharing
    
    func shareStory(_ memoryEntry: MemoryEntry, with familyId: UUID) {
        let sharedStory = SharedStory(
            memoryEntryId: memoryEntry.id ?? UUID(),
            sharedBy: getCurrentUserId(),
            sharedDate: Date(),
            familyGroupId: familyId,
            reactions: [],
            comments: [],
            isVisible: true
        )
        
        sharedStories.append(sharedStory)
        addFamilyActivity(.storyShared(sharedStory))
        saveFamilyData()
        
        print("📤 Shared story: \(memoryEntry.prompt ?? "Untitled")")
    }
    
    func addReaction(to storyId: UUID, reaction: StoryReaction.ReactionType) {
        if let index = sharedStories.firstIndex(where: { $0.id == storyId }) {
            let newReaction = StoryReaction(
                userId: getCurrentUserId(),
                userName: getCurrentUserName(),
                reactionType: reaction,
                date: Date()
            )
            
            var updatedReactions = sharedStories[index].reactions
            updatedReactions.append(newReaction)
            
            sharedStories[index] = SharedStory(
                memoryEntryId: sharedStories[index].memoryEntryId,
                sharedBy: sharedStories[index].sharedBy,
                sharedDate: sharedStories[index].sharedDate,
                familyGroupId: sharedStories[index].familyGroupId,
                reactions: updatedReactions,
                comments: sharedStories[index].comments,
                isVisible: sharedStories[index].isVisible
            )
            
            addFamilyActivity(.reactionAdded(storyId, reaction))
            saveFamilyData()
        }
    }
    
    func addComment(to storyId: UUID, text: String, audioURL: String? = nil) {
        if let index = sharedStories.firstIndex(where: { $0.id == storyId }) {
            let comment = StoryComment(
                userId: getCurrentUserId(),
                userName: getCurrentUserName(),
                text: text,
                audioURL: audioURL,
                date: Date(),
                isVoiceMessage: audioURL != nil
            )
            
            var updatedComments = sharedStories[index].comments
            updatedComments.append(comment)
            
            sharedStories[index] = SharedStory(
                memoryEntryId: sharedStories[index].memoryEntryId,
                sharedBy: sharedStories[index].sharedBy,
                sharedDate: sharedStories[index].sharedDate,
                familyGroupId: sharedStories[index].familyGroupId,
                reactions: sharedStories[index].reactions,
                comments: updatedComments,
                isVisible: sharedStories[index].isVisible
            )
            
            addFamilyActivity(.commentAdded(storyId, comment))
            saveFamilyData()
        }
    }
    
    // MARK: - Activity Tracking
    
    private func addFamilyActivity(_ activity: FamilyActivity) {
        recentActivity.insert(activity, at: 0)
        // Keep only last 50 activities
        if recentActivity.count > 50 {
            recentActivity = Array(recentActivity.prefix(50))
        }
    }
    
    // MARK: - Data Persistence
    
    private func saveFamilyData() {
        if let family = currentFamily,
           let familyData = try? JSONEncoder().encode(family) {
            userDefaults.set(familyData, forKey: familyKey)
        }
        
        if let membersData = try? JSONEncoder().encode(familyMembers) {
            userDefaults.set(membersData, forKey: membersKey)
        }
        
        if let storiesData = try? JSONEncoder().encode(sharedStories) {
            userDefaults.set(storiesData, forKey: sharedStoriesKey)
        }
    }
    
    private func loadFamilyData() {
        if let familyData = userDefaults.data(forKey: familyKey),
           let family = try? JSONDecoder().decode(FamilyGroup.self, from: familyData) {
            currentFamily = family
        }
        
        if let membersData = userDefaults.data(forKey: membersKey),
           let members = try? JSONDecoder().decode([FamilyMember].self, from: membersData) {
            familyMembers = members
        }
        
        if let storiesData = userDefaults.data(forKey: sharedStoriesKey),
           let stories = try? JSONDecoder().decode([SharedStory].self, from: storiesData) {
            sharedStories = stories
        }
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentUserId() -> UUID {
        // This would get the current user's ID from your authentication system
        return UUID() // Placeholder
    }
    
    private func getCurrentUserName() -> String {
        // This would get the current user's name
        return "Current User" // Placeholder
    }
    
    func isUserFamilyAdmin() -> Bool {
        guard let family = currentFamily else { return false }
        return family.adminId == getCurrentUserId()
    }
    
    func canUserInviteMembers() -> Bool {
        return isUserFamilyAdmin()
    }
}

// MARK: - Family Activity

enum FamilyActivity: Identifiable {
    case storyShared(SharedStory)
    case reactionAdded(UUID, StoryReaction.ReactionType)
    case commentAdded(UUID, StoryComment)
    case memberJoined(FamilyMember)
    
    var id: String {
        switch self {
        case .storyShared(let story): return "story_\(story.id)"
        case .reactionAdded(let storyId, _): return "reaction_\(storyId)_\(UUID())"
        case .commentAdded(let storyId, let comment): return "comment_\(storyId)_\(comment.id)"
        case .memberJoined(let member): return "member_\(member.id)"
        }
    }
    
    var description: String {
        switch self {
        case .storyShared: return "shared a new story"
        case .reactionAdded(_, let reaction): return "reacted with \(reaction.rawValue)"
        case .commentAdded: return "added a comment"
        case .memberJoined(let member): return "\(member.name) joined the family"
        }
    }
} 