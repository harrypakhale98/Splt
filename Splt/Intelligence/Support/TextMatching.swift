import Foundation

extension String {
    /// Lowercased, accent-free and width-normalised, so "José" matches "jose".
    var folded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Folded words split on anything that is not a letter or digit.
    var foldedWords: [String] {
        folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// Uppercases the first character and leaves the rest as written.
    var sentenceCased: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    /// Collapses runs of whitespace and trims the ends.
    var tidied: String {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Small regular expression helper so call sites stay readable.
struct TextPattern: Sendable {
    private let source: String
    private let options: NSRegularExpression.Options

    init(_ source: String, caseInsensitive: Bool = true) {
        self.source = source
        self.options = caseInsensitive ? [.caseInsensitive] : []
    }

    private var expression: NSRegularExpression? {
        try? NSRegularExpression(pattern: source, options: options)
    }

    func matches(in text: String) -> [NSTextCheckingResult] {
        guard let expression else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func firstMatch(in text: String) -> NSTextCheckingResult? {
        matches(in: text).first
    }

    func isMatch(in text: String) -> Bool {
        firstMatch(in: text) != nil
    }
}

extension NSTextCheckingResult {
    /// The text of a numbered or named group, or nil when the group did not take part.
    func group(_ index: Int, in text: String) -> String? {
        guard index < numberOfRanges, let range = Range(range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    func group(named name: String, in text: String) -> String? {
        let nsRange = range(withName: name)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: text) else { return nil }
        return String(text[range])
    }
}

enum EditDistance {
    /// Levenshtein distance between two strings, compared character by character.
    static func between(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, right) in b.enumerated() {
                let cost = left == right ? 0 : 1
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }
}
