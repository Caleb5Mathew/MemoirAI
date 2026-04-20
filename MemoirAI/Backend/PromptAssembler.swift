//
//  PromptAssembler.swift
//  MemoirAI
//
//  A compact, deterministic image-prompt assembler with a tiny LLM
//  prepass to summarize the setting/props as JSON. Designed to work
//  for any memory (people or not) and avoid mid‑sentence truncation.
//

import Foundation

struct SettingSummary: Decodable {
    var setting: String
    var layoutHint: String?
    var props: [String]?
}

actor PromptAssembler {
    private let apiKey: String
    private let session: URLSession
    // NOTE: Do not reference this from nonisolated funcs.
    private let internalBudget: Int = 1100  // actor-local default
    
    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }
    
    // LLM prepass: extract a tiny JSON with setting/layout/props from raw memory text
    func summarizeSetting(from memoryText: String) async -> SettingSummary? {
        let system = """
        You extract visual scene hints for an illustration prompt.
        Return ONLY compact JSON with fields: setting (short phrase),
        layoutHint (optional, short), props (optional array of 1-4 nouns).
        Keep it extremely short and concrete. No prose. No extra keys.
        Example: {"setting":"moonlit bridge","layoutHint":"friends left→right on rail","props":["guitar","camera"]}
        """
        let user = """
        Text: \(memoryText.prefix(1600))
        Return JSON only.
        """
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
            ],
            "temperature": 0.2,
            "max_tokens": 120
        ]
        do {
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let startedAt = Date()
            let (data, resp) = try await session.data(for: req)
            let statusCode = (resp as? HTTPURLResponse)?.statusCode
            let usage = DevCostTelemetryService.extractOpenAIUsage(from: data)
            await DevCostTelemetryService.shared.logEvent(
                DevCostEvent(
                    timestamp: Date(),
                    provider: .openAI,
                    operation: .openAIChat,
                    model: "gpt-4o-mini",
                    statusCode: statusCode,
                    success: statusCode == 200,
                    durationMs: Date().timeIntervalSince(startedAt) * 1000,
                    promptCharacters: memoryText.count,
                    inputTokens: usage.inputTokens,
                    outputTokens: usage.outputTokens,
                    inputImageCount: 0,
                    outputImageCount: 0,
                    uploadedBytes: 0
                )
            )
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
            struct Root: Decodable { let choices: [Choice] }
            let raw = try JSONDecoder().decode(Root.self, from: data).choices.first?.message.content ?? ""
            guard let jsonStart = raw.firstIndex(of: "{"),
                  let jsonEnd   = raw.lastIndex(of: "}") else { return nil }
            let json = String(raw[jsonStart...jsonEnd])
            if let d = json.data(using: .utf8) {
                return try? JSONDecoder().decode(SettingSummary.self, from: d)
            }
            return nil
        } catch {
            print("⚠️ PromptAssembler summarizeSetting failed:", error.localizedDescription)
            return nil
        }
    }
    
    // Deterministic string assembly with section prioritization and hard budget.
    nonisolated func assemblePrompt(
        subjectName: String?,
        subjectDescriptor: String?,
        characters: CharacterDetails?,
        styleLine: String,
        setting: SettingSummary?
    ) -> String {
        // Use a local constant so this nonisolated function doesn't touch actor state.
        let characterBudget = 1100
        var sections: [String] = []
        
        // 1) Count
        let names = characters?.characters.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        if names.isEmpty {
            sections.append("Exactly 0 people. No others.")
        } else {
            sections.append("Exactly \(names.count) people: \(names.joined(separator: ", ")). No others.")
        }
        
        // 2) Subject binding
        if let sName = subjectName?.trimmingCharacters(in: .whitespacesAndNewlines), !sName.isEmpty,
           let sDesc = subjectDescriptor?.trimmingCharacters(in: .whitespacesAndNewlines), !sDesc.isEmpty {
            sections.append("Subject: \(sName) (main subject) — \(sDesc).")
        }
        
        // 3) Characters compact lines from CharacterDetails
        if let chars = characters?.characters, !chars.isEmpty {
            for c in chars {
                var parts: [String] = []
                if !c.ethnicity.isEmpty { parts.append(c.ethnicity) }
                if !c.hairAndFeatures.isEmpty { parts.append(c.hairAndFeatures) }
                if !c.clothes.isEmpty { parts.append(c.clothes) }
                if parts.isEmpty && !c.combinedAppearance.isEmpty {
                    parts.append(c.combinedAppearance)
                }
                let line = parts.joined(separator: ", ")
                if !line.isEmpty {
                    sections.append("\(c.name) — \(line).")
                } else {
                    sections.append("\(c.name).")
                }
            }
        }
        
        // 4) Layout
        if names.count > 1 {
            sections.append("Layout: Left→Right \(names.joined(separator: ", ")).")
        } else {
            sections.append("Layout: centered subject.")
        }
        if let hint = setting?.layoutHint, !hint.isEmpty {
            sections.append("Layout hint: \(hint).")
        }
        
        // 5) Setting + props
        if let s = setting?.setting, !s.isEmpty {
            sections.append("Setting: \(s).")
        }
        if let props = setting?.props, !props.isEmpty {
            sections.append("Props: \(props.joined(separator: ", ")).")
        }
        
        // 6) Style (always last)
        sections.append(styleLine)
        
        // Assemble with budget: drop least important optional sections first
        var prompt = sections.joined(separator: " ")
        if prompt.count <= characterBudget { return prompt }
        
        // Drop props
        dropIfContains(prefix: "Props:", from: &prompt)
        if prompt.count <= characterBudget { return prompt }
        
        // Drop layout hint
        dropIfContains(prefix: "Layout hint:", from: &prompt)
        if prompt.count <= characterBudget { return prompt }
        
        // Shorten character lines (keep first clause of each field)
        if let chars = characters?.characters, !chars.isEmpty {
            var shortened: [String] = []
            for c in chars {
                var parts: [String] = []
                if !c.ethnicity.isEmpty { parts.append(c.ethnicity) }
                if !c.hairAndFeatures.isEmpty {
                    let first = c.hairAndFeatures.split(separator: ",").first.map(String.init) ?? c.hairAndFeatures
                    parts.append(first)
                }
                if parts.isEmpty && !c.combinedAppearance.isEmpty {
                    let first = c.combinedAppearance.split(separator: ",").first.map(String.init) ?? c.combinedAppearance
                    parts.append(first)
                }
                shortened.append("\(c.name) — \(parts.joined(separator: ", ")).")
            }
            prompt = rebuild(with: sections, replacingCharacterLinesWith: shortened, styleLine: styleLine)
        }
        
        if prompt.count <= characterBudget { return prompt }
        
        // As a last resort, drop Layout hint and compress layout to a single phrase
        dropIfContains(prefix: "Layout:", from: &prompt)
        prompt += " Layout: simple composition."
        return prompt
    }
    
    // Helpers
    nonisolated private func dropIfContains(prefix: String, from prompt: inout String) {
        let sentences = prompt.split(separator: ".").map { String($0).trimmingCharacters(in: .whitespaces) }
        let kept = sentences.filter { !$0.hasPrefix(prefix) }
        prompt = kept.joined(separator: ". ") + "."
    }
    
    nonisolated private func rebuild(with originalSections: [String], replacingCharacterLinesWith newCharLines: [String], styleLine: String) -> String {
        var rebuilt: [String] = []
        var inserted = false
        for sec in originalSections {
            if sec.contains(" — ") && sec != styleLine && !inserted {
                // Insert the new character block once, skip old character lines thereafter
                rebuilt.append(contentsOf: newCharLines)
                inserted = true
                continue
            }
            if sec.contains(" — ") { continue }
            rebuilt.append(sec)
        }
        return rebuilt.joined(separator: " ")
    }
}


