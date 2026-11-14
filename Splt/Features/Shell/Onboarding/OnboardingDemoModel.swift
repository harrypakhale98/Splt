import Foundation
import Observation
import SpltCore

/// The welcome tour's sample dinner: the real Split Bar on a bill that is never saved.
///
/// It moves exactly like the bar in the expense form. It starts as an equal split, the first drag or
/// step turns it into percentages, and every drag goes through `SplitBarMath.dragDivider`, so the
/// detents, the minimum and the 1 percent steps are the ones people meet on their first real expense.
@MainActor
@Observable
final class OnboardingDemoModel {
    /// The friend in the sample. Sam is the app's example name, and the bar shows only a first word.
    static let friendName = String(localized: "Sam", comment: "The friend in the welcome tour's sample dinner")
    /// Cobalt: far from your pine, and from the red and green that mean money owed.
    static let friendHue = 7

    private(set) var me: Person
    let friend: Person
    /// The currency the sample is in: the default currency chosen on the page before.
    var currencyCode: String
    private(set) var method: SplitMethod = .equal
    /// Each person's part in basis points, once a drag has left the equal split.
    private(set) var basisPoints: [Int64] = SplitBarMath.equalWeights(count: 2, scale: SplitBarMath.basisPoints)

    init(currencyCode: String, myName: String) {
        self.currencyCode = currencyCode
        me = Person(name: myName, kind: .me, avatarSeed: 0)
        friend = Person(name: Self.friendName, kind: .placeholder, avatarSeed: 0)
    }

    /// Your name as typed on the page before. The bar says "You"; the list's avatar shows your initials.
    var myName: String {
        get { me.name }
        set { me.name = newValue }
    }

    /// Fixed hues, because neither person is in the color book: you in your own hue, Sam in cobalt.
    var hues: [PersonID: Int] {
        [me.id: PersonPalette.meIndex, friend.id: Self.friendHue]
    }

    /// The sample bill: a plain dinner for two where the currency is spent.
    var total: Money {
        Money(minorUnits: Self.sampleUnits(for: currencyCode) * Currency.minorUnitScale(for: currencyCode), currencyCode: currencyCode)
    }

    /// Whole units for the sample, in steps of 20 so every 5 percent detent lands on a whole amount.
    static func sampleUnits(for currencyCode: String) -> Int64 {
        switch currencyCode.uppercased() {
        case "GBP": 100
        case "INR": 1_200
        case "JPY": 12_000
        case "KRW": 120_000
        case "IDR": 600_000
        case "VND": 1_200_000
        case "KWD", "BHD", "OMR", "JOD": 40
        default: 120
        }
    }

    private var weights: [Int64] {
        method == .equal ? SplitBarMath.equalWeights(count: 2, scale: SplitBarMath.basisPoints) : basisPoints
    }

    /// What each person pays, from the calculator that saves real expenses, so cents fall the same way.
    var shares: [Money] {
        let people = [me.id, friend.id]
        let definition: SplitDefinition = method == .equal
            ? .equal(participants: Set(people))
            : .percentages(basisPoints: Dictionary(uniqueKeysWithValues: zip(people, basisPoints)))
        guard let result = try? SplitCalculator.calculate(definition, total: total) else {
            return SplitBarMath.amounts(for: weights, total: total)
        }
        return people.map { result.share(for: $0) }
    }

    /// Sam's part of the bill, the line under the bar.
    var friendShare: Money { shares[1] }

    var barData: SplitBarData {
        let amounts = shares
        let segments = zip([me, friend], weights).enumerated().map { index, pair in
            SplitBarSegment(person: pair.0, weight: pair.1, amount: amounts[index])
        }
        return SplitBarData(method: method, segments: segments, scale: SplitBarMath.basisPoints, total: total, canDrag: true)
    }

    /// What one VoiceOver step changes, as in the form once the split is in percentages.
    var stepDescription: String { String(localized: "One percent") }

    // MARK: Changing the split

    /// Moves the divider to `fraction` of the bar, as the form does for a percentage split.
    @discardableResult
    func drag(_ divider: Int, toFraction fraction: Double) -> SplitBarDrag {
        leaveEqualSplit()
        let result = SplitBarMath.dragDivider(
            divider, toFraction: fraction, weights: basisPoints, scale: SplitBarMath.basisPoints,
            freeStep: 100, thresholdBasisPoints: 150
        )
        if result.didChange { basisPoints = result.weights }
        return result
    }

    /// One percent more or less for `person`, for VoiceOver and the list's buttons.
    func step(_ person: PersonID, increase: Bool) {
        guard let index = [me.id, friend.id].firstIndex(of: person) else { return }
        leaveEqualSplit()
        basisPoints = SplitBarMath.nudge(
            index: index, by: increase ? 100 : -100, weights: basisPoints,
            minimum: SplitBarMath.minimumSegment(count: 2, scale: SplitBarMath.basisPoints)
        )
    }

    /// Leaving an equal split turns it into percentages, keeping the bar's shape, as in the form.
    private func leaveEqualSplit() {
        guard method == .equal else { return }
        basisPoints = SplitBarMath.equalWeights(count: 2, scale: SplitBarMath.basisPoints)
        method = .percentage
    }
}
