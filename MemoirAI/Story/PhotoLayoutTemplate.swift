import SwiftUI
import UniformTypeIdentifiers

// MARK: - Photo Layout Template System
enum PhotoLayoutType: String, CaseIterable, Codable, Transferable {
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
    
    // MARK: - Transferable Conformance
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}

// MARK: - Photo Layout Model
struct PhotoLayout: Codable, Identifiable {
    let id: UUID
    var type: PhotoLayoutType
    var frame: CGRect  // Position and size on the page
    var imageData: String?  // Base64 encoded image data
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
    
    // Custom Codable implementation to match JavaScript format
    enum CodingKeys: String, CodingKey {
        case id, type, frame, imageData, imageName, rotation, borderStyle, isLocked
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(PhotoLayoutType.self, forKey: .type)
        imageData = try container.decodeIfPresent(String.self, forKey: .imageData)
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        borderStyle = try container.decodeIfPresent(BorderStyle.self, forKey: .borderStyle) ?? .none
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        
        // Handle frame decoding - support both JavaScript format [[x,y],[w,h]] and CGRect format
        if let frameArray = try? container.decode([[CGFloat]].self, forKey: .frame) {
            // JavaScript format: [[x, y], [width, height]]
            if frameArray.count == 2 && frameArray[0].count == 2 && frameArray[1].count == 2 {
                let origin = CGPoint(x: frameArray[0][0], y: frameArray[0][1])
                let size = CGSize(width: frameArray[1][0], height: frameArray[1][1])
                frame = CGRect(origin: origin, size: size)
            } else {
                frame = CGRect.zero
            }
        } else if let frameDict = try? container.decode([String: [String: CGFloat]].self, forKey: .frame) {
            // CGRect format: {"origin": {"x": ..., "y": ...}, "size": {"width": ..., "height": ...}}
            if let originDict = frameDict["origin"],
               let sizeDict = frameDict["size"],
               let x = originDict["x"],
               let y = originDict["y"],
               let width = sizeDict["width"],
               let height = sizeDict["height"] {
                frame = CGRect(x: x, y: y, width: width, height: height)
            } else {
                frame = CGRect.zero
            }
        } else {
            // Fallback to zero frame
            frame = CGRect.zero
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(imageName, forKey: .imageName)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(borderStyle, forKey: .borderStyle)
        try container.encode(isLocked, forKey: .isLocked)
        
        // Encode frame in JavaScript format: [[x, y], [width, height]]
        let frameArray: [[CGFloat]] = [
            [frame.origin.x, frame.origin.y],
            [frame.size.width, frame.size.height]
        ]
        try container.encode(frameArray, forKey: .frame)
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