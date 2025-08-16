import Foundation
import UIKit

extension String {
    /// Enhanced pagination that creates professional book layout with 150-200 words per page
    func paginatedForBook(wordsPerPage: Int = 175) -> [String] {
        let words = self.split { $0.isWhitespace }
        guard words.count > wordsPerPage else {
            return [self]
        }
        
        var pages: [String] = []
        var start = 0
        
        while start < words.count {
            let end = min(start + wordsPerPage, words.count)
            let slice = words[start..<end]
            
            // Join words and clean up any extra whitespace
            let pageContent = slice.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            pages.append(pageContent)
            
            start += wordsPerPage
        }
        
        return pages
    }
    
    /// Content-aware pagination that considers chapter breaks and content flow
    func paginatedWithChapters(wordsPerPage: Int = 175) -> [String] {
        // Split by potential chapter breaks (double line breaks, etc.)
        let paragraphs = self.components(separatedBy: "\n\n")
        
        var pages: [String] = []
        var currentPage = ""
        var currentWordCount = 0
        
        for paragraph in paragraphs {
            let paragraphWords = paragraph.split { $0.isWhitespace }
            let paragraphWordCount = paragraphWords.count
            
            // If adding this paragraph would exceed the word limit
            if currentWordCount + paragraphWordCount > wordsPerPage && !currentPage.isEmpty {
                // Finalize current page
                pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
                currentPage = ""
                currentWordCount = 0
            }
            
            // Add paragraph to current page
            if !currentPage.isEmpty {
                currentPage += "\n\n"
            }
            currentPage += paragraph
            currentWordCount += paragraphWordCount
        }
        
        // Add the last page if there's content
        if !currentPage.isEmpty {
            pages.append(currentPage.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return pages.isEmpty ? [self] : pages
    }
    
    /// Legacy pagination for backward compatibility
    func paginated(wordsPerPage: Int = 130) -> [String] {
        let words = self.split { $0.isWhitespace }
        guard words.count > wordsPerPage else {
            return [self]
        }
        var pages: [String] = []
        var start = 0
        while start < words.count {
            let end = min(start + wordsPerPage, words.count)
            let slice = words[start..<end]
            pages.append(slice.joined(separator: " "))
            start += wordsPerPage
        }
        return pages
    }

    /// Advanced pagination that considers available space and typography
    func paginate(for size: CGSize, with font: UIFont) -> [String] {
        let attributedString = NSAttributedString(string: self, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        var pages = [String]()
        var start = 0

        while start < self.count {
            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: size))
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(start, 0), path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)

            if visibleRange.length == 0 {
                break
            }

            let end = start + visibleRange.length
            let startIndex = self.index(self.startIndex, offsetBy: start)
            let endIndex = self.index(self.startIndex, offsetBy: end)
            pages.append(String(self[startIndex..<endIndex]))

            start = end
        }

        return pages
    }
    
    /// Smart content distribution that creates balanced pages
    func smartPaginated(targetWordsPerPage: Int = 175, maxWordsPerPage: Int = 200) -> [String] {
        let words = self.split { $0.isWhitespace }
        guard words.count > targetWordsPerPage else {
            return [self]
        }
        
        var pages: [String] = []
        var currentPageWords: [String] = []
        var currentWordCount = 0
        
        for word in words {
            // If adding this word would exceed max words per page
            if currentWordCount + 1 > maxWordsPerPage && !currentPageWords.isEmpty {
                // Finalize current page
                pages.append(currentPageWords.joined(separator: " "))
                currentPageWords = []
                currentWordCount = 0
            }
            
            // Add word to current page
            currentPageWords.append(String(word))
            currentWordCount += 1
            
            // If we've reached target words and we're at a good breaking point
            if currentWordCount >= targetWordsPerPage {
                // Look for sentence endings to break naturally
                let lastWord = String(word)
                if lastWord.hasSuffix(".") || lastWord.hasSuffix("!") || lastWord.hasSuffix("?") {
                    pages.append(currentPageWords.joined(separator: " "))
                    currentPageWords = []
                    currentWordCount = 0
                }
            }
        }
        
        // Add remaining words to final page
        if !currentPageWords.isEmpty {
            pages.append(currentPageWords.joined(separator: " "))
        }
        
        return pages.isEmpty ? [self] : pages
    }
    
    /// Professional book pagination with chapter awareness
    func bookPaginated(wordsPerPage: Int = 175) -> [String] {
        // First, try to identify natural chapter breaks
        let chapterMarkers = ["Chapter", "CHAPTER", "Part", "PART", "Section", "SECTION"]
        let lines = self.components(separatedBy: .newlines)
        
        var pages: [String] = []
        var currentContent = ""
        var currentWordCount = 0
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check if this line is a chapter marker
            let isChapterBreak = chapterMarkers.contains { trimmedLine.hasPrefix($0) }
            
            if isChapterBreak && !currentContent.isEmpty {
                // Finalize current page before chapter break
                pages.append(currentContent.trimmingCharacters(in: .whitespacesAndNewlines))
                currentContent = ""
                currentWordCount = 0
            }
            
            let lineWords = trimmedLine.split { $0.isWhitespace }
            let lineWordCount = lineWords.count
            
            // If adding this line would exceed word limit
            if currentWordCount + lineWordCount > wordsPerPage && !currentContent.isEmpty {
                pages.append(currentContent.trimmingCharacters(in: .whitespacesAndNewlines))
                currentContent = ""
                currentWordCount = 0
            }
            
            // Add line to current content
            if !currentContent.isEmpty {
                currentContent += "\n"
            }
            currentContent += trimmedLine
            currentWordCount += lineWordCount
        }
        
        // Add final content
        if !currentContent.isEmpty {
            pages.append(currentContent.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return pages.isEmpty ? [self] : pages
    }
}
