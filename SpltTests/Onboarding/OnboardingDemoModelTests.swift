import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Welcome tour sample split")
@MainActor
struct OnboardingDemoModelTests {
    private func model(_ currency: String = "USD") -> OnboardingDemoModel {
        OnboardingDemoModel(currencyCode: currency, myName: "Priya")
    }

    @Test func itStartsAsAnEqualSplitOfADinner() {
        let demo = model("INR")
        #expect(demo.method == .equal)
        #expect(demo.total == Money(minorUnits: 120_000, currencyCode: "INR"))
        #expect(demo.shares.map(\.minorUnits) == [60_000, 60_000])
        #expect(demo.barData.weights == [5_000, 5_000])
        #expect(demo.barData.canDrag)
    }

    @Test func theSampleFitsTheCurrency() {
        #expect(model("USD").total.minorUnits == 12_000)
        #expect(model("GBP").total.minorUnits == 10_000)
        #expect(model("JPY").total.minorUnits == 12_000)
        #expect(model("KWD").total.minorUnits == 40_000)
        #expect(model("VND").total.minorUnits == 1_200_000)
        #expect(model("CHF").total.minorUnits == 12_000)
    }

    @Test(arguments: ["USD", "EUR", "GBP", "INR", "JPY", "KRW", "IDR", "VND", "KWD", "CHF"])
    func everyFivePercentIsAWholeAmount(_ currency: String) {
        let total = model(currency).total.minorUnits
        #expect(total * 500 % SplitBarMath.basisPoints == 0)
        #expect(total * 500 / SplitBarMath.basisPoints % Currency.minorUnitScale(for: currency) == 0)
    }

    @Test func theFirstDragTurnsTheSplitIntoPercentages() {
        let demo = model()
        let result = demo.drag(0, toFraction: 0.5)
        #expect(demo.method == .percentage)
        #expect(result.snappedTo == .equal)
        #expect(demo.barData.weights == [5_000, 5_000])
    }

    @Test func dividersClickIntoRoundPercentages() {
        let demo = model()
        let result = demo.drag(0, toFraction: 0.66)
        #expect(result.snappedTo == .percent)
        #expect(demo.basisPoints == [6_500, 3_500])
        #expect(demo.friendShare == Money(minorUnits: 4_200, currencyCode: "USD"))
    }

    @Test func freeDragsMoveInWholePercents() {
        let demo = model()
        let result = demo.drag(0, toFraction: 0.723)
        #expect(result.snappedTo == nil)
        #expect(demo.basisPoints == [7_200, 2_800])
        #expect(demo.shares.map(\.minorUnits).reduce(0, +) == demo.total.minorUnits)
    }

    @Test func nobodyDropsBelowTheMinimum() {
        let demo = model()
        demo.drag(0, toFraction: 0.01)
        #expect(demo.basisPoints == [300, 9_700])
        demo.drag(0, toFraction: 1)
        #expect(demo.basisPoints == [9_700, 300])
    }

    @Test func aStepMovesOnePercentAndLeavesTheEqualSplit() {
        let demo = model()
        demo.step(demo.friend.id, increase: true)
        #expect(demo.method == .percentage)
        #expect(demo.basisPoints == [4_900, 5_100])
        demo.step(demo.me.id, increase: true)
        #expect(demo.basisPoints == [5_000, 5_000])
    }

    @Test func changingTheCurrencyKeepsTheSplit() {
        let demo = model()
        demo.drag(0, toFraction: 0.7)
        demo.currencyCode = "JPY"
        #expect(demo.basisPoints == [7_000, 3_000])
        #expect(demo.shares.map(\.minorUnits) == [8_400, 3_600])
    }

    @Test func youKeepYourHueAndSamGetsCobalt() {
        let demo = model()
        #expect(demo.hues[demo.me.id] == PersonPalette.meIndex)
        #expect(demo.hues[demo.friend.id] == OnboardingDemoModel.friendHue)
        #expect(OnboardingDemoModel.friendHue != PersonPalette.meIndex)
    }

    @Test func yourNameFollowsWhatYouType() {
        let demo = model()
        demo.myName = "Maya Lin"
        #expect(demo.me.name == "Maya Lin")
        #expect(demo.barData.segments.first?.person.name == "Maya Lin")
    }
}
