import Foundation

enum TitleSimilarity {
    /// True when the titles match ignoring case, accents and spacing, or one contains the other.
    static func areSimilar(_ lhs: String, _ rhs: String) -> Bool {
        let first = normalized(lhs)
        let second = normalized(rhs)
        if first == second { return true }
        guard first.count >= 3, second.count >= 3 else { return false }
        return first.contains(second) || second.contains(first)
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
