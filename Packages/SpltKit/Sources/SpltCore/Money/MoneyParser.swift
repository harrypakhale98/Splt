import Foundation

/// Reads amounts typed by people, such as "12.5", "12,50" or "$1,234.50".
///
/// A single separator is read as a decimal point unless it sits where a thousands separator
/// would (one to three digits, then exactly three) and the locale uses that character for
/// grouping. Currency symbols, currency codes and spaces around the number are ignored.
/// A minus sign, a trailing minus or parentheses make the amount negative.
public enum MoneyParser {
    public static func parse(
        _ text: String,
        currencyCode: String,
        locale: Locale = .current,
        allowNegative: Bool = true
    ) throws -> Money {
        let chars = normalize(text)
        guard chars.contains(where: { !$0.isWhitespace }) else { throw MoneyParseError.empty }
        guard let firstDigit = chars.firstIndex(where: isDigit),
              let lastDigit = chars.lastIndex(where: isDigit) else {
            throw MoneyParseError.invalidFormat
        }

        var start = firstDigit
        if start > 0, isSeparator(chars[start - 1]), start == 1 || !chars[start - 2].isLetter {
            start -= 1
        }
        var end = lastDigit
        if end + 1 < chars.count, isSeparator(chars[end + 1]),
           end + 2 >= chars.count || !chars[end + 2].isLetter {
            end += 1
        }

        let negative = try readSign(prefix: chars[..<start], suffix: chars[(end + 1)...])
        if negative && !allowNegative { throw MoneyParseError.negativeNotAllowed }

        let exponent = Currency.minorUnitExponent(for: currencyCode)
        let magnitude = try readMagnitude(Array(chars[start...end]), exponent: exponent, locale: locale)
        return Money(minorUnits: negative ? -magnitude : magnitude, currencyCode: currencyCode)
    }

    private static func isDigit(_ ch: Character) -> Bool {
        ch.isASCII && ch.isNumber
    }

    private static func isSeparator(_ ch: Character) -> Bool {
        ch == "." || ch == ","
    }

    private static func normalize(_ text: String) -> [Character] {
        // Bidi marks are invisible, and locales such as Arabic and Hebrew put them around a minus sign.
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !$0.properties.isBidiControl })).map { ch -> Character in
            switch ch {
            case "\u{2212}", "\u{2013}", "\u{2014}": return "-"
            case "\u{066B}": return "."
            case "\u{066C}": return ","
            case "\u{00A0}", "\u{202F}", "\u{2009}", "\u{3000}": return " "
            case "\u{2018}", "\u{2019}": return "'"
            default:
                if !ch.isASCII, ch.unicodeScalars.first?.properties.numericType == .decimal,
                   let value = ch.wholeNumberValue {
                    return Character(String(value))
                }
                return ch
            }
        }
    }

    /// Checks the text around the number and says whether it marks the amount as negative.
    private static func readSign(prefix: ArraySlice<Character>, suffix: ArraySlice<Character>) throws -> Bool {
        let around = Array(prefix) + Array(suffix)
        var minusCount = 0
        var letterRun = 0
        for ch in around + [" "] {
            if ch.isLetter {
                letterRun += 1
                continue
            }
            if letterRun == 1 { throw MoneyParseError.invalidFormat }
            letterRun = 0
            switch ch {
            case "-": minusCount += 1
            case "+", "(", ")", ".", " ": break
            default:
                guard ch.isWhitespace || ch.isCurrencySymbol else { throw MoneyParseError.invalidFormat }
            }
        }
        guard minusCount <= 1 else { throw MoneyParseError.invalidFormat }
        let parentheses = prefix.contains("(") && suffix.contains(")")
        return minusCount == 1 || parentheses
    }

    private static func readMagnitude(_ core: [Character], exponent: Int, locale: Locale) throws -> Int64 {
        let spaceGrouped = core.contains { $0 == " " || $0 == "'" }
        let body = spaceGrouped ? try joinSpaceGroups(core) : core
        guard body.allSatisfy({ isDigit($0) || isSeparator($0) }) else { throw MoneyParseError.invalidFormat }

        let dots = body.indices.filter { body[$0] == "." }
        let commas = body.indices.filter { body[$0] == "," }
        var decimalIndex: Int?
        var groupCharacter: Character?

        if spaceGrouped {
            guard dots.count + commas.count <= 1 else { throw MoneyParseError.invalidFormat }
            decimalIndex = (dots + commas).first
        } else if !dots.isEmpty && !commas.isEmpty {
            let decimalIsDot = dots[dots.count - 1] > commas[commas.count - 1]
            let decimals = decimalIsDot ? dots : commas
            guard decimals.count == 1 else { throw MoneyParseError.invalidFormat }
            decimalIndex = decimals[0]
            groupCharacter = decimalIsDot ? "," : "."
        } else if let separators = [dots, commas].first(where: { !$0.isEmpty }) {
            let character = body[separators[0]]
            if separators.count > 1 {
                groupCharacter = character
            } else if looksLikeGrouping(body, at: separators[0], exponent: exponent, locale: locale) {
                groupCharacter = character
            } else {
                decimalIndex = separators[0]
            }
        }

        let integerRegion = Array(body[..<(decimalIndex ?? body.count)])
        var fraction = decimalIndex.map { Array(body[($0 + 1)...]) } ?? []
        guard fraction.allSatisfy(isDigit) else { throw MoneyParseError.invalidFormat }

        let integerDigits: [Character]
        if let groupCharacter {
            integerDigits = try joinGroups(integerRegion, separator: groupCharacter)
        } else {
            guard integerRegion.allSatisfy(isDigit) else { throw MoneyParseError.invalidFormat }
            integerDigits = integerRegion
        }

        if fraction.count > exponent {
            guard fraction[exponent...].allSatisfy({ $0 == "0" }) else { throw MoneyParseError.tooManyFractionDigits }
            fraction = Array(fraction[..<exponent])
        }
        fraction += Array(repeating: "0", count: exponent - fraction.count)

        guard let value = Int64(String(integerDigits + fraction)) else { throw MoneyParseError.outOfRange }
        return value
    }

    /// A lone separator is a thousands separator only when it follows one to three digits,
    /// is followed by exactly three, and the locale (or a zero decimal currency) says so.
    private static func looksLikeGrouping(_ body: [Character], at index: Int, exponent: Int, locale: Locale) -> Bool {
        let after = body.count - index - 1
        guard (1...3).contains(index), body[0] != "0", after == 3 else { return false }
        if exponent == 0 { return true }
        // The body is already normalized, so the locale's separators have to be as well.
        if normalize(locale.decimalSeparator ?? "").first == body[index] { return false }
        return normalize(locale.groupingSeparator ?? "").first == body[index]
    }

    /// Joins chunks split by spaces or apostrophes, as in "1 234,56" or "1'234.50".
    private static func joinSpaceGroups(_ core: [Character]) throws -> [Character] {
        let chunks = core.split(omittingEmptySubsequences: false, whereSeparator: { $0 == " " || $0 == "'" })
        guard chunks.count >= 2, !chunks.contains(where: { $0.isEmpty }) else { throw MoneyParseError.invalidFormat }
        var joined: [Character] = []
        for (position, chunk) in chunks.enumerated() {
            let isLast = position == chunks.count - 1
            let digits = isLast ? Array(chunk.prefix(while: isDigit)) : Array(chunk)
            guard digits.allSatisfy(isDigit) else { throw MoneyParseError.invalidFormat }
            if position == 0 {
                guard (1...3).contains(digits.count), digits[0] != "0" else { throw MoneyParseError.invalidFormat }
            } else {
                guard digits.count == 3 else { throw MoneyParseError.invalidFormat }
            }
            joined += chunk
        }
        return joined
    }

    /// Checks thousands groups (one to three digits, then groups of two or three) and drops the separators.
    private static func joinGroups(_ region: [Character], separator: Character) throws -> [Character] {
        let groups = region.split(separator: separator, omittingEmptySubsequences: false)
        guard groups.count >= 2, groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(isDigit) }) else {
            throw MoneyParseError.invalidFormat
        }
        guard (1...3).contains(groups[0].count), groups[0][groups[0].startIndex] != "0" else {
            throw MoneyParseError.invalidFormat
        }
        guard groups.dropFirst().allSatisfy({ (2...3).contains($0.count) }) else { throw MoneyParseError.invalidFormat }
        return groups.flatMap { $0 }
    }
}

extension Money {
    /// Reads a typed amount; see `MoneyParser`.
    public init(parsing text: String, currencyCode: String, locale: Locale = .current) throws {
        self = try MoneyParser.parse(text, currencyCode: currencyCode, locale: locale)
    }
}
