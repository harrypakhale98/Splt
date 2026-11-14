import Foundation
import SpltCore

/// Turns a decimal amount, as Wallet, a bank text or a screenshot gives it, into `Money`.
enum PaymentAmount {
    /// Rounded to the currency's smallest unit. Nil unless it is a positive, believable amount.
    static func money(_ value: Decimal, currencyCode: String) -> Money? {
        let code = currencyCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 3, value > 0, value < 1_000_000_000 else { return nil }
        var scaled = value * Decimal(sign: .plus, exponent: Currency.minorUnitExponent(for: code), significand: 1)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let units = NSDecimalNumber(decimal: rounded).int64Value
        guard units > 0 else { return nil }
        return Money(minorUnits: units, currencyCode: code)
    }

    /// The currency this iPhone uses, for amounts that don't name one.
    static var localCurrencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }
}
