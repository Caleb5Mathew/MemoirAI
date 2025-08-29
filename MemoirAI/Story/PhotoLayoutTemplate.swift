import SwiftUI

// MARK: - Photo Layout Template System
enum PhotoLayoutType: String, CaseIterable, Codable {
    case portrait = "Portrait"
    case landscape = "Landscape"
    case square = "Square"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .portrait: return "rectangle.portrait"
        case .landscape: return "rectangle"
        case .square: return "square"
        case .custom: return "rectangle.dashed"
        }
    }
    
    var defaultAspectRatio: CGFloat {
        switch self {
        case .portrait: return 3.0 / 4.0  // 3:4 ratio
        case .landscape: return 4.0 / 3.0  // 4:3 ratio
        case .square: return 1.0  // 1:1 ratio
        case .custom: return 1.0  // User definable
        }
    }
    
    var defaultSize: CGSize {
        switch self {
        case .portrait: return CGSize(width: 150, height: 200)
        case .landscape: return CGSize(width: 200, height: 150)
        case .square: return CGSize(width: 175, height: 175)
        case .custom: return CGSize(width: 175, height: 175)
        }
    }
    
    var description: String {
        switch self {
        case .portrait: return "Perfect for portraits"
        case .landscape: return "Great for landscapes"
        case .square: return "Instagram style"
        case .custom: return "Free resize"
        }
    }
}

// MARK: - Photo Layout Model
struct PhotoLayout: Codable, Identifiable {
    let id: UUID
    var type: PhotoLayoutType
    var frame: CGRect  // Position and size on the page
    var imageData: Data?  // The actual photo data
    var imageName: String?  // Optional name/caption
    var rotation: Double = 0  // Rotation angle in degrees
    var borderStyle: BorderStyle = .none
    var isLocked: Bool = false  // Prevent accidental moves
    
    init(type: PhotoLayoutType, frame: CGRect) {
        self.id = UUID()
        self.type = type
        self.frame = frame
    }
    
    // Helper to check if photo is added
    var hasPhoto: Bool {
        imageData != nil
    }
}

// MARK: - Border Styles
enum BorderStyle: String, CaseIterable, Codable {
    case none = "None"
    case thin = "Thin"
    case thick = "Thick"
    case polaroid = "Polaroid"
    case vintage = "Vintage"
    case modern = "Modern"
    
    var strokeWidth: CGFloat {
        switch self {
        case .none: return 0
        case .thin: return 1
        case .thick: return 3
        case .polaroid, .vintage: return 8
        case .modern: return 2
        }
    }
    
    var color: Color {
        switch self {
        case .none: return .clear
        case .thin, .thick: return Color.white
        case .polaroid: return Color.white
        case .vintage: return Color(red: 245/255, green: 238/255, blue: 220/255)
        case .modern: return Color.black
        }
    }
    
    var hasShadow: Bool {
        switch self {
        case .polaroid, .vintage, .modern: return true
        default: return false
        }
    }
}

// MARK: - Layout Template Card Model
struct LayoutTemplate: Identifiable {
    let id = UUID()
    let type: PhotoLayoutType
    var isDragging: Bool = false
    
    // Preview representation
    func previewView() -> some View {
        VStack(spacing: 8) {
            // Template icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .foregroundColor(Tokens.ink.opacity(0.3))
                    )
                    .frame(
                        width: type.defaultSize.width * 0.5,
                        height: type.defaultSize.height * 0.5
                    )
                    .shadow(color: Tokens.shadow.opacity(0.1), radius: 4, x: 0, y: 2)
                
                Image(systemName: type.icon)
                    .font(.system(size: 24))
                    .foregroundColor(Tokens.ink.opacity(0.5))
            }
            
            // Label
            VStack(spacing: 2) {
                Text(type.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Tokens.ink)
                
                Text(type.description)
                    .font(.system(size: 10))
                    .foregroundColor(Tokens.ink.opacity(0.6))
            }
        }
        .frame(width: 120, height: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Tokens.bgPrimary)
                .shadow(color: Tokens.shadow.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

// MARK: - Drag State for Templates
struct DragState {
    var isDragging: Bool = false
    var location: CGPoint = .zero
    var startLocation: CGPoint = .zero
    var template: PhotoLayoutType?
}