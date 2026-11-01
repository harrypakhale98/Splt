import Testing
@testable import SpltCore

@Suite("Currency")
struct CurrencyTests {
    @Test(arguments: ["JPY", "KRW", "VND", "CLP", "ISK", "XOF", "UGX", "PYG"])
    func zeroDecimalCurrencies(code: String) {
        #expect(Currency.minorUnitExponent(for: code) == 0)
        #expect(Currency.minorUnitScale(for: code) == 1)
    }

    @Test(arguments: ["KWD", "BHD", "OMR", "JOD", "TND", "IQD", "LYD"])
    func threeDecimalCurrencies(code: String) {
        #expect(Currency.minorUnitExponent(for: code) == 3)
        #expect(Currency.minorUnitScale(for: code) == 1_000)
    }

    @Test(arguments: ["USD", "EUR", "GBP", "INR", "CAD", "HUF", "XXX"])
    func everythingElseHasTwoDecimals(code: String) {
        #expect(Currency.minorUnitExponent(for: code) == 2)
        #expect(Currency.minorUnitScale(for: code) == 100)
    }

    @Test func lookupIgnoresCase() {
        #expect(Currency.minorUnitExponent(for: "jpy") == 0)
        #expect(Currency.minorUnitExponent(for: "kwd") == 3)
    }
}
