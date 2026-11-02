import SpltCore
import SwiftUI
import Testing
@testable import Splt

@Suite("Split bar layout and labels")
@MainActor
struct SplitBarPresentationTests {
    private let us = Locale(identifier: "en_US")
    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    private func segment(_ name: String, weight: Int64, cents: Int64? = nil, adjustment: Int64? = nil) -> SplitBarSegment {
        SplitBarSegment(
            person: Person(name: name), weight: weight, amount: cents.map(usd), adjustment: adjustment.map(usd)
        )
    }

    // MARK: Layout

    @Test func widthsFollowTheWeightsAndFillTheBar() {
        let layout = SplitBarLayout.make(weights: [5_000, 3_000, 2_000], scale: 10_000, width: 300)
        #expect(layout.widths == [150, 90, 60])
        #expect(layout.visual.last == 300)
    }

    @Test func tinySegmentsKeepAVisibleMinimum() {
        let layout = SplitBarLayout.make(weights: [4_900, 200, 4_900], scale: 10_000, width: 300, minimum: 28)
        #expect(layout.widths[1] == 28)
        #expect(abs(layout.widths.reduce(0, +) - 300) < 0.001)
        #expect(layout.widths[0] == layout.widths[2])
    }

    @Test func severalTinySegmentsAllKeepTheMinimum() {
        let layout = SplitBarLayout.make(weights: [9_000, 100, 100, 800], scale: 10_000, width: 320, minimum: 28)
        #expect(layout.widths[1] >= 28 && layout.widths[2] >= 28)
        #expect(abs(layout.widths.reduce(0, +) - 320) < 0.001)
    }

    @Test func aCrowdedBarSharesTheWidthEvenly() {
        let layout = SplitBarLayout.make(weights: Array(repeating: 1_000, count: 10), scale: 10_000, width: 200, minimum: 28)
        #expect(layout.widths.allSatisfy { abs($0 - 20) < 0.001 })
    }

    @Test func touchesMapBackToTheRealPosition() {
        let layout = SplitBarLayout.make(weights: [4_900, 200, 4_900], scale: 10_000, width: 300, minimum: 28)
        #expect(layout.fraction(forX: 0) == 0)
        #expect(abs(layout.fraction(forX: 300) - 1) < 0.0001)
        let first = layout.fraction(forX: layout.visual[1])
        #expect(abs(first - 0.49) < 0.0001)
        let second = layout.fraction(forX: layout.visual[2])
        #expect(abs(second - 0.51) < 0.0001)
        #expect(layout.fraction(forX: layout.visual[1] + 14) > first)
    }

    @Test func degenerateInputsAreSafe() {
        #expect(SplitBarLayout.make(weights: [], scale: 0, width: 100).widths.isEmpty)
        let zero = SplitBarLayout.make(weights: [1, 1], scale: 2, width: .nan)
        #expect(zero.widths.allSatisfy { $0 == 0 })
    }

    // MARK: Labels

    @Test func percentSegmentsShowPercentagesWithMoneyUnderneath() {
        let label = SplitBarLabels.make(
            method: .percentage, segment: segment("Maya", weight: 3_334, cents: 2_101), scale: 10_000, wide: true, locale: us
        )
        #expect(label.primary == "33.3%")
        #expect(label.secondary == "$21.01")
    }

    @Test func shareSegmentsShowCountsWithMoneyUnderneath() {
        let wide = SplitBarLabels.make(method: .shares, segment: segment("Maya", weight: 2, cents: 3_000), scale: 4, wide: true, locale: us)
        #expect(wide.primary == "2 shares")
        #expect(wide.secondary == "$30.00")
        let narrow = SplitBarLabels.make(method: .shares, segment: segment("Maya", weight: 2, cents: 3_000), scale: 4, wide: false, locale: us)
        #expect(narrow.primary == "2\u{00D7}")
    }

    @Test func exactSegmentsShowMoneyOnly() {
        let label = SplitBarLabels.make(method: .exact, segment: segment("Maya", weight: 2_500, cents: 2_500), scale: 10_000, wide: true, locale: us)
        #expect(label.primary == "$25.00")
        #expect(label.secondary == nil)
    }

    @Test func equalSegmentsShowMoneyAndTheWordEqual() {
        let label = SplitBarLabels.make(method: .equal, segment: segment("Maya", weight: 3_333, cents: 2_000), scale: 10_000, wide: true, locale: us)
        #expect(label.primary == "$20.00")
        #expect(label.secondary == "equal")
        let narrow = SplitBarLabels.make(method: .equal, segment: segment("Maya", weight: 3_333, cents: 2_000), scale: 10_000, wide: false, locale: us)
        #expect(narrow.secondary == nil)
    }

    @Test func adjustedSegmentsShowTheirAdjustment() {
        let up = SplitBarLabels.make(method: .adjustment, segment: segment("Maya", weight: 1, cents: 2_100, adjustment: 100), scale: 3, wide: true, locale: us)
        #expect(up.primary == "$21.00")
        #expect(up.secondary == "+$1.00")
        let even = SplitBarLabels.make(method: .adjustment, segment: segment("Sam", weight: 1, cents: 2_000, adjustment: 0), scale: 3, wide: true, locale: us)
        #expect(even.secondary == "even")
    }

    @Test func methodsDifferOnTheSameSegment() {
        let seg = segment("Maya", weight: 5_000, cents: 3_000)
        let texts = [SplitMethod.percentage, .exact, .equal].map {
            SplitBarLabels.make(method: $0, segment: seg, scale: 10_000, wide: true, locale: us)
        }
        #expect(Set(texts).count == 3)
    }

    @Test func theModelFillsInAdjustmentCaptions() throws {
        let harness = try ExpenseFormHarness()
        let model = harness.filledDinner()
        model.selectMethod(.adjustment)
        model.dragDivider(0, toFraction: 0.5, thresholdBasisPoints: 10)
        let data = try #require(model.barData)
        #expect(data.segments.allSatisfy { $0.adjustment != nil })
        #expect(data.segments.compactMap(\.adjustment).map(\.minorUnits).reduce(0, +) == 0)
    }

    // MARK: Contrast

    @Test func inkAlwaysPassesOnEveryPersonColor() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for index in 0..<PersonPalette.count {
                let fill = ContrastInk.resolve(PersonPalette.color(at: index), style: style)
                let dark = ContrastInk.prefersDarkInk(on: fill)
                let ratio = ContrastInk.ratio(dark ? ContrastInk.black : ContrastInk.white, fill)
                #expect(ratio >= 4.5, "hue \(index) in \(style.rawValue) only reaches \(ratio)")
            }
        }
    }

    @Test func darkInkOnLightFillsAndWhiteOnDarkOnes() {
        #expect(ContrastInk.prefersDarkInk(on: ContrastInk.RGB(red: 1, green: 0.8, blue: 0.2)))
        #expect(!ContrastInk.prefersDarkInk(on: ContrastInk.RGB(red: 0.1, green: 0.2, blue: 0.6)))
    }

    @Test func contrastRatioMatchesTheKnownExtremes() {
        let ratio = ContrastInk.ratio(ContrastInk.black, ContrastInk.white)
        #expect(abs(ratio - 21) < 0.01)
        #expect(ContrastInk.ratio(ContrastInk.white, ContrastInk.white) == 1)
    }
}
