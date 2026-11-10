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
        "yen": "JPY", "z\u{0142}": "PLN", "kr": "kr"
    ]

    /// Currencies written as "kr". Swedish kronor when the default is none of them.
    private static let kronaLike: Set<String> = ["SEK", "NOK", "DKK", "ISK"]

    /// Codes safe to match as plain words. Codes that are also English words (ALL, TRY) are left out.
    private static let writtenCodes: Set<String> = [
        "USD", "EUR", "GBP", "INR", "JPY", "CAD", "AUD", "NZD", "CHF", "CNY", "SEK", "NOK", "DKK",
        "MXN", "BRL", "ZAR", "SGD", "HKD", "AED", "THB", "KRW", "PLN", "CZK", "HUF", "ILS", "PHP", "IDR"
    ]

    /// Every other code Foundation knows. Many are also words (ALL, TRY, TOP, PEN), so these count
    /// only in capitals and only right beside the amount.
    private static let otherCodes: Set<String> = Set(Locale.commonISOCurrencyCodes).subtracting(writtenCodes)
    private static let otherCodeAlternation = otherCodes.sorted().joined(separator: "|")

    private static let symbols: [Character: String] = [
        "$": "$", "\u{20AC}": "EUR", "\u{00A3}": "GBP", "\u{20B9}": "INR", "\u{00A5}": "JPY",
        "\u{20A9}": "KRW", "\u{20BA}": "TRY", "\u{20B1}": "PHP", "\u{0E3F}": "THB", "\u{20AB}": "VND"
    ]

    /// "R$" is the Brazilian real, so it is read before the dollar sign inside it.
    private static let symbolPattern = TextPattern(
        #"(?<![\p{L}])R\$|[$\x{20AC}\x{00A3}\x{20B9}\x{00A5}\x{20A9}\x{20BA}\x{20B1}\x{0E3F}\x{20AB}]"#,
        caseInsensitive: false
    )
    /// The yen sign is also the yuan sign. Yen has no decimals, so a price such as ¥68.50 is yuan.
    private static let yuanPricePattern = TextPattern(#"\x{00A5}\s?\d[\d,]*\.\d{1,2}(?!\d)"#)

    /// Regex alternation of the words and codes that can follow or precede an amount.
    static var wordAlternation: String {
        let all = Array(words.keys) + writtenCodes.map { $0.lowercased() }
        return all.sorted { $0.count > $1.count }.joined(separator: "|")
            + "|(?-i:" + otherCodeAlternation + ")"
    }

    /// The ISO code for a symbol, word or code token, or nil when the token means no currency.
    /// A bare dollar sign resolves to `defaultCode` when that is itself a dollar currency.
    static func code(forToken token: String, defaultCode: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var resolved: String?
        if trimmed.count == 1, let symbol = symbols[trimmed[trimmed.startIndex]] {
            resolved = symbol
        } else if trimmed.uppercased() == "R$" {
            resolved = "BRL"
        } else if let word = words[trimmed.lowercased()] {
            resolved = word
        } else if writtenCodes.contains(trimmed.uppercased()) {
            resolved = trimmed.uppercased()
        } else if otherCodes.contains(trimmed) {
            resolved = trimmed
        }
        guard let resolved else { return nil }
        if resolved == "$" {
            return dollarLike.contains(defaultCode.uppercased()) ? defaultCode.uppercased() : "USD"
        }
        if resolved == "kr" {
            return kronaLike.contains(defaultCode.uppercased()) ? defaultCode.uppercased() : "SEK"
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
        symbolCodes(in: text, defaultCode: defaultCode).forEach { add($0) }
        let pattern = TextPattern("(?<![\\p{L}])(\(wordAlternation))(?![\\p{L}])")
        for match in pattern.matches(in: text) {
            guard let token = match.group(1, in: text), let range = Range(match.range, in: text) else { continue }
            let counts = writtenCodes.contains(token) || touchesAmount(range, in: text) || followsIn(range, in: text)
            if counts { add(code(forToken: token, defaultCode: defaultCode)) }
        }
        return found
    }

    /// The currency of each symbol in `text`, in the order written.
    private static func symbolCodes(in text: String, defaultCode: String) -> [String] {
        symbolPattern.matches(in: text).compactMap { match in
            guard let token = match.group(0, in: text) else { return nil }
            let resolved = code(forToken: token, defaultCode: defaultCode)
            if token == "\u{00A5}", resolved == "JPY", yuanPricePattern.isMatch(in: text) { return "CNY" }
            return resolved
        }
    }

    /// Currency words that are also product names on a receipt (a quarter pound burger, a dollar store) never count.
    private static let printedWords: Set<String> = ["euro", "euros", "rupee", "rupees", "rs", "yen"]
    /// Words printed after the amount, as in "249,00 kr".
    private static let printedAfterAmount: Set<String> = ["kr", "z\u{0142}"]
    private static let summaryWords: Set<String> = ["total", "subtotal", "due", "amount", "balance", "payable", "currency"]

    /// What a printed receipt says its currency is: symbols, codes in capitals, and a few words right beside a number.
    static func printedCodes(in text: String, defaultCode: String) -> [String] {
        var found: [String] = []
        func add(_ code: String?) {
            if let code, !found.contains(code) { found.append(code) }
        }
        symbolCodes(in: text, defaultCode: defaultCode).forEach { add($0) }
        let pattern = TextPattern("(?<![\\p{L}])(\(wordAlternation))(?![\\p{L}])")
        for match in pattern.matches(in: text) {
            guard let token = match.group(1, in: text), let range = Range(match.range, in: text) else { continue }
            let isCode = writtenCodes.contains(token.uppercased())
            let counts: Bool
            if otherCodes.contains(token) {
                // Receipts print product names in capitals, and "1 MOP 12.99" is a mop. A code outside the
                // usual list counts after a printed price or after a word such as TOTAL.
                counts = followsPrice(range, in: text) || summaryWords.contains(wordBefore(range, in: text))
            } else if printedAfterAmount.contains(token.lowercased()) {
                counts = followsPrice(range, in: text)
            } else {
                counts = writtenCodes.contains(token)
                    || ((isCode || printedWords.contains(token.lowercased())) && touchesAmount(range, in: text))
            }
            if counts { add(code(forToken: token, defaultCode: defaultCode)) }
        }
        return found
    }

    /// True when a number with a decimal or thousands mark sits right before the word on the same line.
    private static func followsPrice(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = String(text[..<range.lowerBound].suffix(8))
        return TextPattern(#"\d[.,]\d{2,3} ?\z"#).isMatch(in: before)
    }

    /// The word right before the range on the same line, lowercased.
    private static func wordBefore(_ range: Range<String.Index>, in text: String) -> String {
        let before = text[..<range.lowerBound].reversed().drop { $0 == " " || $0 == ":" }
        return String(before.prefix { $0.isLetter }.reversed()).lowercased()
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
