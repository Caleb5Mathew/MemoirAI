//
//  TranscriptChunker.swift
//  MemoirAI
//
//  Created by user941803 on 5/9/25.
//

import Foundation

struct TranscriptChunker {
    /// A conservative token estimate that accounts for both natural-language words
    /// and long strings without whitespace.
    static func approximateTokenCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        return approximateTokenCount(wordCount: wordCount, utf8Count: text.utf8.count)
    }

    private static func approximateTokenCount(wordCount: Int, utf8Count: Int) -> Int {
        let wordEstimate = Int(Double(wordCount) * 1.3)
        let byteEstimate = (utf8Count + 3) / 4
        return max(wordEstimate, byteEstimate)
    }

    /// Splits `text` into chunks whose estimated token count never exceeds `maxTokens`.
    static func chunk(_ text: String, maxTokens: Int = 120_000) -> [String] {
        guard maxTokens > 0 else { return [] }

        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { return [] }

        var units: [(text: String, startsParagraph: Bool)] = []
        for paragraph in paragraphs {
            let unitStartIndex = units.count
            if approximateTokenCount(paragraph) <= maxTokens {
                units.append((paragraph, true))
                continue
            }

            var currentWords: [Substring] = []
            var currentUTF8Count = 0
            for word in paragraph.split(whereSeparator: { $0.isWhitespace }) {
                let separatorByteCount = currentWords.isEmpty ? 0 : 1
                let candidateUTF8Count = currentUTF8Count + separatorByteCount + word.utf8.count
                if approximateTokenCount(
                    wordCount: currentWords.count + 1,
                    utf8Count: candidateUTF8Count
                ) <= maxTokens {
                    currentWords.append(word)
                    currentUTF8Count = candidateUTF8Count
                    continue
                }

                if !currentWords.isEmpty {
                    units.append((currentWords.joined(separator: " "), units.count == unitStartIndex))
                    currentWords.removeAll(keepingCapacity: true)
                    currentUTF8Count = 0
                }

                let wordText = String(word)
                if approximateTokenCount(wordText) <= maxTokens {
                    currentWords.append(word)
                    currentUTF8Count = word.utf8.count
                    continue
                }

                var fragment = ""
                var fragmentUTF8Count = 0
                for scalar in wordText.unicodeScalars {
                    let scalarText = String(scalar)
                    let candidateUTF8Count = fragmentUTF8Count + scalarText.utf8.count
                    if !fragment.isEmpty,
                       approximateTokenCount(wordCount: 1, utf8Count: candidateUTF8Count) > maxTokens {
                        units.append((fragment, units.count == unitStartIndex))
                        fragment = scalarText
                        fragmentUTF8Count = scalarText.utf8.count
                    } else {
                        fragment.append(contentsOf: scalarText)
                        fragmentUTF8Count = candidateUTF8Count
                    }
                }
                if !fragment.isEmpty {
                    units.append((fragment, units.count == unitStartIndex))
                }
            }

            if !currentWords.isEmpty {
                units.append((currentWords.joined(separator: " "), units.count == unitStartIndex))
            }
        }

        var chunks: [String] = []
        var current = ""
        for unit in units {
            let separator = current.isEmpty ? "" : (unit.startsParagraph ? "\n\n" : " ")
            let candidate = current + separator + unit.text
            if approximateTokenCount(candidate) <= maxTokens {
                current = candidate
            } else {
                if !current.isEmpty { chunks.append(current) }
                current = unit.text
            }
        }
        if !current.isEmpty { chunks.append(current) }

        #if DEBUG
        print("[TranscriptChunker] split \(text.count) characters into \(chunks.count) chunks")
        #endif
        return chunks
    }
}
