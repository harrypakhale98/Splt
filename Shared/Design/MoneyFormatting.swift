import Foundation
import SpltCore

/// How Splt writes an amount, in the app and its widgets.
enum MoneyFormatting {
    /// Display only. Stored amounts stay in integer minor units.
    static func string(_ money: Money, locale: Locale = .current, showsSign: Bool = false) -> String {
        let text = magnitudeString(money, locale: locale)
        guard showsSign, money.minorUnits != 0 else { return text }
        return (money.minorUnits > 0 ? "+" : "-") + text
    }

    /// The amount without any sign.
    static func magnitudeString(_ money: Money, locale: Locale = .current) -> String {
        money.formattedMagnitude(locale: locale)
    }
}
