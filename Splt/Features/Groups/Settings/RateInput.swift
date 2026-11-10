import Foundation

/// Reads and writes the exchange rate a person types for a trip.
enum RateInput {
    /// A positive rate, or nil if the text is not one. A rate is read strictly: digits and one
    /// separator. Either separator is the decimal point, so a rate pasted from elsewhere keeps its
    /// value, unless it can only be the locale's thousands separator, as "25,000" in English.
    static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        var digits = ""
        var separatorOffset: Int?
        var separator: Character?
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let value = character.wholeNumberValue, character.unicodeScalars.first?.properties.numericType == .decimal {
                digits.append(String(value))
            } else if ".,\u{066B}\u{066C}".contains(character), separator == nil {
                separator = character
                separatorOffset = digits.count
            } else {
                return nil
            }
        }
        guard !digits.isEmpty else { return nil }

        var plain = digits
        if let separator, let offset = separatorOffset {
            let isGrouping = String(separator) == locale.groupingSeparator
                && (1...3).contains(offset) && digits.count - offset == 3 && digits.first != "0"
            if !isGrouping {
                plain.insert(".", at: plain.index(plain.startIndex, offsetBy: offset))
            }
        }
        guard let value = Decimal(string: plain, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    static func string(_ rate: Decimal, locale: Locale = .current) -> String {
        rate.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...10)))
    }
}
