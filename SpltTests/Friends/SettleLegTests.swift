import SpltCore
import Testing
@testable import Splt

@Suite("Settle legs")
struct SettleLegTests {
    private let me = PersonID()
    private let sam = PersonID()
    private let flat = SplitGroup(name: "Flat", currencyCode: "USD")
    private let direct = SplitGroup(name: "Sam", currencyCode: "USD", kind: .friend)

    private func legs(_ amounts: [GroupAmounts]) -> [SettleLeg] {
        SettleLeg.make(from: amounts, friend: sam, me: me, groups: [flat.id: flat, direct.id: direct])
    }

    @Test func positiveAmountsAreOwedToYou() throws {
        let legs = legs([GroupAmounts(groupID: flat.id, amounts: [usdAmount(1500)])])
        let leg = try #require(legs.first)
        #expect(leg.debt == Debt(debtor: sam, creditor: me, amount: usdAmount(1500)))
        #expect(!leg.youOwe)
        #expect(leg.groupName == "Flat")
    }

    @Test func negativeAmountsAreOwedByYou() throws {
        let legs = legs([GroupAmounts(groupID: flat.id, amounts: [usdAmount(-900)])])
        let leg = try #require(legs.first)
        #expect(leg.debt == Debt(debtor: me, creditor: sam, amount: usdAmount(900)))
        #expect(leg.youOwe)
    }

    @Test func eachCurrencyInAGroupIsItsOwnLeg() {
        let euros = Money(minorUnits: 2000, currencyCode: "EUR")
        let legs = legs([GroupAmounts(groupID: flat.id, amounts: [usdAmount(500), euros])])
        #expect(legs.count == 2)
        #expect(Set(legs.map(\.id)).count == 2)
    }

    @Test func zeroAmountsAndUnknownGroupsAreHandled() {
        let legs = legs([
            GroupAmounts(groupID: flat.id, amounts: [usdAmount(0)]),
            GroupAmounts(groupID: GroupID(), amounts: [usdAmount(100)]),
            GroupAmounts(groupID: direct.id, amounts: [usdAmount(100)])
        ])
        #expect(legs.map(\.groupName) == ["Group", "Direct expenses"])
    }

    @Test func aLegBuildsASettleRoute() throws {
        let leg = try #require(legs([GroupAmounts(groupID: flat.id, amounts: [usdAmount(500)])]).first)
        #expect(leg.route.groupID == flat.id)
        #expect(leg.route.debts == [leg.debt])
    }
}

@MainActor
@Suite("Direct group")
struct DirectGroupResolverTests {
    @Test func createsTheGroupOnceAndReusesIt() throws {
        let fixture = try Fixture()
        let first = try DirectGroupResolver.group(with: fixture.sam.id, services: fixture.services, currencyCode: "EUR")
        let second = try DirectGroupResolver.group(with: fixture.sam.id, services: fixture.services, currencyCode: "EUR")
        #expect(first == second)
        let group = try #require(try fixture.services.groups.group(id: first))
        #expect(group.currencyCode == "EUR")
        #expect(group.kind == .friend)
        let other = try DirectGroupResolver.group(with: fixture.priya.id, services: fixture.services, currencyCode: "EUR")
        #expect(other != first)
    }

    @Test func createsYourProfileWhenItIsMissing() throws {
        let services = try DataServices.inMemory()
        let friend = Person(name: "Sam")
        try services.people.add(friend)
        let id = try DirectGroupResolver.group(with: friend.id, services: services, currencyCode: "USD")
        #expect(try services.people.me() != nil)
        #expect(try services.groups.group(id: id)?.memberIDs.count == 2)
    }

    @Test func theHiddenGroupStaysOutOfTheGroupsList() throws {
        let fixture = try Fixture()
        _ = try DirectGroupResolver.group(with: fixture.sam.id, services: fixture.services)
        let visible = try fixture.services.groups.groups(includeArchived: false).filter { $0.kind != .friend }
        #expect(visible.map(\.name) == ["Flat"])
    }
}

@Suite("Duplicate finder")
struct DuplicateFinderTests {
    @Test func suggestsNamesThatLookAlike() {
        let sam = Person(name: "Sam", kind: .placeholder)
        let samuel = Person(name: "Samuel Reed")
        let samRivera = Person(name: "Sam Rivera")
        let maya = Person(name: "Maya Chen")
        let found = DuplicateFinder.candidates(for: sam, among: [maya, samuel, samRivera, sam])
        #expect(found.map(\.name) == ["Sam Rivera", "Samuel Reed"])
        #expect(!found.contains(maya))
        #expect(!found.contains(sam))
    }

    @Test func exactNamesComeFirstIgnoringCaseAndAccents() {
        let jose = Person(name: "jose", kind: .placeholder)
        let found = DuplicateFinder.candidates(for: jose, among: [Person(name: "Jose Alvarez"), Person(name: "José")])
        #expect(found.first?.name == "José")
        #expect(found.count == 2)
    }

    @Test func tolleratesATypo() {
        let found = DuplicateFinder.candidates(for: Person(name: "Priyaa", kind: .placeholder), among: [Person(name: "Priya Nair")])
        #expect(found.map(\.name) == ["Priya Nair"])
    }

    @Test func ignoresYouAndEmptyNames() {
        let me = Person(name: "Sam", kind: .me)
        #expect(DuplicateFinder.candidates(for: Person(name: "Sam", kind: .placeholder), among: [me]).isEmpty)
        #expect(DuplicateFinder.candidates(for: Person(name: "  ", kind: .placeholder), among: [Person(name: "Sam")]).isEmpty)
    }
}
