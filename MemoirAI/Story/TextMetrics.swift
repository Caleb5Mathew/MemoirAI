import SwiftUI
import UIKit

// MARK: - Text Metrics Calculator
struct TextMetrics {
    
    // Calculate the height of text given constraints
    static func height(for text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let constraintBox = CGSize(width: width, height: .greatestFiniteMagnitude)
        let rect = attributedText.boundingRect(
            with: constraintBox,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(rect.height)
    }
    
    // Calculate the number of lines text will occupy
    static func lineCount(for text: String, font: UIFont, width: CGFloat) -> Int {
        let textHeight = height(for: text, font: font, width: width)
        let lineHeight = font.lineHeight
        return Int(ceil(textHeight / lineHeight))
    }
    
    // Calculate maximum characters that fit in given space
    static func maxCharacters(for availableHeight: CGFloat, font: UIFont, width: CGFloat, averageCharsPerLine: Int = 40) -> Int {
        let lineHeight = font.lineHeight
        let maxLines = Int(floor(availableHeight / lineHeight))
        return maxLines * averageCharsPerLine
    }
    
    // Calculate maximum words that fit in given space
    static func maxWords(for availableHeight: CGFloat, font: UIFont, width: CGFloat, averageWordsPerLine: Int = 8) -> Int {
        let lineHeight = font.lineHeight
        let maxLines = Int(floor(availableHeight / lineHeight))
        return maxLines * averageWordsPerLine
    }
}

// MARK: - Dynamic Page Limits Calculator
struct PageLimits {
    let titleCharLimit: Int
    let captionCharLimit: Int
    let textWordLimit: Int
    let availableTextHeight: CGFloat
    
    // Calculate dynamic limits based on page content
    static func calculate(for page: FlipPage, pageSize: CGSize) -> PageLimits {
        let pageWidth = pageSize.width * 0.8 // Account for margins
        let pageHeight = pageSize.height * 0.85 // Account for margins
        
        // Define fonts (matching the CSS)
        let titleFont: UIFont
        let captionFont: UIFont
        let textFont: UIFont
        
        switch page.type {
        case .cover:
            titleFont = UIFont.systemFont(ofSize: 20, weight: .regular)
            captionFont = UIFont.italicSystemFont(ofSize: 11)
            textFont = UIFont.systemFont(ofSize: 10)
            
            // Cover page has centered content with more spacing
            let titleHeight = TextMetrics.height(for: page.title ?? "", font: titleFont, width: pageWidth)
            let captionHeight = TextMetrics.height(for: page.caption ?? "", font: captionFont, width: pageWidth)
            
            // Cover page doesn't have body text, so limits are more generous
            let titleLimit = titleHeight < 60 ? 20 : 15
            let captionLimit = captionHeight < 40 ? 40 : 30
            
            return PageLimits(
                titleCharLimit: titleLimit,
                captionCharLimit: captionLimit,
                textWordLimit: 0,
                availableTextHeight: 0
            )
            
        case .text, .leftBars:
            titleFont = UIFont.systemFont(ofSize: 12, weight: .regular)
            textFont = UIFont.systemFont(ofSize: 6, weight: .light)
            
            // Calculate space used by title
            let titleHeight = page.title != nil ? 
                TextMetrics.height(for: page.title!, font: titleFont, width: pageWidth) + 16 : 0
            
            // Calculate remaining space for text
            let availableTextHeight = pageHeight - titleHeight - 40 // padding
            
            // Dynamic limits based on available space
            let titleLimit = page.title?.count ?? 0 > 20 ? 30 : 40
            let wordLimit = Int(availableTextHeight / textFont.lineHeight) * 8 // ~8 words per line
            
            return PageLimits(
                titleCharLimit: titleLimit,
                captionCharLimit: 0,
                textWordLimit: min(wordLimit, 200), // Cap at 200 words
                availableTextHeight: availableTextHeight
            )
            
        case .rightPhoto, .mixed:
            titleFont = UIFont.systemFont(ofSize: 12, weight: .regular)
            captionFont = UIFont.italicSystemFont(ofSize: 8)
            
            // Account for image taking up space
            let imageHeight = pageHeight * 0.4
            let titleHeight = page.title != nil ?
                TextMetrics.height(for: page.title!, font: titleFont, width: pageWidth) + 16 : 0
            
            let availableHeight = pageHeight - imageHeight - titleHeight - 40
            
            return PageLimits(
                titleCharLimit: 30,
                captionCharLimit: 50,
                textWordLimit: 0,
                availableTextHeight: availableHeight
            )
            
        case .html:
            return PageLimits(
                titleCharLimit: 50,
                captionCharLimit: 100,
                textWordLimit: 500,
                availableTextHeight: pageHeight * 0.8
            )
        }
    }
}

// MARK: - Text Validation
struct TextValidator {
    
    // Check if text will overflow given the limits
    static func willOverflow(text: String, limit: PageLimits, isTitle: Bool = false) -> Bool {
        if isTitle {
            return text.count > limit.titleCharLimit
        } else {
            let wordCount = text.split(separator: " ").count
            return wordCount > limit.textWordLimit
        }
    }
    
    // Get overflow percentage (0.0 to 1.0+)
    static func overflowPercentage(text: String, limit: Int, countWords: Bool = false) -> Double {
        let count = countWords ? text.split(separator: " ").count : text.count
        return Double(count) / Double(max(limit, 1))
    }
    
    // Get color for text based on usage
    static func limitColor(for percentage: Double) -> Color {
        if percentage >= 1.0 {
            return .red
        } else if percentage >= 0.8 {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - View Extension for Dynamic Limits
extension View {
    func withTextLimitIndicator(text: String, limit: Int, countWords: Bool = false) -> some View {
        self.overlay(
            TextLimitIndicator(text: text, limit: limit, countWords: countWords),
            alignment: .bottomTrailing
        )
    }
}

// MARK: - Text Limit Indicator View
struct TextLimitIndicator: View {
    let text: String
    let limit: Int
    let countWords: Bool
    
    private var count: Int {
        countWords ? text.split(separator: " ").count : text.count
    }
    
    private var percentage: Double {
        TextValidator.overflowPercentage(text: text, limit: limit, countWords: countWords)
    }
    
    private var color: Color {
        TextValidator.limitColor(for: percentage)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)/\(limit)")
                .font(.caption2)
                .foregroundColor(color)
            
            if percentage >= 0.8 {
                Image(systemName: percentage >= 1.0 ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(color)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.9))
        .cornerRadius(4)
        .padding(4)
    }
}