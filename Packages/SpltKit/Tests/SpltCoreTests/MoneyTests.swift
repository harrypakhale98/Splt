import Testing
@testable import SpltCore

@Suite("Money")
struct MoneyTests {
    @Test func comparesByMinorUnits() {
        let small = Money(minorUnits: 100, currencyCode: "USD")
        let large = Money(minorUnits: 250, currencyCode: "USD")
        #expect(small < large)
    }
}
