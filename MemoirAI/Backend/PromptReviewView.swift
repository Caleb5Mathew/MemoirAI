//
//  PromptReviewView.swift
//  MemoirAI
//
//  Created by user941803 on 5/10/25.
//

import SwiftUI
// For a more structured logging approach in a production app, consider using OSLog.
// import os.log // Uncomment if you want to use OSLog

struct PromptReviewView: View {
    // private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PromptReviewView") // Example for OSLog

    @StateObject private var viewModel = PromptReviewViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Inputs from previous screen
    let transcript: String
    let attachedPhotos: [UIImage]
    let pageCount: Int

    /// Controls navigation to the gallery
    @State private var showGallery = false

    // Initializer for the view itself (structs get memberwise initializers by default)
    // We can't directly print in the implicit init, but onAppear will cover initial state.
    // If a custom init was needed for other reasons, we could print there.
    // init(transcript: String, attachedPhotos: [UIImage], pageCount: Int) {
    //     self.transcript = transcript
    //     self.attachedPhotos = attachedPhotos
    //     self.pageCount = pageCount
    //     print("[PromptReviewView DEBUG] Initializing with transcript (length: \(transcript.count)), photos: \(attachedPhotos.count), pageCount: \(pageCount)")
    //     // _viewModel is initialized separately by @StateObject
    // }

    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("Generating…")
                    .padding()
            } else if let error = viewModel.errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            } else {
                List {
                    Section("Text Prompts") {
                        if viewModel.prompts.isEmpty {
                            Text("No prompts generated yet.")
                                .foregroundColor(.gray)
                        } else {
                            ForEach(viewModel.prompts) { prompt in
                                Text(prompt.text)
                                    .font(.body)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())

                Button(action: {
                    generateAndNavigate()
                }) {
                    Text("Generate Images")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isLoading ? Color.gray : Color.blue)
                        .cornerRadius(8)
                }
                .disabled(viewModel.isLoading)
                .padding(.horizontal)
                .padding(.bottom)

                // Hidden nav link to ImageGalleryView
                NavigationLink(
                    destination: ImageGalleryView(images: viewModel.images),
                    isActive: $showGallery
                ) {
                    EmptyView()
                }
            }
        }
        .navigationTitle("Review Prompts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Optional: additional setup
        }
    

    }
    private func generateAndNavigate() {
        Task {
            await viewModel.generateAndRender(
                transcript: transcript,
                pageCount: pageCount,
                attachedPhotos: attachedPhotos
            )
            
            // Navigate to gallery when images are ready
            if !viewModel.images.isEmpty {
                showGallery = true
            }
        }
    }
}

// Assuming ImagePrompt structure for compilation
/// After




struct PromptReviewView_Previews: PreviewProvider {
    static var previews: some View {
        let _ = print("[PromptReviewView_Previews DEBUG] Setting up previews.")
        NavigationStack {
            PromptReviewView(
                transcript: "Once upon a time in a land far away, there was a brave knight and a friendly dragon.",
                attachedPhotos: [UIImage(systemName: "photo") ?? UIImage()], // Example with one photo
                pageCount: 3
            )
        }
    }
}
