import CoreGraphics
import Foundation
import SpltCore
import SwiftUI
import Testing
@testable import Splt

@Suite("Colors within a group")
struct UIGroupColorTests {
    /// People the color book has never seen, so their own hue is the one their id points to.
    private func strangers(_ seeds: ClosedRange<Int>) -> [PersonID] {
        seeds.map { seed in
            PersonID(rawValue: UUID(uuid: (UInt8(seed & 0xFF), UInt8(seed >> 8), 0xC0, 0x10, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)))
        }
    }

    /// Four strangers whose own hues are all the same, and one whose hue is different.
    private func clashingGroup() -> (clashing: [PersonID], other: PersonID) {
        let pool = strangers(0...600)
        let byHue = Dictionary(grouping: pool, by: PersonPalette.preferredIndex(for:))
        let hue = byHue.filter { $0.value.count >= 4 }.keys.min()!
        let clashing = Array(byHue[hue]!.prefix(4))
        let other = pool.first { PersonPalette.preferredIndex(for: $0) != hue }!
        return (clashing, other)
    }

    @Test func fourMembersWhoseHuesCollideGetFourColors() {
        let group = clashingGroup().clashing
        #expect(Set(group.map(PersonPalette.index(for:))).count == 1)
        let hues = PersonPalette.indices(for: group)
        #expect(hues.count == 4)
        #expect(Set(hues.values).count == 4)
    }

    @Test func someoneWhoDoesNotClashKeepsTheirOwnColor() {
        let (clashing, other) = clashingGroup()
        let hues = PersonPalette.indices(for: clashing + [other])
        #expect(hues[other] == PersonPalette.index(for: other))
        // one of the clashing members keeps the shared hue, the others move off it
        #expect(hues.values.filter { $0 == PersonPalette.index(for: clashing[0]) }.count == 1)
        #expect(Set(hues.values).count == 5)
    }

    @Test func theResultIsStableAcrossCallsAndOrderings() {
        let (clashing, other) = clashingGroup()
        let group = clashing + [other]
        let first = PersonPalette.indices(for: group)
        #expect(PersonPalette.indices(for: group) == first)
        #expect(PersonPalette.indices(for: group.reversed()) == first)
        #expect(PersonPalette.indices(for: [group[2], group[4], group[0], group[3], group[1]]) == first)
        #expect(PersonPalette.indices(for: group + group) == first)
    }

    @Test func twelveMembersNeverShareAColor() {
        let group = Array(strangers(0...600).prefix(12))
        #expect(Set(PersonPalette.indices(for: group).values).count == 12)
    }

    @Test func someoneOutsideTheGroupKeepsTheirOwnColor() {
        let (clashing, other) = clashingGroup()
        #expect(PersonPalette.index(for: other, in: clashing) == PersonPalette.index(for: other))
        #expect(PersonPalette.index(for: other, in: []) == PersonPalette.index(for: other))
    }
}

@Suite("Saved person colors")
struct UIStickyColorBookTests {
    private func person(_ seed: UInt8, created: TimeInterval) -> Person {
        Person(
            id: PersonID(rawValue: UUID(uuid: (seed, 0xB0, 9, 9, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12))),
            name: "P\(seed)", createdAt: Date(timeIntervalSince1970: created)
        )
    }

    @Test func someoneAddedWithAnEarlierDateChangesNobody() {
        let people = (1...8).map { person(UInt8($0), created: 100 + Double($0)) }
        let me = people[0].id
        let before = PersonColorBook.assigning(people, me: me, existing: [:])
        let earlier = person(40, created: 1)
        let after = PersonColorBook.assigning(people + [earlier], me: me, existing: before)
        for (id, entry) in before { #expect(after[id] == entry) }
        // the newcomer takes a hue nobody present holds
        #expect(!before.values.map(\.hue).contains(after[earlier.id]?.hue ?? -1))
        // and ranks after everyone already there
        #expect((after[earlier.id]?.rank ?? 0) > before.values.map(\.rank).max()!)
    }

    @Test func removingSomeoneChangesNobody() {
        let people = (1...6).map { person(UInt8($0), created: Double($0)) }
        let before = PersonColorBook.assigning(people, me: people[0].id, existing: [:])
        let after = PersonColorBook.assigning(Array(people.dropFirst(2)), me: people[0].id, existing: before)
        for person in people.dropFirst(2) { #expect(after[person.id] == before[person.id]) }
    }

    @Test func youAlwaysHaveTheBrandHueAndComeFirst() {
        let people = (1...4).map { person(UInt8($0), created: Double($0)) }
        let before = PersonColorBook.assigning(people, me: nil, existing: [:])
        let after = PersonColorBook.assigning(people, me: people[3].id, existing: before)
        #expect(after[people[3].id] == PersonColorBook.Entry(hue: PersonPalette.meIndex, rank: -1))
    }
}

@Suite("Split bar fixes")
@MainActor
struct UISplitBarFixTests {
    @Test func aCrowdedBarStaysToScale() {
        // 12 people on a small phone, one pays 90% and the rest share 10%
        let weights: [Int64] = [9_000] + Array(repeating: 90, count: 10) + [100]
        let layout = SplitBarLayout.make(weights: weights, scale: 10_000, width: 300, minimum: 28)
        #expect(abs(layout.widths.reduce(0, +) - 300) < 0.001)
        #expect(layout.widths[0] > layout.widths[1] * 5)
        #expect(layout.widths.dropFirst().allSatisfy { $0 > 0 })
        #expect(abs(layout.widths[1] - layout.widths[2]) < 0.001)
    }

    @Test func theNearestDividerTakesTheTouch() {
        let positions: [CGFloat] = [100, 104, 200]
        #expect(SplitBarLayout.nearest(to: 103, in: positions) == 1)
        #expect(SplitBarLayout.nearest(to: 101, in: positions) == 0)
        #expect(SplitBarLayout.nearest(to: 170, in: positions) == 2)
        #expect(SplitBarLayout.nearest(to: 10, in: []) == nil)
    }

    @Test func discountsAndRefundsReadAsMinus() {
        let five = Money(minorUnits: 500, currencyCode: "USD")
        let refund = Money(minorUnits: -500, currencyCode: "USD")
        #expect(SignedAmount.isNegative(five, isDeduction: true))
        #expect(!SignedAmount.isNegative(refund, isDeduction: true))
        #expect(SignedAmount.isNegative(refund, isDeduction: false))
        #expect(!SignedAmount.isNegative(five, isDeduction: false))
    }

    @Test func thePaymentIsSpokenWithTheRightVerb() {
        let you = SettleParticipant(id: PersonID(), name: "You", color: .clear, avatarName: "Jonas Reyes")
        let sam = SettleParticipant(id: PersonID(), name: "Sam", color: .clear, avatarName: "Sam")
        let priya = SettleParticipant(id: PersonID(), name: "Priya", color: .clear, avatarName: "Priya")
        #expect(SettleStage.spokenPayment(payer: you, receiver: sam) == "You pay Sam")
        #expect(SettleStage.spokenPayment(payer: sam, receiver: you) == "Sam pays you")
        #expect(SettleStage.spokenPayment(payer: sam, receiver: priya) == "Sam pays Priya")
    }
}
