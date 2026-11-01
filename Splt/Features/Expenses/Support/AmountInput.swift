import Foundation
import SpltCore

/// Reads and writes the numbers people type into the form: money, percentages and share counts.
/// A blank field is not an error; it reads as nil and callers decide what that means.
enum AmountInput {
    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The typed amount in the currency's minor units, or nil when blank or not a number.
    static func money(_ text: String, currencyCode: String, locale: Locale = .current, allowNegative: Bool = false) -> Money? {
        guard !isBlank(text) else { return nil }
        return try? MoneyParser.parse(text, currencyCode: currencyCode, locale: locale, allowNegative: allowNegative)
    }

    /// Hundredths of a percent, so "33.33" is 3333. Percent signs are ignored.
    static func basisPoints(_ text: String, locale: Locale = .current) -> Int64? {
        hundredths(text, locale: locale)
    }

    /// Hundredths of a unit, so "1.5" is 150. Used for share counts that may have a fraction.
    static func hundredths(_ text: String, locale: Locale = .current) -> Int64? {
        let cleaned = text.replacingOccurrences(of: "%", with: "")
        guard !isBlank(cleaned) else { return nil }
        return (try? MoneyParser.parse(cleaned, currencyCode: "USD", locale: locale, allowNegative: false))?.minorUnits
    }

    /// "25" for 2500 and "33.33" for 3333, in the locale's decimal style.
    static func hundredthsText(_ value: Int64, locale: Locale = .current) -> String {
        Decimal(sign: .plus, exponent: -2, significand: Decimal(value))
            .formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...2)))
    }

    /// Money in a text field, for example "12.50", with a minus sign for negative amounts.
    static func text(for money: Money, locale: Locale = .current) -> String {
        money.plainString(locale: locale)
    }
}
