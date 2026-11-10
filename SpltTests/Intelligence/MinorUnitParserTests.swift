import SpltCore
import Testing
@testable import Splt

@Suite("Minor unit parsing")
struct MinorUnitParserTests {
    @Test(arguments: [
        ("12", 1200), ("12.5", 1250), ("12.50", 1250), ("12,5", 1250), ("0.99", 99),
        ("1,234.50", 123_450), ("1.234,50", 123_450), ("1,234", 123_400), ("1.234", 123_400),
        ("1,234,567", 123_456_700), ("1'234.5", 123_450), ("12.", 1200)
    ] as [(String, Int64)])
    func twoDigitCurrency(text: String, expected: Int64) {
        #expect(MinorUnitParser.minorUnits(from: text, fractionDigits: 2) == expected)
    }

    @Test func zeroDigitCurrencyTreatsSeparatorsAsGrouping() {
        #expect(MinorUnitParser.minorUnits(from: "1,200", fractionDigits: 0) == 1200)
        #expect(MinorUnitParser.minorUnits(from: "1200", fractionDigits: 0) == 1200)
        #expect(MinorUnitParser.minorUnits(from: "12.5", fractionDigits: 0) == nil)
    }

    @Test func threeDigitCurrencyReadsDotAsDecimal() {
        #expect(MinorUnitParser.minorUnits(from: "1.234", fractionDigits: 3) == 1234)
        #expect(MinorUnitParser.minorUnits(from: "1,234", fractionDigits: 3) == 1_234_000)
    }

    @Test(arguments: ["", "abc", "12.345.6", "1.2.3", "12x", "--"])
    func rejectsNonsense(text: String) {
        #expect(MinorUnitParser.minorUnits(from: text, fractionDigits: 2) == nil)
    }

    @Test func amountsAboveWhatCanBeTypedAreRefused() {
        #expect(MinorUnitParser.minorUnits(from: "10000000000000", currencyCode: "USD") == MoneyParser.maximumMinorUnits)
        #expect(MinorUnitParser.minorUnits(from: "10000000000000.01", currencyCode: "USD") == nil)
        #expect(MinorUnitParser.minorUnits(from: "90000000000000", currencyCode: "USD") == nil)
    }

    @Test func rejectsTooManyDecimals() {
        #expect(MinorUnitParser.minorUnits(from: "1.2345", fractionDigits: 2) == nil)
    }

    @Test func looksUpFractionDigitsByCode() {
        #expect(MinorUnitParser.fractionDigits(for: "USD") == 2)
        #expect(MinorUnitParser.fractionDigits(for: "jpy") == 0)
        #expect(MinorUnitParser.fractionDigits(for: "KWD") == 3)
        #expect(MinorUnitParser.minorUnits(from: "1200", currencyCode: "JPY") == 1200)
    }

    @Test func spelledNumbersBecomeDigits() {
        #expect(NumberWords.replacingSpelledNumbers(in: "dinner sixty with Sam") == "dinner 60 with Sam")
        #expect(NumberWords.replacingSpelledNumbers(in: "taxi twenty five dollars") == "taxi 25 dollars")
        #expect(NumberWords.replacingSpelledNumbers(in: "rent a hundred and twenty") == "rent 120")
        #expect(NumberWords.replacingSpelledNumbers(in: "one night three friends") == "one night three friends")
        #expect(NumberWords.replacingSpelledNumbers(in: "lunch five dollars") == "lunch 5 dollars")
    }

    @Test func currencyWordsAndSymbolsResolve() {
        #expect(CurrencyDetector.codes(in: "coffee 4.80 euros", defaultCode: "USD") == ["EUR"])
        #expect(CurrencyDetector.codes(in: "taxi $20", defaultCode: "CAD") == ["CAD"])
        #expect(CurrencyDetector.codes(in: "taxi $20", defaultCode: "INR") == ["USD"])
        #expect(CurrencyDetector.codes(in: "try all of it", defaultCode: "USD").isEmpty)
        #expect(CurrencyDetector.codes(in: "rent 500 gbp", defaultCode: "USD") == ["GBP"])
    }
}
