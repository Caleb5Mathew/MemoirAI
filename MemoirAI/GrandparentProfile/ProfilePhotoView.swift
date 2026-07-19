// ProfilePhotoView.swift
// MemoirAI

import SwiftUI
import PhotosUI

struct ProfilePhotoView: View {
    @ObservedObject var viewModel: ProfileViewModel
    var onSwitchProfileTapped: () -> Void

    @State private var isShowingRenameAlert = false
    @State private var newName: String = ""
    @StateObject private var subscriptionManager = RCSubscriptionManager.shared

    @State private var showingLibraryPicker = false
    @State private var showingCamera = false

    private let switchButtonInset: CGFloat = 40

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if viewModel.profiles.isEmpty {
                dashedAddProfileBox
            } else {
                profileImageBox
            }

            Button(action: onSwitchProfileTapped) {
                Image(systemName: "arrow.2.circlepath.circle.fill")
                    .resizable()
                    .frame(width: 42, height: 42)
                    .foregroundColor(.orange)
                    .shadow(radius: 4)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
            .offset(x: -switchButtonInset, y: 0)

            if viewModel.profiles.count > 1 && subscriptionManager.hasActiveSubscription {
                VStack {
                    Text("👑")
                        .font(.caption)
                    Text("\(viewModel.profiles.count) profiles")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                .offset(x: 60, y: -60)
            }
        }
        .padding(12)
        .frame(height: 180)
        .sheet(isPresented: $showingLibraryPicker) {
            LibraryPickerView { image in
                if let data = image.jpegData(compressionQuality: 0.8) {
                    var updated = viewModel.selectedProfile
                    updated.photoData = data
                    viewModel.updateProfile(updated)
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPickerView { image in
                if let data = image.jpegData(compressionQuality: 0.8) {
                    var updated = viewModel.selectedProfile
                    updated.photoData = data
                    viewModel.updateProfile(updated)
                }
            }
        }
        .alert("Rename Profile", isPresented: $isShowingRenameAlert) {
            TextField("New name", text: $newName)
            Button("Save") {
                viewModel.updateName(for: viewModel.selectedProfile, to: newName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name for this profile.")
        }
    }

    private var profileImageBox: some View {
        HStack {
            if viewModel.profiles.count > 1 {
                Button {
                    viewModel.selectPreviousProfile()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.gray)
                        .padding()
                }
            } else {
                Spacer().frame(width: 44)
            }

            Spacer()

            ZStack(alignment: .topTrailing) {
                viewModel.selectedProfile.image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
                    .clipped()
                    .transaction { $0.animation = nil }

                Menu {
                    Button("Rename") {
                        newName = viewModel.selectedProfile.name
                        isShowingRenameAlert = true
                    }
                    Button {
                        showingLibraryPicker = true
                    } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                    }
                    Button("Remove Photo", role: .destructive) {
                        viewModel.removePhotoFromSelectedProfile()
                    }
                    if viewModel.profiles.count > 1 {
                        Button("Delete Profile", role: .destructive) {
                            viewModel.deleteSelectedProfile()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .padding(6)
                }
            }
            .frame(width: 180, height: 180)
            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)

            Spacer()

            if viewModel.profiles.count > 1 {
                Button {
                    viewModel.selectNextProfile()
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .padding()
                }
            } else {
                Spacer().frame(width: 44)
            }
        }
    }

    private var dashedAddProfileBox: some View {
        Button {
            onSwitchProfileTapped()
        } label: {
            VStack {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(.gray)

                Text("Add your first profile!")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(.gray.opacity(0.5))
            )
        }
    }
}

// MARK: - Library Picker (UIImagePickerController — supports native crop via allowsEditing)

struct LibraryPickerView: UIViewControllerRepresentable {
    var onPhotoPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: LibraryPickerView

        init(_ parent: LibraryPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            if let image {
                parent.onPhotoPicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Camera Picker (UIImagePickerController)

struct CameraPickerView: UIViewControllerRepresentable {
    var onPhotoPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            if let image {
                parent.onPhotoPicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct ProfilePhotoView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePhotoView(
            viewModel: ProfileViewModel()
        ) {}
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
