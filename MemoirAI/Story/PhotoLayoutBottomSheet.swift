import SwiftUI

// MARK: - Photo Layout Bottom Sheet
struct PhotoLayoutBottomSheet: View {
    @Binding var isPresented: Bool
    @Binding var selectedTemplate: PhotoLayoutType?
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    
    // Callback when a template is selected
    var onTemplateSelected: ((PhotoLayoutType) -> Void)?
    
    // Sheet heights
    private let minHeight: CGFloat = 250
    private let maxHeight: CGFloat = 400
    @State private var currentHeight: CGFloat = 250
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background overlay
            if isPresented {
                Color.black
                    .opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring()) {
                            isPresented = false
                        }
                    }
            }
            
            // Bottom sheet
            if isPresented {
                VStack(spacing: 0) {
                    // Handle bar
                    handleBar
                    
                    // Header
                    headerView
                    
                    // Layout templates
                    templatesGrid
                    
                    Spacer()
                }
                .frame(height: currentHeight)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Tokens.bgPrimary)
                        .shadow(color: Tokens.shadow.opacity(0.2), radius: 20, x: 0, y: -5)
                )
                .offset(y: dragOffset.height)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                            isDragging = true
                            
                            // Adjust height while dragging up
                            if value.translation.height < 0 {
                                let newHeight = min(maxHeight, currentHeight - value.translation.height)
                                currentHeight = newHeight
                            }
                        }
                        .onEnded { value in
                            isDragging = false
                            
                            // Dismiss if dragged down enough
                            if value.translation.height > 100 {
                                withAnimation(.spring()) {
                                    isPresented = false
                                    dragOffset = .zero
                                    currentHeight = minHeight
                                }
                            } else {
                                // Snap back
                                withAnimation(.spring()) {
                                    dragOffset = .zero
                                    
                                    // Snap to min or max height
                                    if currentHeight > (minHeight + maxHeight) / 2 {
                                        currentHeight = maxHeight
                                    } else {
                                        currentHeight = minHeight
                                    }
                                }
                            }
                        }
                )
                .transition(.move(edge: .bottom))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
            }
        }
    }
    
    // MARK: - Handle Bar
    private var handleBar: some View {
        VStack {
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 5)
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Add Photo Layout")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Tokens.ink)
            
            Text("Choose a layout or drag onto the page")
                .font(.system(size: 14))
                .foregroundColor(Tokens.ink.opacity(0.6))
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Templates Grid
    private var templatesGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(PhotoLayoutType.allCases, id: \.self) { layoutType in
                    TemplateCard(
                        layoutType: layoutType,
                        isSelected: selectedTemplate == layoutType
                    )
                    .onTapGesture {
                        selectTemplate(layoutType)
                    }
                    .draggable(layoutType) {
                        // Drag preview
                        TemplateCard(
                            layoutType: layoutType,
                            isSelected: true
                        )
                        .scaleEffect(1.1)
                        .opacity(0.8)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Helper Methods
    private func selectTemplate(_ template: PhotoLayoutType) {
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        // Update selection
        selectedTemplate = template
        
        // Notify callback
        onTemplateSelected?(template)
        
        // Auto-dismiss after selection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring()) {
                isPresented = false
            }
        }
    }
}

// MARK: - Template Card Component
struct TemplateCard: View {
    let layoutType: PhotoLayoutType
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Visual representation
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? Tokens.accent : Color.gray.opacity(0.3),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .frame(
                        width: layoutType.defaultSize.width * 0.6,
                        height: layoutType.defaultSize.height * 0.6
                    )
                    .shadow(
                        color: isSelected ? Tokens.accent.opacity(0.3) : Tokens.shadow.opacity(0.1),
                        radius: isSelected ? 8 : 4,
                        x: 0,
                        y: 2
                    )
                
                Image(systemName: layoutType.icon)
                    .font(.system(size: 28))
                    .foregroundColor(isSelected ? Tokens.accent : Tokens.ink.opacity(0.4))
            }
            
            // Label
            VStack(spacing: 4) {
                Text(layoutType.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? Tokens.accent : Tokens.ink)
                
                Text(layoutType.description)
                    .font(.system(size: 11))
                    .foregroundColor(Tokens.ink.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 140, height: 160)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Tokens.accentSoft.opacity(0.1) : Tokens.bgWash)
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Preview
struct PhotoLayoutBottomSheet_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.2)
                .ignoresSafeArea()
            
            PhotoLayoutBottomSheet(
                isPresented: .constant(true),
                selectedTemplate: .constant(nil)
            )
        }
    }
}