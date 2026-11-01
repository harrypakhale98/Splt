import Foundation
import Testing
@testable import SpltCore

@Suite("Money")
struct MoneyTests {
    @Test func comparesByMinorUnits() {
        let small = Money(minorUnits: 100, currencyCode: "USD")
        let large = Money(minorUnits: 250, currencyCode: "USD")
        #expect(small < large)
    }

    @Test func normalisesCurrencyCode() {
        let money = Money(minorUnits: 5, currencyCode: "usd")
        #expect(money.currencyCode == "USD")
        #expect(money == Money(minorUnits: 5, currencyCode: "USD"))
    }

    @Test func ordersByCurrencyThenAmount() {
        let sorted = [
            Money(minorUnits: 5, currencyCode: "USD"),
            Money(minorUnits: 9, currencyCode: "EUR"),
            Money(minorUnits: 1, currencyCode: "USD")
        ].sorted()
        #expect(sorted.map(\.currencyCode) == ["EUR", "USD", "USD"])
        #expect(sorted.map(\.minorUnits) == [9, 1, 5])
    }

    @Test func exponentFollowsCurrency() {
        #expect(Money(minorUnits: 1, currencyCode: "JPY").exponent == 0)
        #expect(Money(minorUnits: 1, currencyCode: "USD").exponent == 2)
        #expect(Money(minorUnits: 1, currencyCode: "KWD").exponent == 3)
    }

    @Test func codableRoundTrip() throws {
        let money = Money(minorUnits: -1234, currencyCode: "eur")
        let data = try JSONEncoder().encode(money)
        let decoded = try JSONDecoder().decode(Money.self, from: data)
        #expect(decoded == money)
    }

    @Test func decodingNormalisesCurrencyCode() throws {
        let json = Data(#"{"minorUnits":10,"currencyCode":"gbp"}"#.utf8)
        let decoded = try JSONDecoder().decode(Money.self, from: json)
        #expect(decoded.currencyCode == "GBP")
    }
}
