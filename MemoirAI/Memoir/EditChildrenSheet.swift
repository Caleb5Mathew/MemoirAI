// EditChildrenSheet.swift
// MemoirAI — capture / edit the set of children this Parenthood memoir is about.

import SwiftUI

struct EditChildrenSheet: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    /// Local editable copy; committed to the profile on Save.
    @State private var names: [String] = [""]
    @FocusState private var focusedIndex: Int?

    // Match the rest of the app's palette.
    private let cream       = Color(red: 0.98, green: 0.94, blue: 0.86)
    private let deepGreen   = Color(red: 0.10, green: 0.22, blue: 0.14)
    private let terracotta  = Color(red: 0.83, green: 0.45, blue: 0.14)
    private var inputFill: Color { cream.opacity(0.7) }

    private let headerFontSize: CGFloat = 28
    private let bodyFontSize: CGFloat = 18

    private var trimmedNames: [String] {
        names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool { !trimmedNames.isEmpty }

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 28) {
                        header
                            .padding(.top, 24)

                        nameRows
                            .padding(.horizontal, 20)

                        addButton
                            .padding(.horizontal, 20)

                        footerNote
                            .padding(.horizontal, 28)
                            .padding(.top, 4)

                        Spacer(minLength: 24)
                    }
                }

                saveButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            let current = profileVM.selectedProfile.childNames
            if !current.isEmpty {
                names = current
            }
            if names.isEmpty { names = [""] }
            DispatchQueue.main.async { focusedIndex = 0 }
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(deepGreen.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Who is this book for?")
                .font(.customSerifFallback(size: headerFontSize))
                .fontWeight(.light)
                .foregroundColor(deepGreen)
                .multilineTextAlignment(.center)

            Text("Add the children this memoir is about.")
                .font(.system(size: bodyFontSize))
                .fontWeight(.light)
                .foregroundColor(.black.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    private var nameRows: some View {
        VStack(spacing: 12) {
            ForEach(names.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    TextField("Child's name", text: $names[index])
                        .font(.system(size: bodyFontSize))
                        .fontWeight(.light)
                        .foregroundColor(deepGreen)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(false)
                        .focused($focusedIndex, equals: index)
                        .submitLabel(index == names.count - 1 ? .done : .next)
                        .onSubmit {
                            if index < names.count - 1 {
                                focusedIndex = index + 1
                            } else {
                                focusedIndex = nil
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(inputFill)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)

                    if names.count > 1 {
                        Button {
                            removeRow(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(deepGreen.opacity(0.6))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.7))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var addButton: some View {
        Button {
            addRow()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add another child")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(terracotta)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(terracotta.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    private var footerNote: some View {
        Text("Per-child questions are asked once for each name. Questions about your own life are shared across all children.")
            .font(.system(size: 13))
            .fontWeight(.light)
            .foregroundColor(.black.opacity(0.55))
            .multilineTextAlignment(.center)
    }

    private var saveButton: some View {
        Button(action: saveAndDismiss) {
            Text("Save")
                .font(.system(size: bodyFontSize, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSave ? terracotta : terracotta.opacity(0.4))
                .cornerRadius(24)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    // MARK: - Actions

    private func addRow() {
        names.append("")
        DispatchQueue.main.async { focusedIndex = names.count - 1 }
    }

    private func removeRow(at index: Int) {
        guard names.indices.contains(index) else { return }
        names.remove(at: index)
        if names.isEmpty { names = [""] }
    }

    private func saveAndDismiss() {
        let finalNames = trimmedNames
        guard !finalNames.isEmpty else { return }
        var updated = profileVM.selectedProfile
        updated.childNames = finalNames
        profileVM.updateSelectedProfile(with: updated)
        dismiss()
    }
}
