import Foundation

/// A key on the built-in number pad.
enum AmountKey: Hashable, Sendable {
    case digit(Int)
    case decimal
    case delete
}

/// What the on-screen number pad does to the amount text. The text uses the locale's decimal
/// separator, so `AmountInput` reads it back unchanged.
enum AmountKeypad {
    static let maximumIntegerDigits = 9

    static func decimalSeparator(_ locale: Locale) -> String {
        locale.decimalSeparator ?? "."
    }

    static func apply(_ key: AmountKey, to text: String, exponent: Int, locale: Locale = .current) -> String {
        let separator = decimalSeparator(locale)
        switch key {
        case .digit(let value):
            guard (0...9).contains(value) else { return text }
            let parts = text.components(separatedBy: separator)
            if parts.count > 1 {
                guard parts[1].count < exponent else { return text }
                return text + String(value)
            }
            if text == "0" { return String(value) }
            guard text.count < maximumIntegerDigits else { return text }
            return text + String(value)
        case .decimal:
            guard exponent > 0, !text.contains(separator) else { return text }
            return (text.isEmpty ? "0" : text) + separator
        case .delete:
            return String(text.dropLast())
        }
    }

    /// The text with the locale's digit grouping (1,00,000 in en_IN) and digits in the whole part, for the big numerals.
    static func display(_ text: String, locale: Locale = .current) -> String {
        guard !text.isEmpty else { return "" }
        let separator = decimalSeparator(locale)
        let parts = text.components(separatedBy: separator)
        let isNegative = parts[0].hasPrefix("-")
        let whole = isNegative ? String(parts[0].dropFirst()) : parts[0]
        var shown = wholeNumber(whole).flatMap { formatter(locale).string(for: $0) } ?? whole
        if isNegative { shown.insert("-", at: shown.startIndex) }
        guard parts.count > 1 else { return shown }
        return shown + separator + parts[1].map { character in
            character.wholeNumberValue.map { digit($0, locale: locale) } ?? String(character)
        }.joined()
    }

    /// A single digit as this locale writes it, such as 3 in en_US and ٣ in ar_SA.
    static func digit(_ value: Int, locale: Locale = .current) -> String {
        formatter(locale).string(for: value) ?? String(value)
    }

    /// Whether the currency symbol comes before the number here: $12.50, but 12,50 € in de_DE.
    static func symbolLeads(currencyCode: String, locale: Locale = .current) -> Bool {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        let pattern = formatter.positiveFormat ?? ""
        guard let symbol = pattern.firstIndex(of: "\u{00A4}"),
              let number = pattern.firstIndex(where: { $0 == "#" || $0 == "0" }) else { return true }
        return symbol < number
    }

    private static func formatter(_ locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    /// The value of a run of digits of any script, or nil when it holds anything else or is too long.
    private static func wholeNumber(_ text: String) -> Int64? {
        let digits = text.compactMap(\.wholeNumberValue)
        guard digits.count == text.count else { return nil }
        return Int64(digits.map(String.init).joined())
    }
}
