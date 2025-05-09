//
//  StoryPage.swift
//  MemoirAI
//
//  Created by user941803 on 4/23/25.
//

import SwiftUI

// MARK: - Color Theme


struct StoryPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasGenerated = false // Toggle to simulate generation

    let colors = ColorTheme()

    var body: some View {
        ZStack {
            // 📜 Watercolor-style Background
            colors.softCream
                .ignoresSafeArea()
                .overlay(
                    Image("paper_texture") // Optional: watercolor texture
                        .resizable()
                        .scaledToFill()
                        .opacity(0.05)
                )

            VStack(spacing: 24) {
                // 🧭 Custom Back Button
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.black)
                            .padding(10)
                            .background(Color.black.opacity(0.1))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 12)

                // 📖 Title + Subtitle
                VStack(spacing: 4) {
                    Text("Story Page")
                        .font(.customSerifFallback(size: 22))
                        .foregroundColor(.black)

                    Text("See your stories come to life.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                // 📚 BOOK FRAME
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 280, height: 380)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        )

                    if hasGenerated {
                        // Later: Add TabView with image carousel here
                        Text("📖 Your illustrated storybook will appear here.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(colors.deepGreen)
                            .padding()
                    } else {
                        VStack {
                            Text("Your book is ready to be created.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.bottom, 8)

                            Button(action: {
                                withAnimation {
                                    hasGenerated = true
                                }
                            }) {
                                Text("Generate")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(24)
                                    .background(colors.terracotta)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                            }
                        }
                        .blur(radius: 0) // You could apply a blur here if there's real content
                    }
                }

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    StoryPage()
}
