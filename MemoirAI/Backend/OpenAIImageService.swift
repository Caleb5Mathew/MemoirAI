import Foundation
import UIKit

actor OpenAIImageService {
    let apiKey: String
    let session: URLSession


    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey  = apiKey
        self.session = session
        print("[OpenAIImageService DEBUG] booted – key prefix: \(apiKey.prefix(5))…")
    }

    /// Generate `n` images at `size` for a single text `prompt`,
    /// using any number of reference-image IDs to guide subject/look.
    func generateImages(
        prompt: String,
        referencedImageIDs: [String],
        n: Int = 1,
        size: String = "1024x1024"
    ) async throws -> [UIImage] {
        return try await generateImagesWithRetry(
            prompt: prompt,
            referencedImageIDs: referencedImageIDs,
            n: n,
            size: size,
            retryCount: 0,
            maxRetries: 3
        )
    }
    

    
    /// Internal helper with retry logic for rate limiting
    private func generateImagesWithRetry(
        prompt: String,
        referencedImageIDs: [String],
        n: Int,
        size: String,
        retryCount: Int,
        maxRetries: Int
    ) async throws -> [UIImage] {
        // 1) build JSON payload - DALL-E 3 specific constraints
        print("[OpenAIImageService DEBUG] === DALL-E 3 REQUEST DETAILS ===")
        print("[OpenAIImageService DEBUG] Prompt length: \(prompt.count) characters")
        print("[OpenAIImageService DEBUG] Size requested: \(size)")
        print("[OpenAIImageService DEBUG] N requested: \(n) (will use 1 for DALL-E 3)")
        print("[OpenAIImageService DEBUG] Referenced image IDs: \(referencedImageIDs)")
        
        let body: [String: Any] = [
            "model"           : "dall-e-3",
            "prompt"          : prompt,
            "n"               : 1, // DALL-E 3 only supports n=1
            "size"            : size,
            "response_format" : "url",
            "quality"         : "standard" // Add required quality parameter
        ]
        
        // Note: reference_image_ids is not supported by DALL-E 3 API
        // This was causing the image_generation_user_error
        if !referencedImageIDs.isEmpty {
            print("[OpenAIImageService WARNING] Reference image IDs not supported by DALL-E 3, ignoring: \(referencedImageIDs)")
        }
        
        // Log the exact JSON being sent
        if let jsonData = try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("[OpenAIImageService DEBUG] JSON payload:")
            print(jsonString)
        }

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        req.httpMethod = "POST"
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 2) send request
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        print("[OpenAIImageService DEBUG] HTTP status: \(http.statusCode)")

        // 3) handle rate limiting and API errors with retry
        if http.statusCode == 429 {
            let raw = String(data: data, encoding: .utf8) ?? "(binary)"
            
            // Check for specific image_generation_user_error
            if raw.contains("image_generation_user_error") {
                print("[OpenAIImageService ERROR] === DETAILED ERROR ANALYSIS ===")
                print("[OpenAIImageService ERROR] Error type: image_generation_user_error")
                print("[OpenAIImageService ERROR] Retry attempt: \(retryCount + 1)/\(maxRetries + 1)")
                print("[OpenAIImageService ERROR] Prompt length: \(prompt.count) characters")
                print("[OpenAIImageService ERROR] Full response: \(raw)")
                
                // Analyze prompt for potential issues
                analyzePromptForIssues(prompt)
                
                if retryCount < maxRetries {
                    let delay = pow(2.0, Double(retryCount + 1))
                    print("[OpenAIImageService INFO] Retrying in \(delay) seconds...")
                    
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    return try await generateImagesWithRetry(
                        prompt: prompt,
                        referencedImageIDs: referencedImageIDs,
                        n: n,
                        size: size,
                        retryCount: retryCount + 1,
                        maxRetries: maxRetries
                    )
                } else {
                    print("[OpenAIImageService ERROR] === FINAL FAILURE AFTER ALL RETRIES ===")
                    print("[OpenAIImageService ERROR] This error suggests the prompt content may be triggering OpenAI's content filters")
                    print("[OpenAIImageService ERROR] Consider simplifying the prompt or removing specific details")
                    
                    throw NSError(domain: "OpenAI",
                                  code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "DALL-E 3 failed with image_generation_user_error after \(maxRetries + 1) attempts. The prompt may be triggering content filters.", "body": raw, "promptLength": prompt.count])
                }
            } else {
                print("[OpenAIImageService ERROR] Rate limited (429). Retry \(retryCount + 1)/\(maxRetries + 1)")
                print("[OpenAIImageService ERROR] Response: \(raw)")
                
                if retryCount < maxRetries {
                    // Exponential backoff: 2^retry seconds (2, 4, 8 seconds)
                    let delay = pow(2.0, Double(retryCount + 1))
                    print("[OpenAIImageService INFO] Waiting \(delay) seconds before retry...")
                    
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    return try await generateImagesWithRetry(
                        prompt: prompt,
                        referencedImageIDs: referencedImageIDs,
                        n: n,
                        size: size,
                        retryCount: retryCount + 1,
                        maxRetries: maxRetries
                    )
                } else {
                    throw NSError(domain: "OpenAI",
                                  code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "Rate limit exceeded. Please try again in a few minutes.", "body": raw])
                }
            }
        }

        guard (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "(binary)"
            print("[OpenAIImageService ERROR] API \(http.statusCode):\n\(raw)")
            throw NSError(domain: "OpenAI",
                          code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Image API failed", "body": raw])
        }

        // 4) decode URLs
        struct Response: Decodable {
            struct Entry: Decodable { let url: String? }
            let data: [Entry]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let urls    = decoded.data.compactMap { URL(string: $0.url ?? "") }

        // 5) download images
        var images: [UIImage] = []
        for url in urls {
            let (imgData, imgResp) = try await session.data(from: url)
            if let imgHttp = imgResp as? HTTPURLResponse, imgHttp.statusCode == 200,
               let ui = UIImage(data: imgData) {
                images.append(ui)
            }
        }
        print("[OpenAIImageService DEBUG] downloaded \(images.count) images")
        return images
    }

    /// Convenience overload: no references
    func generateImages(
        prompt: String,
        n: Int = 1,
        size: String = "1024x1024"
    ) async throws -> [UIImage] {
        return try await generateImages(
            prompt: prompt,
            referencedImageIDs: [],
            n: n,
            size: size
        )
    }

    /// Batch-helper: generate `n` images per prompt for an array of ImagePrompt
    /// (now including each prompt’s own referenceImageIDs).
    func generateImages(
        from prompts: [ImagePrompt],
        n: Int = 1,
        size: String = "1024x1024"
    ) async throws -> [UIImage] {
        var all: [UIImage] = []
        for p in prompts {
            print("[StoryPageViewModel] ⛔ Image prompt before failure:", p.text)

            let imgs = try await generateImages(
                prompt: p.text,
                referencedImageIDs: p.referenceImageIDs,
                n: n,
                size: size
            )
            all.append(contentsOf: imgs)
        }
        return all
    }

    /// Style-cue “enrichPrompt” – for adding style hints before actual DALL·E call.
    /// Style‐cue enrichment. Preserve the entire prompt, then tack on your style hint.
    func enrichPrompt(_ prompt: String, with ref: UIImage) async throws -> String {
        return """
        \(prompt)

        Match the colour palette, flat torn-paper texture, and
        blocky-silhouette style of the reference image.
        """
    }
    
    /// Analyze prompt for potential issues that might trigger content filters
    private func analyzePromptForIssues(_ prompt: String) {
        print("[OpenAIImageService DEBUG] === PROMPT ANALYSIS ===")
        
        // Check length
        if prompt.count > 1000 {
            print("[OpenAIImageService WARNING] Prompt is very long (\(prompt.count) chars). DALL-E 3 may have issues with complex prompts.")
        }
        
        // Check for potentially problematic terms
        let problematicTerms = [
            "NEGATIVE:", "CHARACTERS:", "incorrect", "mismatched", "banned", "forbidden",
            "violent", "attack", "weapon", "blood", "inappropriate", "explicit",
            "pale caucasian", "interracial family", "mismatched race"
        ]
        
        for term in problematicTerms {
            if prompt.lowercased().contains(term.lowercased()) {
                print("[OpenAIImageService WARNING] Found potentially problematic term: '\(term)'")
            }
        }
        
        // Check for excessive detail/complexity
        let sentences = prompt.components(separatedBy: ". ")
        if sentences.count > 10 {
            print("[OpenAIImageService WARNING] Prompt has \(sentences.count) sentences - very complex")
        }
        
        // Check for conflicting instructions
        if prompt.contains("NEGATIVE:") && prompt.contains("CHARACTERS:") {
            print("[OpenAIImageService WARNING] Prompt contains both character instructions and negative prompts - may confuse DALL-E 3")
        }
        
        // Check for overly specific racial/ethnic instructions
        if prompt.contains("default to the same race") || prompt.contains("similar skin-tone") {
            print("[OpenAIImageService WARNING] Prompt contains specific racial instructions that may trigger content filters")
        }
        
        // Suggest simplification
        if prompt.count > 500 {
            print("[OpenAIImageService INFO] Consider using a simpler prompt with just the core scene description")
        }
        
        print("[OpenAIImageService DEBUG] === END ANALYSIS ===")
    }

}
