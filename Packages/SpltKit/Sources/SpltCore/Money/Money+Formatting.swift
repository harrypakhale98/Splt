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
        let style = currencyStyle(locale: locale)
        if showsPlusSign {
            return decimalValue.formatted(style.sign(strategy: .always(showZero: false)))
        }
        return decimalValue.formatted(style)
    }

    /// The amount without any sign, such as "$12.50" for minus 12.50.
    public func formattedMagnitude(locale: Locale = .current) -> String {
        decimalValue.magnitude.formatted(currencyStyle(locale: locale))
    }

    /// The locale's style for the currency. Some currencies are normally shown without decimals
    /// (HUF, LBP, IQD) although amounts can have them, so a real fraction is shown rather than rounded away.
    private func currencyStyle(locale: Locale) -> Decimal.FormatStyle.Currency {
        let style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
        return minorUnits % Currency.minorUnitScale(for: currencyCode) == 0 ? style : style.precision(.fractionLength(exponent))
    }

    /// A plain number string without symbol or grouping, such as "12.50", for text fields.
    /// `MoneyParser` reads it back with the same locale.
    public func plainString(locale: Locale = .current) -> String {
        decimalValue.formatted(
            .number.locale(locale).grouping(.never).precision(.fractionLength(exponent))
        )
    }
}
