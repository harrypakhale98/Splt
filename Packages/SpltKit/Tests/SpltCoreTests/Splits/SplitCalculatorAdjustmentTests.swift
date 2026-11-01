import Testing
@testable import SpltCore

@Suite("Adjustment splits")
struct SplitCalculatorAdjustmentTests {
    private let a = person(1), b = person(2), c = person(3)

    private func shares(_ participants: Set<PersonID>, _ adjustments: [PersonID: Money], _ total: Money) throws -> [PersonID: Money] {
        try SplitCalculator.shares(for: .adjustments(participants: participants, adjustments: adjustments), total: total)
    }

    @Test func noAdjustmentsIsAnEqualSplit() throws {
        #expect(try shares([a, b, c], [:], usd(900)) == [a: usd(300), b: usd(300), c: usd(300)])
    }

    @Test func plusAmountsAreAddedOnTopOfTheEqualPart() throws {
        // $100 total, a ordered an extra $10: the other $90 is shared equally by three
        let result = try shares([a, b, c], [a: usd(1000)], usd(10_000))
        #expect(result == [a: usd(4000), b: usd(3000), c: usd(3000)])
    }

    @Test func minusAmountsReduceAPersonsShare() throws {
        // c has $6 less: remaining $106 over three people is 35.33 each, c pays 29.33
        let result = try shares([a, b, c], [c: usd(-600)], usd(10_000))
        #expect(result.values.reduce(0) { $0 + $1.minorUnits } == 10_000)
        #expect(result == [a: usd(3534), b: usd(3533), c: usd(2933)])
    }

    @Test func adjustmentsCanCancelOut() throws {
        let result = try shares([a, b], [a: usd(500), b: usd(-500)], usd(1000))
        #expect(result == [a: usd(1000), b: usd(0)])
    }

    @Test func adjustmentsMayTakeTheWholeTotal() throws {
        let result = try shares([a, b], [a: usd(700), b: usd(300)], usd(1000))
        #expect(result == [a: usd(700), b: usd(300)])
    }

    @Test func rejectsNegativeResults() {
        #expect(throws: SplitError.negativeShare(b)) {
            try shares([a, b], [a: usd(1500)], usd(1000))
        }
    }

    @Test func rejectsAdjustmentsForOutsiders() {
        #expect(throws: SplitError.adjustmentForNonParticipant(c)) {
            try shares([a, b], [c: usd(100)], usd(1000))
        }
    }

    @Test func rejectsOtherCurrenciesAndEmptyGroups() {
        #expect(throws: SplitError.currencyMismatch(expected: "USD", found: "EUR")) {
            try shares([a, b], [a: eur(100)], usd(1000))
        }
        #expect(throws: SplitError.noParticipants) { try shares([], [:], usd(1000)) }
    }

    @Test func refundsKeepAdjustmentsInTheSameDirection() throws {
        let result = try shares([a, b, c], [a: usd(-1000)], usd(-10_000))
        #expect(result == [a: usd(-4000), b: usd(-3000), c: usd(-3000)])
    }
}
