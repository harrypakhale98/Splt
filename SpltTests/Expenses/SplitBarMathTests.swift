import SpltCore
import Testing
@testable import Splt

@Suite("Split bar math")
struct SplitBarMathTests {
    private let scale = SplitBarMath.basisPoints

    private func drag(
        _ divider: Int, to raw: Int64, _ weights: [Int64], snaps: Bool = true, threshold: Int64 = 100,
        freeStep: Int64 = 100, count: Int? = nil
    ) -> SplitBarDrag {
        let n = count ?? weights.count
        let prefix = weights[..<divider].reduce(0, +)
        let detents = snaps
            ? SplitBarMath.detents(divider: divider, count: n, scale: scale, prefix: prefix, threshold: threshold)
            : []
        return SplitBarMath.drag(
            divider: divider, to: raw, weights: weights, detents: detents, freeStep: freeStep,
            minimum: SplitBarMath.minimumSegment(count: n, scale: scale), threshold: threshold
        )
    }

    @Test func equalWeightsAddUpAndFavourTheFirstSegments() {
        #expect(SplitBarMath.equalWeights(count: 3, scale: 10_000) == [3334, 3333, 3333])
        #expect(SplitBarMath.equalWeights(count: 4, scale: 10_000) == [2500, 2500, 2500, 2500])
        #expect(SplitBarMath.equalWeights(count: 0, scale: 10_000).isEmpty)
    }

    @Test func equalBoundariesAreTheDividerPositions() {
        #expect(SplitBarMath.equalBoundaries(count: 4, scale: 10_000) == [2500, 5000, 7500])
        #expect(SplitBarMath.equalBoundaries(count: 1, scale: 10_000).isEmpty)
    }

    @Test func scalingKeepsProportionsAndTheSum() {
        let scaled = SplitBarMath.scaled([1, 2, 1], to: 10_000)
        #expect(scaled == [2500, 5000, 2500])
        let odd = SplitBarMath.scaled([1, 1, 1], to: 100)
        #expect(odd.reduce(0, +) == 100)
        #expect(SplitBarMath.scaled([0, 0], to: 100) == [50, 50])
    }

    @Test func minimumSegmentShrinksForCrowdedBars() {
        #expect(SplitBarMath.minimumSegment(count: 3, scale: 10_000) == 300)
        let crowded = SplitBarMath.minimumSegment(count: 40, scale: 10_000)
        #expect(crowded > 0 && crowded * 40 <= 10_000)
    }

    @Test func draggingMovesMoneyBetweenNeighboursOnly() {
        let result = drag(0, to: 4_000, [3_334, 3_333, 3_333], snaps: false)
        #expect(result.weights == [4_000, 2_667, 3_333])
        #expect(result.weights.reduce(0, +) == 10_000)
        #expect(result.didChange)
        #expect(result.snappedTo == nil)
    }

    @Test func dragsSnapToTheEqualSplit() {
        let start: [Int64] = [4_000, 2_667, 3_333]
        let result = drag(0, to: 3_380, start)
        #expect(result.snappedTo == .equal)
        #expect(result.weights == [3_334, 3_333, 3_333])
    }

    @Test func dragsSnapToRoundPercentages() {
        let result = drag(0, to: 2_030, [3_334, 3_333, 3_333], freeStep: 1)
        #expect(result.snappedTo == .percent)
        #expect(result.weights[0] == 2_000)
    }

    @Test func freePositionsRoundToTheStep() {
        let result = drag(0, to: 2_742, [5_000, 5_000], snaps: false, freeStep: 100)
        #expect(result.weights == [2_700, 7_300])
    }

    @Test func segmentsNeverShrinkBelowTheMinimum() {
        let result = drag(0, to: 0, [5_000, 5_000], snaps: false)
        #expect(result.weights[0] == 300)
        let far = drag(0, to: 10_000, [5_000, 5_000], snaps: false)
        #expect(far.weights[1] == 300)
    }

    @Test func draggingTheLastDividerOnlyTouchesTheLastTwo() {
        let result = drag(1, to: 8_000, [2_500, 2_500, 5_000], snaps: false)
        #expect(result.weights == [2_500, 5_500, 2_000])
    }

    @Test func badIndexChangesNothing() {
        let result = SplitBarMath.drag(
            divider: 5, to: 1_000, weights: [5_000, 5_000], detents: [], freeStep: 100, minimum: 300, threshold: 100
        )
        #expect(!result.didChange)
    }

    @Test func wholeAmountsAreDetentsInAMinorUnitBar() {
        // 60.00 split in two: the divider clicks on each whole dollar
        let total: Int64 = 6_000
        let weights: [Int64] = [3_000, 3_000]
        let detents = SplitBarMath.detents(
            divider: 0, count: 2, scale: total, prefix: 0, totalMinor: total, unitMinor: 100,
            spaceIsMinorUnits: true, percentStep: 0, threshold: 60
        )
        let result = SplitBarMath.drag(
            divider: 0, to: 2_240, weights: weights, detents: detents, freeStep: 1,
            minimum: SplitBarMath.minimumSegment(count: 2, scale: total), threshold: 60
        )
        #expect(result.snappedTo == .wholeAmount)
        #expect(result.weights[0] % 100 == 0)
        #expect(result.weights.reduce(0, +) == total)
    }

    @Test func amountsAlwaysAddUpToTheTotal() {
        let total = Money(minorUnits: 10_001, currencyCode: "USD")
        let amounts = SplitBarMath.amounts(for: [3_334, 3_333, 3_333], total: total)
        #expect(amounts.map(\.minorUnits).reduce(0, +) == 10_001)
        let refund = Money(minorUnits: -999, currencyCode: "USD")
        #expect(SplitBarMath.amounts(for: [1, 1, 1], total: refund).map(\.minorUnits).reduce(0, +) == -999)
    }

    @Test func adjustmentsReproduceTheSharesOnAnEqualBase() {
        let shares: [Int64] = [4_000, 3_500, 2_501]
        let adjustments = SplitBarMath.adjustments(for: shares)
        #expect(adjustments.reduce(0, +) == 0)
        let equal = SplitBarMath.equalWeights(count: 3, scale: shares.reduce(0, +))
        #expect(zip(adjustments, equal).map { $0 + $1 } == shares)
    }

    @Test func nudgeMovesOneStepToTheNeighbour() {
        #expect(SplitBarMath.nudge(index: 0, by: 100, weights: [5_000, 5_000], minimum: 300) == [5_100, 4_900])
        #expect(SplitBarMath.nudge(index: 1, by: 100, weights: [5_000, 5_000], minimum: 300) == [4_900, 5_100])
        #expect(SplitBarMath.nudge(index: 0, by: -100, weights: [5_000, 5_000], minimum: 300) == [4_900, 5_100])
        #expect(SplitBarMath.nudge(index: 0, by: 9_000, weights: [5_000, 5_000], minimum: 300) == [9_700, 300])
    }

    @Test func sharesStayWholeNumbers() {
        let result = SplitBarMath.dragShares(divider: 0, toFraction: 0.5, weights: [1, 1, 1])
        #expect(result.weights.allSatisfy { $0 >= 1 })
        #expect(result.weights.count == 3)
        let ratio = Double(result.weights[0]) / Double(result.weights.reduce(0, +))
        #expect(ratio > 0.4 && ratio < 0.6)
    }

    @Test func sharesReduceBackToSmallNumbers() {
        let result = SplitBarMath.dragShares(divider: 0, toFraction: 0.5, weights: [2, 2])
        #expect(result.weights == [1, 1] || result.weights == [2, 2])
        let same = SplitBarMath.dragShares(divider: 0, toFraction: 0.5, weights: [1, 1])
        #expect(same.weights == [1, 1])
        #expect(!same.didChange)
    }
}
