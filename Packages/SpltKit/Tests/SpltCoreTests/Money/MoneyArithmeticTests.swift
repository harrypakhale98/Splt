import Testing
@testable import SpltCore

@Suite("Money arithmetic")
struct MoneyArithmeticTests {
    @Test func addsAndSubtracts() throws {
        #expect(try usd(150).adding(usd(275)) == usd(425))
        #expect(try usd(150).subtracting(usd(275)) == usd(-125))
    }

    @Test func rejectsMixedCurrencies() {
        #expect(throws: MoneyError.currencyMismatch("USD", "EUR")) { try usd(1).adding(eur(1)) }
        #expect(throws: MoneyError.currencyMismatch("USD", "EUR")) { try usd(1).subtracting(eur(1)) }
        #expect(usd(1).isSameCurrency(as: usd(2)))
        #expect(!usd(1).isSameCurrency(as: eur(1)))
    }

    @Test func detectsOverflow() {
        #expect(throws: MoneyError.overflow) { try usd(Int64.max).adding(usd(1)) }
        #expect(throws: MoneyError.overflow) { try usd(Int64.min).subtracting(usd(1)) }
        #expect(throws: MoneyError.overflow) { try usd(Int64.min).negated() }
    }

    @Test func negates() throws {
        #expect(try usd(5).negated() == usd(-5))
        #expect(try usd(0).negated() == usd(0))
    }

    @Test func signFlags() {
        #expect(usd(0).isZero)
        #expect(usd(1).isPositive)
        #expect(usd(-1).isNegative)
        #expect(!usd(1).isNegative)
        #expect(Money.zero(currencyCode: "jpy") == Money(minorUnits: 0, currencyCode: "JPY"))
    }

    @Test func sumsSequences() throws {
        #expect(try Money.sum([usd(100), usd(250), usd(-50)], currencyCode: "USD") == usd(300))
        #expect(try Money.sum([Money](), currencyCode: "USD") == usd(0))
        #expect(throws: MoneyError.currencyMismatch("USD", "EUR")) {
            try Money.sum([usd(1), eur(1)], currencyCode: "USD")
        }
    }

    @Test func percentageRoundsHalfAwayFromZero() throws {
        #expect(try usd(10_000).percentage(basisPoints: 1_800) == usd(1_800))
        #expect(try usd(1_001).percentage(basisPoints: 1_800) == usd(180))
        #expect(try usd(1_003).percentage(basisPoints: 5_000) == usd(502))
        #expect(try usd(-1_003).percentage(basisPoints: 5_000) == usd(-502))
        #expect(try usd(1_000).percentage(basisPoints: 0) == usd(0))
        #expect(try usd(1_000).percentage(basisPoints: 12_500) == usd(1_250))
    }

    @Test func percentageDoesNotOverflowOnLargeInput() throws {
        let big = usd(Int64.max / 2)
        #expect(try big.percentage(basisPoints: 10_000) == big)
        #expect(throws: MoneyError.overflow) { try usd(Int64.max).percentage(basisPoints: 20_000) }
    }
}
