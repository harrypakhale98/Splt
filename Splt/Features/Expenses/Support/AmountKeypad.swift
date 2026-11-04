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

    /// The text with thousands separators in the whole part, for the big numerals.
    static func display(_ text: String, locale: Locale = .current) -> String {
        guard !text.isEmpty else { return "" }
        let separator = decimalSeparator(locale)
        let grouping = locale.groupingSeparator ?? ","
        let parts = text.components(separatedBy: separator)
        let isNegative = parts[0].hasPrefix("-")
        let whole = isNegative ? String(parts[0].dropFirst()) : parts[0]
        var grouped = ""
        for (offset, character) in whole.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { grouped.insert(contentsOf: grouping, at: grouped.startIndex) }
            grouped.insert(character, at: grouped.startIndex)
        }
        if isNegative { grouped.insert("-", at: grouped.startIndex) }
        return parts.count > 1 ? grouped + separator + parts[1] : grouped
    }
}
