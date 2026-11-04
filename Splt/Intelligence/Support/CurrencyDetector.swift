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
            guard let token = match.group(1, in: text), let range = Range(match.range, in: text) else { continue }
            let counts = writtenCodes.contains(token) || touchesAmount(range, in: text) || followsIn(range, in: text)
            if counts { add(code(forToken: token, defaultCode: defaultCode)) }
        }
        return found
    }

    /// Currency words that are also product names on a receipt (a quarter pound burger, a dollar store) never count.
    private static let printedWords: Set<String> = ["euro", "euros", "rupee", "rupees", "rs", "yen"]

    /// What a printed receipt says its currency is: symbols, codes in capitals, and a few words right beside a number.
    static func printedCodes(in text: String, defaultCode: String) -> [String] {
        var found: [String] = []
        func add(_ code: String?) {
            if let code, !found.contains(code) { found.append(code) }
        }
        for character in text where symbols[character] != nil {
            add(code(forToken: String(character), defaultCode: defaultCode))
        }
        let pattern = TextPattern("(?<![\\p{L}])(\(wordAlternation))(?![\\p{L}])")
        for match in pattern.matches(in: text) {
            guard let token = match.group(1, in: text), let range = Range(match.range, in: text) else { continue }
            let isCode = writtenCodes.contains(token.uppercased())
            let counts = writtenCodes.contains(token)
                || ((isCode || printedWords.contains(token.lowercased())) && touchesAmount(range, in: text))
            if counts { add(code(forToken: token, defaultCode: defaultCode)) }
        }
        return found
    }

    /// True when a number sits right before or after the word on the same line.
    private static func touchesAmount(_ range: Range<String.Index>, in text: String) -> Bool {
        var before = text[..<range.lowerBound].reversed().drop { $0 == " " }
        if before.first == "k" || before.first == "K" { before = before.dropFirst() }
        if before.first?.isNumber == true { return true }
        let after = text[range.upperBound...].drop { $0 == " " || $0 == "." }
        return after.first?.isNumber == true
    }

    /// True for "in euros".
    private static func followsIn(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = text[..<range.lowerBound].reversed().drop { $0 == " " }
        let word = String(before.prefix { $0.isLetter }.reversed())
        return word.lowercased() == "in"
    }
}
