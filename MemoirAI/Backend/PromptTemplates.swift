//  PromptTemplates.swift

import Foundation

/// ArtStyle enum is declared elsewhere.
/// This file provides prompt templates for our image-generation and Chat pipelines.
enum PromptTemplates {

    // This function can remain the same.
    static func combinedImagePrompt(
        sceneDescription: String,
        caption: String
    ) -> String {
        return """
        Render the scene described below,

        Scene:
        \(sceneDescription)
        """
    }

    static func systemPrompt(
        for style: ArtStyle,
        customArtStyleDetails details: String?
    ) -> String {
        let styleDescription: String
        
        switch style {
        case .kidsBook:
            styleDescription = "STYLE REQUIREMENT: Children's book illustration with soft watercolor style, simple shapes, gentle colors, and whimsical character design. NO photorealistic elements, NO detailed textures, NO complex lighting. Keep it simple, colorful, and child-friendly."
            
        case .realistic:
            styleDescription = "STYLE REQUIREMENT: Photorealistic image with detailed textures, natural lighting, and lifelike appearance."
            
        case .comic:
            styleDescription = "STYLE REQUIREMENT: Comic book illustration style with bold ink outlines, dynamic halftone shading, vibrant saturated colors, dramatic panel-style composition, expressive character poses, action lines, and slight Ben-Day dot texturing. Think classic American comic book art like Marvel/DC with strong visual storytelling."
            
        case .custom:
            let trimmed = (details ?? "an undefined style").trimmingCharacters(in: .whitespacesAndNewlines)
            styleDescription = "STYLE REQUIREMENT: Custom style described as: '\(trimmed)'. Strictly follow this style direction."
        }
        
        return """
        You are an expert storybook assistant. Your response MUST follow the format below exactly.
        
        **CRITICAL STYLE ENFORCEMENT:**
        \(styleDescription)
        
        **FORMATTING RULES:**
        Your entire response must be structured like this:
        IMAGE_PROMPT_START
        (Your generated image prompt goes here)
        IMAGE_PROMPT_END
        PAGE_TEXT_START
        (Your generated page caption goes here)
        PAGE_TEXT_END
        
        **CONTENT RULES:**
        1. Read the user's enriched transcript carefully
        2. Your image prompt MUST start with the style requirement above
        3. After the style requirement, describe ALL characters with their specific details FROM THE TRANSCRIPT ONLY
        4. Include the setting and actions being performed AS DESCRIBED IN THE TRANSCRIPT
        5. DO NOT invent details, props, or decorative elements that aren't in the transcript
        6. CRITICAL: Use the exact objects, actions, and details from the transcript. Do not substitute, change, or add objects that weren't mentioned. Preserve exact wording and details.
        7. Do not add decorative elements, props, or details that aren't explicitly in the transcript
        8. Preserve the exact number, type, and description of objects as they appear in the transcript
        9. Maintain the specified art style throughout the entire prompt
        10. Stick to what was actually described - be accurate, not creative
        11. The image prompt must explicitly require no rendered text: no words, letters, numbers, captions, signs, logos, or labels inside the image
        
        If you cannot generate content, respond only with "Error: Could not generate content."
        """
    }

    // This function can remain the same.
    static func userMessage(
        transcript: String,
        pageCount n: Int
    ) -> String {
        return """
        Please analyze the following transcript and generate one page prompt for the single most resonant moment.
        Remember to follow the formatting rules from your system prompt exactly.

        Transcript to analyze:
        ```
        \(transcript)
        ```
        """
    }
}
