import Foundation

extension Money {
    /// The amount as an exact decimal in major units, for example 12.50.
    public var decimalValue: Decimal {
        Decimal(
            sign: minorUnits < 0 ? .minus : .plus,
            exponent: -exponent,
            significand: Decimal(minorUnits.magnitude)
        )
    }

    /// A display string such as "$12.50", using the currency's own number of decimals.
    public func formatted(locale: Locale = .current, showsPlusSign: Bool = false) -> String {
        let style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
        if showsPlusSign {
            return decimalValue.formatted(style.sign(strategy: .always(showZero: false)))
        }
        return decimalValue.formatted(style)
    }

    /// A plain number string without symbol or grouping, such as "12.50", for text fields.
    /// `MoneyParser` reads it back with the same locale.
    public func plainString(locale: Locale = .current) -> String {
        decimalValue.formatted(
            .number.locale(locale).grouping(.never).precision(.fractionLength(exponent))
        )
    }
}
