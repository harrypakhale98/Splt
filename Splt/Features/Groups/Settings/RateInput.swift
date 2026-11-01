import Foundation

/// Reads and writes the exchange rate a person types for a trip.
enum RateInput {
    /// A positive rate in the given locale's number format, or nil if the text is not one.
    static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = try? Decimal(trimmed, format: .number.locale(locale)),
              value > 0 else { return nil }
        return value
    }

    static func string(_ rate: Decimal, locale: Locale = .current) -> String {
        rate.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...6)))
    }
}
