import Foundation
import Testing
@testable import SpltCore

@Suite("Money parser")
struct MoneyParserTests {
    private let us = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")
    private let france = Locale(identifier: "fr_FR")
    private let swiss = Locale(identifier: "de_CH")

    private func parse(_ text: String, _ code: String = "USD", _ locale: Locale? = nil) throws -> Int64 {
        try MoneyParser.parse(text, currencyCode: code, locale: locale ?? us).minorUnits
    }

    @Test func plainNumbers() throws {
        #expect(try parse("12") == 1200)
        #expect(try parse("12.5") == 1250)
        #expect(try parse("12.50") == 1250)
        #expect(try parse("0.07") == 7)
        #expect(try parse(".5") == 50)
        #expect(try parse("12.") == 1200)
        #expect(try parse("0") == 0)
        #expect(try parse("007.25") == 725)
    }

    @Test func commaAsDecimalSeparator() throws {
        #expect(try parse("12,50") == 1250)
        #expect(try parse("12,5") == 1250)
        #expect(try parse("0,99") == 99)
        #expect(try parse("12,50", "EUR", germany) == 1250)
        #expect(try parse("12,5", "EUR", germany) == 1250)
    }

    @Test func thousandsSeparators() throws {
        #expect(try parse("1,234.50") == 123_450)
        #expect(try parse("1,234,567.89") == 123_456_789)
        #expect(try parse("1.234,50", "EUR", germany) == 123_450)
        #expect(try parse("1.234.567,89", "EUR", germany) == 123_456_789)
        #expect(try parse("1,234") == 123_400)
        #expect(try parse("1.234", "EUR", germany) == 123_400)
        #expect(try parse("1,234,567") == 123_456_700)
    }

    @Test func indianGrouping() throws {
        #expect(try parse("1,23,456.50", "INR") == 12_345_650)
    }

    @Test func spaceAndApostropheGrouping() throws {
        #expect(try parse("1 234,56", "EUR", france) == 123_456)
        #expect(try parse("1\u{202F}234,56", "EUR", france) == 123_456)
        #expect(try parse("1\u{00A0}234.56") == 123_456)
        #expect(try parse("1'234.50", "CHF", swiss) == 123_450)
        #expect(try parse("1\u{2019}234.50", "CHF", swiss) == 123_450)
        #expect(try parse("12 345 678") == 1_234_567_800)
    }

    @Test func lonelySeparatorFollowsTheLocale() throws {
        #expect(try parse("1.234", "KWD", us) == 1_234)
        #expect(try parse("1,234", "KWD", us) == 1_234_000)
        #expect(try parse("1,234", "KWD", germany) == 1_234)
        #expect(try parse("0.500", "KWD") == 500)
    }

    @Test func zeroDecimalCurrencies() throws {
        #expect(try parse("1234", "JPY") == 1234)
        #expect(try parse("1,234", "JPY") == 1234)
        #expect(try parse("1.234", "JPY", germany) == 1234)
        #expect(try parse("12.0", "JPY") == 12)
        #expect(try parse("\u{00A5}1,234,567", "JPY") == 1_234_567)
        #expect(throws: MoneyParseError.tooManyFractionDigits) { try parse("12.5", "JPY") }
        #expect(throws: MoneyParseError.tooManyFractionDigits) { try parse("12,50", "KRW") }
    }

    @Test func threeDecimalCurrencies() throws {
        #expect(try parse("1.5", "KWD") == 1_500)
        #expect(try parse("12.345", "BHD") == 12_345)
        #expect(throws: MoneyParseError.tooManyFractionDigits) { try parse("12.3456", "KWD") }
    }

    @Test func tooManyDecimalsIsRejectedButTrailingZerosAreFine() throws {
        #expect(throws: MoneyParseError.tooManyFractionDigits) { try parse("12.505") }
        #expect(throws: MoneyParseError.tooManyFractionDigits) { try parse("12,505", "USD", germany) }
        #expect(try parse("12.500") == 1250)
        #expect(try parse("12.5000000") == 1250)
    }

    @Test func ignoresSymbolsAndCodes() throws {
        #expect(try parse("$12.50") == 1250)
        #expect(try parse("$ 12.50") == 1250)
        #expect(try parse("12.50 USD") == 1250)
        #expect(try parse("USD 12.50") == 1250)
        #expect(try parse("12,50 \u{20AC}", "EUR", germany) == 1250)
        #expect(try parse("\u{20AC}1.234,50", "EUR", germany) == 123_450)
        #expect(try parse("  12.50  ") == 1250)
        #expect(try parse("Rs. 12.50", "INR") == 1250)
        #expect(try parse("Rs.12", "INR") == 1200)
    }

    @Test func negativeAmounts() throws {
        #expect(try parse("-12.50") == -1250)
        #expect(try parse("-$12.50") == -1250)
        #expect(try parse("$-12.50") == -1250)
        #expect(try parse("12.50-") == -1250)
        #expect(try parse("(12.50)") == -1250)
        #expect(try parse("\u{2212}12.50") == -1250)
        #expect(try parse("-0") == 0)
        #expect(try parse("+12.50") == 1250)
    }

    @Test func negativeCanBeForbidden() {
        #expect(throws: MoneyParseError.negativeNotAllowed) {
            try MoneyParser.parse("-5", currencyCode: "USD", locale: us, allowNegative: false)
        }
        #expect(throws: MoneyParseError.negativeNotAllowed) {
            try MoneyParser.parse("(5)", currencyCode: "USD", locale: us, allowNegative: false)
        }
    }

    @Test func nonAsciiDigits() throws {
        #expect(try parse("\u{0661}\u{0662}.\u{0665}") == 1250)
        #expect(try parse("\u{FF11}\u{FF12}") == 1200)
    }

    @Test func emptyInput() {
        #expect(throws: MoneyParseError.empty) { try parse("") }
        #expect(throws: MoneyParseError.empty) { try parse("   ") }
    }

    @Test(arguments: [
        "abc", "$", "-", ".", ",", "12.3.4", "1,2,3", "1,23,4567", "12a5", "1.5k", "--5",
        "1,234.567,89", "12,50.30,10", "1 2 3", "0,500,000", "12 34", "5 %", "12.50!", "1,,234"
    ])
    func rejectsGarbage(text: String) {
        #expect(throws: MoneyParseError.self) { try parse(text) }
    }

    @Test func rejectsHugeAmounts() {
        #expect(throws: MoneyParseError.outOfRange) { try parse("99999999999999999999") }
        #expect(throws: MoneyParseError.outOfRange) { try parse("92233720368547758.08") }
        #expect(throws: Never.self) { try parse("92233720368547758.07") }
    }

    @Test func moneyInitialiserParses() throws {
        let money = try Money(parsing: "1,234.50", currencyCode: "usd", locale: us)
        #expect(money == Money(minorUnits: 123_450, currencyCode: "USD"))
    }
}
