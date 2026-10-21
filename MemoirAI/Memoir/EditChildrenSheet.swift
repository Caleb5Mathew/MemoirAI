// EditChildrenSheet.swift
// MemoirAI — capture / edit the set of children this Parenthood memoir is about.

import SwiftUI

struct EditChildrenSheet: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    /// Local editable copy; committed to the profile on Save.
    @State private var names: [String] = [""]
    @FocusState private var focusedIndex: Int?

    private var trimmedNames: [String] {
        names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool { !trimmedNames.isEmpty }

    var body: some View {
        ZStack {
            LinenTheme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                            .padding(.top, 20)

                        nameRows
                            .padding(.horizontal, 20)

                        addButton
                            .padding(.horizontal, 20)

                        footerNote
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        Spacer(minLength: 24)
                    }
                    .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    saveButton
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
                        .background(LinenTheme.paper)
                }
            }
        }
        .tint(LinenTheme.accent)
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
                    .font(LinenTheme.body(16, weight: .medium))
                    .foregroundColor(LinenTheme.secondary)
                    .frame(minHeight: 44)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who is this book for?")
                .font(LinenTheme.heading(25))
                .foregroundColor(LinenTheme.ink)
                .multilineTextAlignment(.leading)

            Text("Add the children this memoir is about.")
                .font(LinenTheme.body(16))
                .foregroundColor(LinenTheme.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 20)
    }

    private var nameRows: some View {
        VStack(spacing: 12) {
            ForEach(names.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    TextField("Child's name", text: $names[index])
                        .font(LinenTheme.body(16))
                        .foregroundColor(LinenTheme.ink)
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
                        .background(LinenTheme.surface, in: RoundedRectangle(cornerRadius: 12))

                    if names.count > 1 {
                        Button {
                            removeRow(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(LinenTheme.secondary)
                                .frame(width: 44, height: 44)
                                .background(LinenTheme.surface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove child \(index + 1)")
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
                    .font(LinenTheme.body(15, weight: .medium))
            }
            .foregroundColor(LinenTheme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(LinenTheme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var footerNote: some View {
        Text("Questions about each child are asked once for each name. Questions about your own life are shared across all children.")
            .font(LinenTheme.body(13))
            .foregroundColor(LinenTheme.secondary)
            .multilineTextAlignment(.leading)
    }

    private var saveButton: some View {
        Button(action: saveAndDismiss) {
            Text("Save")
                .font(LinenTheme.body(16, weight: .semibold))
                .foregroundColor(LinenTheme.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSave ? LinenTheme.forest : LinenTheme.forest.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
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
