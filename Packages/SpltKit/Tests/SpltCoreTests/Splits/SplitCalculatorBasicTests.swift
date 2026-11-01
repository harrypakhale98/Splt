import Testing
@testable import SpltCore

@Suite("Equal, exact, percentage and share splits")
struct SplitCalculatorBasicTests {
    private let a = person(1), b = person(2), c = person(3), d = person(4)

    private func shares(_ split: SplitDefinition, _ total: Money) throws -> [PersonID: Money] {
        try SplitCalculator.shares(for: split, total: total)
    }

    @Test func equalSplitDividesEvenly() throws {
        let result = try shares(.equal(participants: [a, b, c]), usd(900))
        #expect(result == [a: usd(300), b: usd(300), c: usd(300)])
    }

    @Test func equalSplitGivesSpareCentsToLowestIds() throws {
        let result = try shares(.equal(participants: [c, a, b]), usd(1000))
        #expect(result == [a: usd(334), b: usd(333), c: usd(333)])
        let two = try shares(.equal(participants: [a, b, c, d]), usd(1002))
        #expect(two == [a: usd(251), b: usd(251), c: usd(250), d: usd(250)])
    }

    @Test func equalSplitOfOnePersonIsTheWholeTotal() throws {
        #expect(try shares(.equal(participants: [a]), usd(777)) == [a: usd(777)])
    }

    @Test func equalSplitWorksWithZeroAndThreeDecimalCurrencies() throws {
        let yen = try shares(.equal(participants: [a, b, c]), money(1000, "JPY"))
        #expect(yen == [a: money(334, "JPY"), b: money(333, "JPY"), c: money(333, "JPY")])
        let dinar = try shares(.equal(participants: [a, b]), money(1001, "KWD"))
        #expect(dinar == [a: money(501, "KWD"), b: money(500, "KWD")])
    }

    @Test func equalSplitRequiresPeople() {
        #expect(throws: SplitError.noParticipants) { try shares(.equal(participants: []), usd(100)) }
    }

    @Test func zeroTotalGivesZeroShares() throws {
        #expect(try shares(.equal(participants: [a, b]), usd(0)) == [a: usd(0), b: usd(0)])
    }

    @Test func exactAmountsPassThrough() throws {
        let result = try shares(.exact(amounts: [a: usd(1200), b: usd(800), c: usd(0)]), usd(2000))
        #expect(result == [a: usd(1200), b: usd(800), c: usd(0)])
    }

    @Test func exactAmountsMustAddUp() {
        #expect(throws: SplitError.exactAmountsDoNotMatchTotal(expected: usd(2000), actual: usd(1900))) {
            try shares(.exact(amounts: [a: usd(1200), b: usd(700)]), usd(2000))
        }
    }

    @Test func exactAmountsRejectNegativesAndOtherCurrencies() {
        #expect(throws: SplitError.negativeShare(b)) {
            try shares(.exact(amounts: [a: usd(2500), b: usd(-500)]), usd(2000))
        }
        #expect(throws: SplitError.currencyMismatch(expected: "USD", found: "EUR")) {
            try shares(.exact(amounts: [a: usd(1000), b: eur(1000)]), usd(2000))
        }
        #expect(throws: SplitError.noParticipants) { try shares(.exact(amounts: [:]), usd(0)) }
    }

    @Test func percentagesUseBasisPointsExactly() throws {
        let result = try shares(.percentages(basisPoints: [a: 3333, b: 3333, c: 3334]), usd(10_000))
        #expect(result == [a: usd(3333), b: usd(3333), c: usd(3334)])
        #expect(result.values.reduce(0) { $0 + $1.minorUnits } == 10_000)
    }

    @Test func percentagesRoundWithLargestRemainder() throws {
        // 50 / 25 / 25 of $1.01 is 50.5, 25.25, 25.25
        let result = try shares(.percentages(basisPoints: [a: 5000, b: 2500, c: 2500]), usd(101))
        #expect(result == [a: usd(51), b: usd(25), c: usd(25)])
    }

    @Test func percentagesMustTotalOneHundred() {
        #expect(throws: SplitError.percentagesDoNotSumToHundred(actualBasisPoints: 9_900)) {
            try shares(.percentages(basisPoints: [a: 5000, b: 4900]), usd(100))
        }
        #expect(throws: SplitError.percentagesDoNotSumToHundred(actualBasisPoints: 10_100)) {
            try shares(.percentages(basisPoints: [a: 5100, b: 5000]), usd(100))
        }
        #expect(throws: SplitError.negativePercentage(b)) {
            try shares(.percentages(basisPoints: [a: 11_000, b: -1000]), usd(100))
        }
        #expect(throws: SplitError.noParticipants) { try shares(.percentages(basisPoints: [:]), usd(100)) }
    }

    @Test func zeroPercentGetsNothing() throws {
        let result = try shares(.percentages(basisPoints: [a: 10_000, b: 0]), usd(999))
        #expect(result == [a: usd(999), b: usd(0)])
    }

    @Test func sharesAreProportional() throws {
        let result = try shares(.shares(weights: [a: 2, b: 1, c: 1]), usd(1000))
        #expect(result == [a: usd(500), b: usd(250), c: usd(250)])
    }

    @Test func sharesRoundWithLargestRemainder() throws {
        let result = try shares(.shares(weights: [a: 1, b: 1, c: 5]), usd(800))
        #expect(result == [a: usd(114), b: usd(114), c: usd(572)])
        #expect(result.values.reduce(0) { $0 + $1.minorUnits } == 800)
    }

    @Test func sharesWithZeroWeightPayNothing() throws {
        let result = try shares(.shares(weights: [a: 0, b: 3]), usd(500))
        #expect(result == [a: usd(0), b: usd(500)])
    }

    @Test func sharesRejectBadWeights() {
        #expect(throws: SplitError.zeroTotalWeight) { try shares(.shares(weights: [a: 0, b: 0]), usd(100)) }
        #expect(throws: SplitError.negativeWeight(b)) { try shares(.shares(weights: [a: 1, b: -1]), usd(100)) }
        #expect(throws: SplitError.noParticipants) { try shares(.shares(weights: [:]), usd(100)) }
    }

    @Test func refundsMirrorPurchases() throws {
        let split = SplitDefinition.equal(participants: [a, b, c])
        let purchase = try shares(split, usd(1000))
        let refund = try shares(split, usd(-1000))
        #expect(refund == purchase.mapValues { usd(-$0.minorUnits) })
        #expect(refund.values.reduce(0) { $0 + $1.minorUnits } == -1000)
    }

    @Test func refundsWorkForEveryStrategy() throws {
        let weights = try shares(.shares(weights: [a: 1, b: 2]), usd(-1000))
        #expect(weights == [a: usd(-333), b: usd(-667)])
        let percentages = try shares(.percentages(basisPoints: [a: 2500, b: 7500]), usd(-1000))
        #expect(percentages == [a: usd(-250), b: usd(-750)])
        let exact = try shares(.exact(amounts: [a: usd(-400), b: usd(-600)]), usd(-1000))
        #expect(exact == [a: usd(-400), b: usd(-600)])
    }

    @Test func exactRefundRejectsPositiveShares() {
        #expect(throws: SplitError.negativeShare(a)) {
            try shares(.exact(amounts: [a: usd(1500), b: usd(-2500)]), usd(-1000))
        }
    }

    @Test func calculateReturnsTotalAndNoBreakdown() throws {
        let result = try SplitCalculator.calculate(.equal(participants: [a, b]), total: usd(100))
        #expect(result.total == usd(100))
        #expect(result.breakdown == nil)
        #expect(result.share(for: a) == usd(50))
        #expect(result.share(for: c) == usd(0))
    }

    @Test func participantsListEveryone() {
        #expect(SplitDefinition.equal(participants: [a, b]).participants == [a, b])
        #expect(SplitDefinition.exact(amounts: [a: usd(1)]).participants == [a])
        #expect(SplitDefinition.percentages(basisPoints: [c: 10_000]).participants == [c])
        #expect(SplitDefinition.shares(weights: [a: 1, d: 2]).participants == [a, d])
        #expect(SplitDefinition.adjustments(participants: [a, b], adjustments: [:]).participants == [a, b])
    }
}
