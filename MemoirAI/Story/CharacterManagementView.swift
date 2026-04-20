//
//  CharacterManagementView.swift
//  MemoirAI
//
//  View for managing all characters across memories
//

import SwiftUI
import CoreData

struct CharacterManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var profileVM: ProfileViewModel
    
    @State private var globalCharacters: [GlobalCharacter] = []
    @State private var selectedCharacter: GlobalCharacter?
    @State private var showAppearanceHistory = false
    
    private let softCream = Color(red: 0.98, green: 0.96, blue: 0.89)
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    private let darkText = Color.black.opacity(0.85)
    
    var body: some View {
        ZStack {
            softCream.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                if globalCharacters.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            ForEach(globalCharacters, id: \.id) { globalChar in
                                CharacterRowView(
                                    globalCharacter: globalChar,
                                    profileID: profileVM.selectedProfile.id,
                                    onTap: {
                                        selectedCharacter = globalChar
                                        showAppearanceHistory = true
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Run migration on first load to link existing characters
            let profileID = profileVM.selectedProfile.id
            GlobalCharacterManager.shared.migrateExistingCharacters(for: profileID)
            loadCharacters()
        }
        .sheet(isPresented: $showAppearanceHistory) {
            if let character = selectedCharacter {
                CharacterAppearanceHistoryView(
                    globalCharacter: character,
                    profileID: profileVM.selectedProfile.id
                )
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(darkText)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("My Characters")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundColor(darkText)
            
            Spacer()
            
            Circle().fill(Color.clear).frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.4))
            
            Text("No Characters Yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(darkText)
            
            Text("Add characters to your memories to see them here")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func loadCharacters() {
        let profileID = profileVM.selectedProfile.id
        globalCharacters = GlobalCharacterManager.shared.getAllGlobalCharacters(for: profileID)
    }
}

// MARK: - Character Row View
struct CharacterRowView: View {
    let globalCharacter: GlobalCharacter
    let profileID: UUID
    let onTap: () -> Void
    
    @State private var memoryCount: Int = 0
    
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    private let darkText = Color.black.opacity(0.85)
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(terracotta.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Text(String((globalCharacter.canonicalName ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(terracotta)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(globalCharacter.canonicalName ?? "Unknown")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(darkText)
                    
                    Text("\(memoryCount) \(memoryCount == 1 ? "memory" : "memories")")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(16)
            .background(Color.white.opacity(0.6))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if let globalId = globalCharacter.id {
                memoryCount = GlobalCharacterManager.shared.getMemoryCount(
                    globalCharacterId: globalId,
                    profileID: profileID
                )
            }
        }
    }
}

// MARK: - Character Appearance History View
struct CharacterAppearanceHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let globalCharacter: GlobalCharacter
    let profileID: UUID
    
    @State private var appearances: [(memory: MemoryEntry, character: CharacterDetails.Character)] = []
    
    private let softCream = Color(red: 0.98, green: 0.96, blue: 0.89)
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    private let darkText = Color.black.opacity(0.85)
    
    var body: some View {
        NavigationView {
            ZStack {
                softCream.ignoresSafeArea()
                
                if appearances.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.4))
                        
                        Text("No Appearances Yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(darkText)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            ForEach(Array(appearances.enumerated()), id: \.element.memory.id) { index, appearance in
                                AppearanceCardView(
                                    memory: appearance.memory,
                                    character: appearance.character
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle(globalCharacter.canonicalName ?? "Character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(terracotta)
                }
            }
        }
        .onAppear {
            if let globalId = globalCharacter.id {
                appearances = GlobalCharacterManager.shared.getAllAppearances(
                    globalCharacterId: globalId,
                    profileID: profileID
                )
            }
        }
    }
}

// MARK: - Appearance Card View
struct AppearanceCardView: View {
    let memory: MemoryEntry
    let character: CharacterDetails.Character
    
    private let darkText = Color.black.opacity(0.85)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Memory preview text
            if let text = memory.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(darkText)
                    .lineLimit(3)
            } else {
                Text("Memory")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            Divider()
            
            // Character details for this memory
            VStack(alignment: .leading, spacing: 6) {
                if !character.age.isEmpty {
                    HStack {
                        Text("Age:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Text(character.age)
                            .font(.system(size: 12))
                            .foregroundColor(darkText)
                    }
                }
                
                if !character.ethnicity.isEmpty {
                    HStack {
                        Text("Ethnicity:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Text(character.ethnicity)
                            .font(.system(size: 12))
                            .foregroundColor(darkText)
                    }
                }
                
                if !character.hairAndFeatures.isEmpty {
                    HStack(alignment: .top) {
                        Text("Hair & Features:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Text(character.hairAndFeatures)
                            .font(.system(size: 12))
                            .foregroundColor(darkText)
                            .lineLimit(2)
                    }
                }
                
                if !character.clothes.isEmpty {
                    HStack(alignment: .top) {
                        Text("Clothes:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        Text(character.clothes)
                            .font(.system(size: 12))
                            .foregroundColor(darkText)
                            .lineLimit(2)
                    }
                }
            }
            
            // Date
            if let createdAt = memory.createdAt {
                Text(formatDate(createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(.gray.opacity(0.7))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
