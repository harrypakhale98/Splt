import Foundation
import Testing
@testable import SpltCore

@Suite("Money formatting")
struct MoneyFormattingTests {
    private let us = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")

    @Test func decimalValueUsesCurrencyExponent() {
        #expect(Money(minorUnits: 1250, currencyCode: "USD").decimalValue == Decimal(string: "12.5"))
        #expect(Money(minorUnits: 1250, currencyCode: "JPY").decimalValue == 1250)
        #expect(Money(minorUnits: 1234, currencyCode: "KWD").decimalValue == Decimal(string: "1.234"))
        #expect(Money(minorUnits: -5, currencyCode: "USD").decimalValue == Decimal(string: "-0.05"))
    }

    @Test func formatsDollars() {
        #expect(Money(minorUnits: 1250, currencyCode: "USD").formatted(locale: us) == "$12.50")
        #expect(Money(minorUnits: 123_456, currencyCode: "USD").formatted(locale: us) == "$1,234.56")
        #expect(Money(minorUnits: -1250, currencyCode: "USD").formatted(locale: us) == "-$12.50")
    }

    @Test func formatsZeroDecimalCurrency() {
        #expect(Money(minorUnits: 1235, currencyCode: "JPY").formatted(locale: us) == "\u{00A5}1,235")
    }

    @Test func formatsThreeDecimalCurrency() {
        let text = Money(minorUnits: 12_345, currencyCode: "KWD").formatted(locale: us)
        #expect(text.contains("12.345"))
    }

    @Test func respectsLocale() {
        let text = Money(minorUnits: 123_456, currencyCode: "EUR").formatted(locale: germany)
        #expect(text.contains("1.234,56"))
        #expect(text.contains("\u{20AC}"))
    }

    @Test func plusSignIsOptIn() {
        let positive = Money(minorUnits: 500, currencyCode: "USD")
        #expect(positive.formatted(locale: us, showsPlusSign: true) == "+$5.00")
        #expect(positive.formatted(locale: us) == "$5.00")
    }

    @Test func plainStringHasNoSymbolOrGrouping() {
        #expect(Money(minorUnits: 123_456, currencyCode: "USD").plainString(locale: us) == "1234.56")
        #expect(Money(minorUnits: 123_456, currencyCode: "USD").plainString(locale: germany) == "1234,56")
        #expect(Money(minorUnits: 500, currencyCode: "JPY").plainString(locale: us) == "500")
        #expect(Money(minorUnits: 1_005, currencyCode: "KWD").plainString(locale: us) == "1.005")
    }

    @Test(arguments: [0, 1, 5, 99, 100, 123_456, -250, -1])
    func plainStringRoundTripsThroughParser(units: Int64) throws {
        for locale in [us, germany, Locale(identifier: "fr_FR"), Locale(identifier: "sv_SE")] {
            let money = Money(minorUnits: units, currencyCode: "USD")
            let parsed = try MoneyParser.parse(money.plainString(locale: locale), currencyCode: "USD", locale: locale)
            #expect(parsed == money)
        }
    }
}
