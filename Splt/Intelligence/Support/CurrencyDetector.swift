import Foundation

/// Finds a currency the writer actually mentioned: a symbol, an ISO code or a common word.
enum CurrencyDetector {
    private static let dollarLike: Set<String> = [
        "USD", "CAD", "AUD", "NZD", "SGD", "HKD", "MXN", "ARS", "CLP", "COP"
    ]

    private static let words: [String: String] = [
        "dollar": "$", "dollars": "$", "buck": "$", "bucks": "$",
        "euro": "EUR", "euros": "EUR",
        "pound": "GBP", "pounds": "GBP", "quid": "GBP", "sterling": "GBP",
        "rupee": "INR", "rupees": "INR", "rs": "INR",
        "yen": "JPY"
    ]

    /// Codes safe to match as plain words. Codes that are also English words (ALL, TRY) are left out.
    private static let writtenCodes: Set<String> = [
        "USD", "EUR", "GBP", "INR", "JPY", "CAD", "AUD", "NZD", "CHF", "CNY", "SEK", "NOK", "DKK",
        "MXN", "BRL", "ZAR", "SGD", "HKD", "AED", "THB", "KRW", "PLN", "CZK", "HUF", "ILS", "PHP", "IDR"
    ]

    private static let symbols: [Character: String] = [
        "$": "$", "\u{20AC}": "EUR", "\u{00A3}": "GBP", "\u{20B9}": "INR", "\u{00A5}": "JPY"
    ]

    /// Regex alternation of the words and codes that can follow or precede an amount.
    static var wordAlternation: String {
        let all = Array(words.keys) + writtenCodes.map { $0.lowercased() }
        return all.sorted { $0.count > $1.count }.joined(separator: "|")
    }

    /// The ISO code for a symbol, word or code token, or nil when the token means no currency.
    /// A bare dollar sign resolves to `defaultCode` when that is itself a dollar currency.
    static func code(forToken token: String, defaultCode: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var resolved: String?
        if trimmed.count == 1, let symbol = symbols[trimmed[trimmed.startIndex]] {
            resolved = symbol
        } else if let word = words[trimmed.lowercased()] {
            resolved = word
        } else if writtenCodes.contains(trimmed.uppercased()) {
            resolved = trimmed.uppercased()
        }
        guard let resolved else { return nil }
        if resolved == "$" {
            return dollarLike.contains(defaultCode.uppercased()) ? defaultCode.uppercased() : "USD"
        }
        if resolved == "JPY", defaultCode.uppercased() == "CNY", trimmed == "\u{00A5}" {
            return "CNY"
        }
        return resolved
    }

    /// Every currency mentioned in `text`, symbols first and then words and codes, without repeats.
    static func codes(in text: String, defaultCode: String) -> [String] {
        var found: [String] = []
        func add(_ code: String?) {
            if let code, !found.contains(code) { found.append(code) }
        }
        for character in text {
            add(code(forToken: String(character), defaultCode: defaultCode))
        }
        let pattern = TextPattern("(?<![\\p{L}])(\(wordAlternation))(?![\\p{L}])")
        for match in pattern.matches(in: text) {
            add(code(forToken: match.group(1, in: text) ?? "", defaultCode: defaultCode))
        }
        return found
    }
}
