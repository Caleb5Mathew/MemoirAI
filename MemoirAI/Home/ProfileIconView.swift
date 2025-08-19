//
//  ProfileIconView.swift
//  MemoirAI
//
//  Profile icon component for homepage top-right corner
//

import SwiftUI

struct ProfileIconView: View {
    let profile: Profile
    
    private let iconSize: CGFloat = 36
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color(red: 0.98, green: 0.96, blue: 0.89))
                .frame(width: iconSize, height: iconSize)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            // Profile image or default icon
            if let uiImage = profile.uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: iconSize - 4, height: iconSize - 4)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: iconSize * 0.5, weight: .medium))
                    .foregroundColor(Color(red: 0.10, green: 0.22, blue: 0.14))
            }
            
            // Completion indicator
            if profile.isComplete {
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    Spacer()
                }
                .frame(width: iconSize, height: iconSize)
            }
        }
        .contentShape(Circle())
    }
}

#Preview {
    VStack(spacing: 20) {
        // Complete profile with photo
        ProfileIconView(profile: Profile(
            name: "John Doe",
            photoData: nil,
            birthdate: Date(),
            ethnicity: "Hispanic",
            gender: "Male"
        ))
        
        // Incomplete profile
        ProfileIconView(profile: Profile(
            name: "Jane",
            photoData: nil
        ))
    }
    .padding()
}