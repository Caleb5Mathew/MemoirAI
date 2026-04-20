import Foundation

extension ArtStyle {
    /// Shared long-form style text for memory illustrations and print cover/back-cover art so prompts stay in sync.
    /// - Parameter customText: User phrase when `self == .custom`; ignored for other cases except empty fallback for custom.
    func memoryIllustrationStyleDescription(customText: String?) -> String {
        switch self {
        case .kidsBook:
            return "Children's book illustration with soft watercolor style, gentle colors, and hand-drawn warmth. Keep character faces expressive and readable with natural eyes, visible iris/pupil detail, and soft facial features that still feel kid-friendly. NO photorealistic elements, NO detailed textures, NO complex lighting."
        case .realistic:
            return "Photorealistic image with detailed textures, natural lighting, and lifelike appearance. Render as photograph-quality with natural skin textures, real fabric folds, ambient occlusion, and photographic depth of field. This must look like a real photograph or hyperrealistic digital painting, NOT a cartoon, comic panel, or soft children's-book illustration."
        case .comic:
            return "Comic book illustration with bold ink outlines, dynamic halftone shading, vibrant colors, dramatic composition, expressive poses, and classic comic book art style. Use thick black ink outlines around all figures and objects. Apply visible halftone dot patterns for shading. Use flat, saturated color fills. This must unmistakably look like a printed comic book panel, NOT a watercolor or soft illustration."
        case .custom:
            let trimmed = (customText ?? "an undefined style").trimmingCharacters(in: .whitespacesAndNewlines)
            return "Custom style described as: '\(trimmed.isEmpty ? "an undefined style" : trimmed)'. Strictly follow this style direction."
        }
    }

    /// Short instruction so cover models do not ignore the style block in favor of a default picture-book look.
    static let coverStyleBindingInstruction = "BINDING INSTRUCTION: Render strictly according to VISUAL STYLE above (medium, linework, color, and lighting). Do not substitute a different illustration genre or default to soft watercolor unless VISUAL STYLE specifies watercolor children's book."
}
