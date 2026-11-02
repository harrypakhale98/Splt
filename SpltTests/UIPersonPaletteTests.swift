import Foundation
import SpltCore
import SwiftUI
import Testing
@testable import Splt

@Suite("Person palette")
struct UIPersonPaletteTests {
    private func ids(_ count: Int) -> [PersonID] {
        (0..<count).map { PersonID(rawValue: UUID(uuid: (UInt8($0), 7, 7, 7, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12))) }
    }

    @Test func preferredIndexIsStableAndInRange() {
        let person = PersonID(rawValue: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
        #expect(PersonPalette.preferredIndex(for: person) == PersonPalette.preferredIndex(for: person))
        for id in ids(50) { #expect((0..<PersonPalette.count).contains(PersonPalette.preferredIndex(for: id))) }
    }

    @Test func membersOfAGroupNeverShareAColorUpToTwelve() {
        for size in [2, 5, 8, 12] {
            let members = ids(size)
            let hues = PersonPalette.resolve(members).values
            #expect(Set(hues).count == size)
        }
    }

    @Test func moreThanTwelveMembersStillGetAColor() {
        let members = ids(15)
        let assigned = PersonPalette.resolve(members)
        #expect(assigned.count == 15)
        #expect(assigned.values.allSatisfy { (0..<12).contains($0) })
    }

    @Test func theFirstMemberKeepsTheirPreferredHue() {
        let members = ids(6)
        #expect(PersonPalette.resolve(members)[members[0]] == PersonPalette.preferredIndex(for: members[0]))
    }

    @Test func assignmentFollowsTheOrderOfMembers() {
        let members = ids(6)
        #expect(PersonPalette.resolve(members) == PersonPalette.resolve(members))
    }

    @Test func aStrangerFallsBackToTheirPreferredHue() {
        let stranger = ids(1)[0]
        #expect(PersonPalette.index(for: stranger, in: []) == PersonPalette.preferredIndex(for: stranger))
    }

    @Test func duplicateMembersAreCountedOnce() {
        let members = ids(3)
        #expect(PersonPalette.resolve(members + members).count == 3)
    }

    @Test @MainActor func hueLookupWraps() {
        func resolved(_ color: Color) -> UIColor {
            UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        }
        #expect(resolved(PersonPalette.color(at: 12)) == resolved(PersonPalette.color(at: 0)))
        #expect(resolved(PersonPalette.color(at: -1)) == resolved(PersonPalette.color(at: 11)))
        #expect(resolved(PersonPalette.color(at: 0)) != resolved(PersonPalette.color(at: 1)))
    }
}

@Suite("Person color book")
struct UIPersonColorBookTests {
    private func person(_ seed: UInt8, created: TimeInterval) -> Person {
        Person(
            id: PersonID(rawValue: UUID(uuid: (seed, 9, 9, 9, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12))),
            name: "P\(seed)", createdAt: Date(timeIntervalSince1970: created)
        )
    }

    @Test func youGetTheBrandHueAndNobodyElseDoes() {
        let people = (1...8).map { person(UInt8($0), created: Double($0)) }
        let me = people[3].id
        let hues = PersonColorBook.assign(people, me: me)
        #expect(hues[me] == PersonPalette.meIndex)
        #expect(hues.filter { $0.value == PersonPalette.meIndex }.count == 1)
    }

    @Test func everyoneGetsADifferentHueUpToTwelve() {
        let people = (1...12).map { person(UInt8($0), created: Double($0)) }
        let hues = PersonColorBook.assign(people, me: people[0].id)
        #expect(Set(hues.values).count == 12)
    }

    @Test func theResultDoesNotDependOnTheOrderOfTheList() {
        let people = (1...9).map { person(UInt8($0), created: Double($0)) }
        let me = people[0].id
        #expect(PersonColorBook.assign(people, me: me) == PersonColorBook.assign(people.reversed(), me: me))
    }

    @Test func addingSomeoneNeverChangesAnExistingHue() {
        var people = (1...6).map { person(UInt8($0), created: Double($0)) }
        let before = PersonColorBook.assign(people, me: people[0].id)
        people.append(person(7, created: 100))
        let after = PersonColorBook.assign(people, me: people[0].id)
        for (id, hue) in before { #expect(after[id] == hue) }
    }

    @Test func sameCreationTimeBreaksTiesByIdentifier() {
        let people = (1...5).map { person(UInt8($0), created: 50) }
        #expect(PersonColorBook.assign(people, me: nil) == PersonColorBook.assign(people.reversed(), me: nil))
    }
}

@Suite("Person color lookup", .serialized)
@MainActor
struct UIPersonColorLookupTests {
    @Test func theSameColorWhicheverMemberListIsPassed() {
        let people = (1...5).map { Person(id: PersonID(rawValue: UUID(uuid: (UInt8($0), 5, 5, 5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12))), name: "P\($0)") }
        PersonColorBook.update(people: people, me: people[0].id)
        defer { PersonColorBook.reset() }
        let ids = people.map(\.id)
        for id in ids {
            #expect(PersonPalette.index(for: id, in: ids) == PersonPalette.index(for: id))
            #expect(PersonPalette.index(for: id, in: [id]) == PersonPalette.index(for: id))
            #expect(PersonPalette.index(for: id, in: Array(ids.reversed())) == PersonPalette.index(for: id))
        }
        #expect(PersonPalette.index(for: ids[0]) == PersonPalette.meIndex)
    }

    @Test func strangersFallBackToTheirIdentifierHue() {
        let stranger = PersonID()
        #expect(PersonPalette.index(for: stranger) == PersonPalette.preferredIndex(for: stranger))
    }
}

@Suite("Balance tint")
struct UIBalanceTintTests {
    @Test func oneRuleForGreenRedAndQuiet() {
        #expect(MoneyLabel.balanceTint(for: Money(minorUnits: 100, currencyCode: "USD")) == .green)
        #expect(MoneyLabel.balanceTint(for: Money(minorUnits: -100, currencyCode: "USD")) == .red)
        #expect(MoneyLabel.balanceTint(for: Money(minorUnits: 0, currencyCode: "USD")) == .secondary)
    }
}

@Suite("Account summary")
@MainActor
struct UIAccountSummaryTests {
    @Test func theChosenNameWins() {
        let defaults = UserDefaults(suiteName: "splt.tests.summary.\(UUID().uuidString)")!
        let profile = AccountProfile(defaults: defaults, deviceName: "iPhone")
        var summary = AccountSummary()
        summary.meName = "Jonas Reyes"
        #expect(summary.displayName(for: profile) == "Jonas Reyes")
        profile.displayName = "Jo"
        #expect(summary.displayName(for: profile) == "Jo")
    }

    @Test func theStoredNameSetsTheInitialsWhenNoneIsChosen() {
        let defaults = UserDefaults(suiteName: "splt.tests.summary.\(UUID().uuidString)")!
        let profile = AccountProfile(defaults: defaults, deviceName: "iPhone")
        var summary = AccountSummary()
        summary.meName = "Jonas Reyes"
        #expect(AvatarStyle.initials(for: summary.displayName(for: profile)) == "JR")
    }

    @Test func loadingWithoutStorageIsEmpty() {
        #expect(AccountSummary.load(from: nil) == AccountSummary())
    }
}

@Suite("Person color contrast")
struct UIPersonColorContrastTests {
    @Test(arguments: [false, true])
    func textOnEveryHueReaches4Point5(dark: Bool) {
        for index in 0..<PersonPalette.count {
            let pair = PersonPalette.hexPair(at: index, dark: dark)
            let ratio = PersonPalette.contrastRatio(pair.fill, pair.text)
            #expect(ratio >= 4.5, "hue \(index) \(dark ? "dark" : "light") has contrast \(ratio)")
        }
    }

    @Test func contrastRatioMatchesTheDefinition() {
        #expect(abs(PersonPalette.contrastRatio(0xFFFFFF, 0x000000) - 21) < 0.001)
        #expect(abs(PersonPalette.contrastRatio(0x777777, 0x777777) - 1) < 0.001)
    }

    @Test func pickingTheBetterOfBlackAndWhite() {
        #expect(PersonPalette.foregroundHex(onFill: 0xFFFFFF) == 0x0E0E12)
        #expect(PersonPalette.foregroundHex(onFill: 0x101010) == 0xFFFFFF)
    }
}
