import SwiftUI

// MARK: - Main Storybook View
struct StorybookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profileVM: ProfileViewModel
    
    @State private var currentPage = 0
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [UIImage] = []
    @State private var isCreatingNewBook = false
    
    // Sample pages for the finished book preview
    private let samplePages = MockBookPage.samplePages
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background with subtle parchment gradient
                LinearGradient(
                    colors: [
                        Tokens.bgPrimary,
                        Tokens.bgWash
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Main content
                    GeometryReader { geo in
                        let bookWidth = geo.size.width * Tokens.bookMaxWidthPct
                        let bookHeight = bookWidth * Tokens.pageAspect
                        
                        VStack(spacing: 0) {
                            // Book preview (occupies ~60% of vertical space)
                            if isCreatingNewBook {
                                BlankBookCoverView(
                                    bookWidth: bookWidth,
                                    bookHeight: bookHeight
                                )
                            } else {
                                OpenBookView(
                                    pages: samplePages,
                                    currentPage: $currentPage,
                                    bookWidth: bookWidth,
                                    bookHeight: bookHeight
                                )
                            }
                            
                            Spacer()
                            
                            // Hint row
                            if !isCreatingNewBook && samplePages.count > 1 {
                                Text("Swipe to flip pages")
                                    .font(Tokens.Typography.hint)
                                    .foregroundColor(Tokens.ink.opacity(0.6))
                                    .padding(.top, 20)
                                    .padding(.bottom, 16)
                            }
                            
                            // Action buttons
                            actionButtonsView
                                .padding(.bottom, 30)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerSheet(
                isPresented: $showPhotoPicker,
                onPhotosSelected: { photos in
                    selectedPhotos = photos
                    // Handle photo selection - could integrate with existing photo system
                }
            )
        }
        .onAppear {
            // Reset to first page when view appears
            currentPage = 0
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Tokens.ink.opacity(0.7))
                    .padding(10)
                    .background(Tokens.bgWash)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("Create your book")
                    .font(Tokens.Typography.title)
                    .foregroundColor(Tokens.ink)
                
                Text("Flip through a finished book")
                    .font(Tokens.Typography.subtitle)
                    .foregroundColor(Tokens.ink.opacity(0.7))
            }
            
            Spacer()
            
            // Placeholder for balance
            Color.clear
                .frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }
    
    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        VStack(spacing: 16) {
            // Primary button - Create your own book
            Button(action: {
                isCreatingNewBook = true
                // Navigate to book creation flow
                // This could integrate with existing StoryPage or create new flow
            }) {
                Text("Create your own book")
                    .font(Tokens.Typography.button)
                    .foregroundColor(Tokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(
                                        LinearGradient(
                                            colors: Tokens.primaryOutlineGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 3
                                    )
                            )
                    )
            }
            .accessibilityLabel("Create your own book")
            
            // Secondary button - Add photos
            Button(action: {
                showPhotoPicker = true
            }) {
                Text("Add photos")
                    .font(Tokens.Typography.button)
                    .fontWeight(.medium)
                    .foregroundColor(Tokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Tokens.bgWash)
                            .shadow(
                                color: Tokens.shadow,
                                radius: Tokens.softShadow.radius,
                                x: 0,
                                y: Tokens.softShadow.y
                            )
                    )
            }
            .accessibilityLabel("Add photos")
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview
struct StorybookView_Previews: PreviewProvider {
    static var previews: some View {
        StorybookView()
            .environmentObject(ProfileViewModel())
    }
} 