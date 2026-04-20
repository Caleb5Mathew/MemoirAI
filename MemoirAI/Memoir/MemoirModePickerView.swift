//
//  MemoirModePickerView.swift
//  MemoirAI
//
//  Sheet to choose Normal / Parent / Relationships before entering MemoirView.
//

import SwiftUI

struct MemoirModePickerView: View {
    private let colors = ColorTheme()

    @AppStorage(memoirModeKey) private var memoirModeRaw: String = MemoirMode.normal.rawValue
    @Environment(\.dismiss) private var dismiss

    /// Called after the mode is persisted; dismiss is invoked after this.
    var onSelect: (MemoirMode) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Text("Choose Your Memoir")
                                .font(.customSerifFallback(size: 28))
                                .foregroundColor(colors.deepGreen)

                            Text("Which story would you like to tell?")
                                .font(.subheadline)
                                .foregroundColor(colors.deepGreen.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                        VStack(spacing: 14) {
                            modeCard(
                                mode: .normal,
                                title: "My Life Story",
                                description: "Your journey from childhood to today.",
                                systemImage: "book.fill"
                            )
                            modeCard(
                                mode: .parent,
                                title: "Parenthood",
                                description: "The joys and lessons of raising a family.",
                                systemImage: "figure.and.child.holdinghands"
                            )
                            modeCard(
                                mode: .relationships,
                                title: "Love & Relationships",
                                description: "The story of your partnership together.",
                                systemImage: "heart.fill"
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }

                Text("You can always change this later.")
                    .font(.footnote)
                    .foregroundColor(colors.deepGreen.opacity(0.5))
                    .padding(.bottom, 16)
            }
            .background(colors.softCream.ignoresSafeArea())
            .toolbarBackground(colors.softCream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(colors.deepGreen)
                }
            }
        }
    }

    private func modeCard(mode: MemoirMode, title: String, description: String, systemImage: String) -> some View {
        Button {
            memoirModeRaw = mode.rawValue
            onSelect(mode)
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 24))
                    .foregroundColor(colors.terracotta)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(colors.deepGreen)

                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(colors.deepGreen.opacity(0.65))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.tileBackground)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MemoirModePickerView(onSelect: { _ in })
}
