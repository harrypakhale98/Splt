import Foundation
import Testing
@testable import SpltCore

@Suite("Exchange rates")
struct ExchangeRatesTests {
    private let rates = ExchangeRates(
        baseCurrency: "EUR",
        rates: ["USD": Decimal(string: "1.10")!, "JPY": 160, "KWD": Decimal(string: "0.33")!, "GBP": Decimal(string: "0.85")!]
    )


    @Test func rateFromBaseAndToBase() {
        #expect(rates.rate(from: "EUR", to: "USD") == Decimal(string: "1.10"))
        #expect(rates.rate(from: "USD", to: "EUR") == 1 / Decimal(string: "1.10")!)
        #expect(rates.rate(from: "USD", to: "USD") == 1)
    }

    @Test func crossRatesGoThroughTheBase() throws {
        let rate = try #require(rates.rate(from: "USD", to: "GBP"))
        #expect(rate == Decimal(string: "0.85")! / Decimal(string: "1.10")!)
    }

    @Test func unknownCurrenciesHaveNoRate() {
        #expect(rates.rate(from: "USD", to: "CAD") == nil)
        #expect(throws: ExchangeRatesError.missingRate(from: "CAD", to: "USD")) {
            try rates.convert(money(100, "CAD"), to: "USD")
        }
    }

    @Test func convertsBetweenDifferentExponents() throws {
        // 10.00 EUR is 11.00 USD, 1600 JPY and 3.300 KWD
        #expect(try rates.convert(money(1000, "EUR"), to: "USD") == money(1100, "USD"))
        #expect(try rates.convert(money(1000, "EUR"), to: "JPY") == money(1600, "JPY"))
        #expect(try rates.convert(money(1000, "EUR"), to: "KWD") == money(3300, "KWD"))
        #expect(try rates.convert(money(1600, "JPY"), to: "EUR") == money(1000, "EUR"))
        #expect(try rates.convert(money(3300, "KWD"), to: "EUR") == money(1000, "EUR"))
    }

    @Test func sameCurrencyIsUnchanged() throws {
        #expect(try rates.convert(money(12_345, "USD"), to: "usd") == money(12_345, "USD"))
    }

    @Test func roundsHalfAwayFromZero() throws {
        let half = ExchangeRates(baseCurrency: "USD", rates: ["EUR": Decimal(string: "0.5")!])
        #expect(try half.convert(money(5, "USD"), to: "EUR") == money(3, "EUR"))
        #expect(try half.convert(money(-5, "USD"), to: "EUR") == money(-3, "EUR"))
        #expect(try half.convert(money(4, "USD"), to: "EUR") == money(2, "EUR"))
    }

    @Test func pinnedRatesWinAndWorkBothWays() throws {
        let pinned = ExchangeRates(
            baseCurrency: "EUR",
            rates: ["USD": Decimal(string: "1.10")!],
            pinned: [PinnedRate(from: "EUR", to: "USD", rate: 2)]
        )
        #expect(pinned.rate(from: "EUR", to: "USD") == 2)
        #expect(pinned.rate(from: "USD", to: "EUR") == Decimal(string: "0.5"))
        #expect(try pinned.convert(money(1000, "EUR"), to: "USD") == money(2000, "USD"))
    }

    @Test func nonPositiveRatesAreIgnored() {
        let broken = ExchangeRates(baseCurrency: "EUR", rates: ["USD": 0])
        #expect(broken.rate(from: "EUR", to: "USD") == nil)
        #expect(broken.rate(from: "USD", to: "EUR") == nil)
    }

    @Test func codableRoundTrip() throws {
        let value = ExchangeRates(
            baseCurrency: "eur",
            rates: ["usd": Decimal(string: "1.0875")!],
            pinned: [PinnedRate(from: "gbp", to: "usd", rate: Decimal(string: "1.25")!)],
            asOf: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try JSONDecoder().decode(ExchangeRates.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
        #expect(decoded.baseCurrency == "EUR")
        #expect(decoded.rates["USD"] == Decimal(string: "1.0875"))
    }

    @Test func batchConversionKeepsZeroSumBalancesAtZero() throws {
        // three people each owed or owing odd amounts, converted so each share has a fraction
        let balances: [String: [Money]] = [
            "a": [money(3333, "EUR")],
            "b": [money(-1111, "EUR")],
            "c": [money(-2222, "EUR")]
        ]
        let converted = try rates.convert(balances, to: "USD")
        #expect(converted.values.reduce(0) { $0 + $1.minorUnits } == 0)
        #expect(converted["a"] == money(3666, "USD"))
        #expect(converted["b"] == money(-1222, "USD"))
        #expect(converted["c"] == money(-2444, "USD"))
    }

    @Test func batchConversionReconcilesRounding() throws {
        let third = ExchangeRates(baseCurrency: "USD", rates: ["EUR": Decimal(string: "0.333")!])
        let balances: [String: [Money]] = [
            "a": [money(100, "USD")],
            "b": [money(100, "USD")],
            "c": [money(-200, "USD")]
        ]
        let converted = try third.convert(balances, to: "EUR")
        // exact values are 33.3, 33.3 and -66.6; floors are 33, 33, -67 and one unit is spare
        #expect(converted.values.reduce(0) { $0 + $1.minorUnits } == 0)
        #expect(converted["a"]?.minorUnits == 33)
        #expect(converted["b"]?.minorUnits == 33)
        #expect(converted["c"]?.minorUnits == -66)
    }

    @Test func batchConversionMixesCurrenciesPerKey() throws {
        let balances: [String: [Money]] = [
            "a": [money(1000, "EUR"), money(1100, "USD")],
            "b": [money(-1000, "EUR"), money(-1100, "USD")]
        ]
        let converted = try rates.convert(balances, to: "EUR")
        #expect(converted["a"] == money(2000, "EUR"))
        #expect(converted["b"] == money(-2000, "EUR"))
    }

    @Test func batchConversionFailsOnMissingRate() {
        let balances: [String: [Money]] = ["a": [money(1, "CAD")]]
        #expect(throws: ExchangeRatesError.missingRate(from: "CAD", to: "EUR")) {
            try rates.convert(balances, to: "EUR")
        }
    }

    @Test func batchConversionOfNothingIsEmpty() throws {
        let empty = try rates.convert([String: [Money]](), to: "EUR")
        #expect(empty.isEmpty)
    }

    @Test func batchConversionPropertyZeroSumStaysZeroSum() throws {
        var generator = SeededGenerator(seed: 7)
        let odd = ExchangeRates(
            baseCurrency: "USD",
            rates: ["EUR": Decimal(string: "0.9137")!, "JPY": Decimal(string: "151.37")!, "KWD": Decimal(string: "0.3071")!]
        )
        for code in ["EUR", "JPY", "KWD"] {
            for _ in 0..<200 {
                let count = Int.random(in: 2...8, using: &generator)
                var values = (0..<count - 1).map { _ in Int64.random(in: -50_000...50_000, using: &generator) }
                values.append(-values.reduce(0, +))
                var input: [Int: [Money]] = [:]
                for (index, value) in values.enumerated() { input[index] = [money(value, "USD")] }
                let output = try odd.convert(input, to: code)
                #expect(output.values.reduce(0) { $0 + $1.minorUnits } == 0)
            }
        }
    }
}
