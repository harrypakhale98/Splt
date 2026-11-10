import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Groups list")
struct GroupsListViewModelTests {
    @Test func showsYourBalanceInEachGroup() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        let model = GroupsListViewModel(services: fixture.services, leftGroups: isolatedLeftGroups())

        let summary = try #require(model.active.first)
        #expect(summary.group.id == fixture.group.id)
        #expect(summary.memberCount == 3)
        let lines = BalanceLine.lines(for: summary.myBalance)
        #expect(lines.map(\.money) == [usdAmount(2000)])
        #expect(lines.map(\.direction) == [.owed])
        #expect(model.totals.owedToYou == [usdAmount(2000)])
        #expect(model.totals.youOwe.isEmpty)
    }

    @Test func showsWhatYouOweAsNegative() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, paidBy: fixture.sam)
        let model = GroupsListViewModel(services: fixture.services, leftGroups: isolatedLeftGroups())

        let summary = try #require(model.active.first)
        #expect(BalanceLine.lines(for: summary.myBalance).map(\.direction) == [.owes])
        #expect(model.totals.youOwe == [usdAmount(1000)])
    }

    @Test func aSettledGroupHasNoBalanceLines() throws {
        let fixture = try Fixture()
        let model = GroupsListViewModel(services: fixture.services, leftGroups: isolatedLeftGroups())
        let summary = try #require(model.active.first)
        #expect(BalanceLine.lines(for: summary.myBalance).isEmpty)
        #expect(model.totals.isSettled)
    }

    @Test func noGroupsMeansNoRows() throws {
        let services = try DataServices.inMemory()
        let model = GroupsListViewModel(services: services, leftGroups: isolatedLeftGroups())
        #expect(!model.hasGroups)
        #expect(model.active.isEmpty)
        #expect(model.archived.isEmpty)
    }

    @Test func hidesTheTwoPersonGroupsBehindFriends() throws {
        let fixture = try Fixture()
        let hidden = SplitGroup(
            name: "Sam", currencyCode: "USD", kind: .friend, memberIDs: [fixture.me.id, fixture.sam.id]
        )
        try fixture.services.groups.create(hidden)
        let model = GroupsListViewModel(services: fixture.services, leftGroups: isolatedLeftGroups())
        #expect(model.active.map(\.group.id) == [fixture.group.id])
    }

    @Test func hidesGroupsYouLeftAndShowsThemAgainIfRestored() throws {
        let fixture = try Fixture()
        let left = isolatedLeftGroups()
        let model = GroupsListViewModel(services: fixture.services, leftGroups: left)
        #expect(model.active.count == 1)

        left.insert(fixture.group.id)
        #expect(model.active.isEmpty)
        #expect(!model.hasGroups)

        left.remove(fixture.group.id)
        #expect(model.active.count == 1)
    }

    @Test func searchMatchesNamesAndKeepsTotalsStable() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        let trip = SplitGroup(name: "Lisbon Trip", currencyCode: "USD", memberIDs: [fixture.me.id, fixture.sam.id])
        try fixture.services.groups.create(trip)
        let model = GroupsListViewModel(services: fixture.services, leftGroups: isolatedLeftGroups())
        #expect(model.active.count == 2)

        model.query = "lisb"
        #expect(model.isSearching)
        #expect(model.active.map(\.group.id) == [trip.id])
        #expect(model.totals.owedToYou == [usdAmount(2000)])

        model.query = "nothing like this"
        #expect(!model.hasResults)
    }

    @Test func archiveMovesAGroupToTheArchivedSectionAndRestoreBringsItBack() throws {
        let fixture = try Fixture()
        let model = GroupsListViewModel(services: fixture.services, leftGroups: isolatedLeftGroups())

        model.archive(fixture.group.id)
        #expect(model.active.isEmpty)
        #expect(model.archived.map(\.group.id) == [fixture.group.id])

        model.restore(fixture.group.id)
        #expect(model.archived.isEmpty)
        #expect(model.active.map(\.group.id) == [fixture.group.id])
    }

    @Test func archivedGroupsStillCountInTheTotalsAsTheyDoForFriends() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        let model = GroupsListViewModel(services: fixture.services, leftGroups: isolatedLeftGroups())
        model.archive(fixture.group.id)
        #expect(model.archived.map(\.group.id) == [fixture.group.id])
        #expect(model.totals.owedToYou == [usdAmount(2000)])
        #expect(model.totals.youOwe.isEmpty)
        fixture.services.friendsStore.refresh()
        #expect(fixture.services.friendsStore.totals == model.totals)
    }

    @Test func deleteRemovesTheGroup() throws {
        let fixture = try Fixture()
        let model = GroupsListViewModel(services: fixture.services, leftGroups: isolatedLeftGroups())
        model.delete(fixture.group.id)
        #expect(!model.hasGroups)
        #expect(model.errorMessage == nil)
    }
}

@Suite("Balance presentation")
struct BalancePresentationTests {
    @Test func directionFollowsTheSign() {
        #expect(BalanceDirection(usdAmount(5)) == .owed)
        #expect(BalanceDirection(usdAmount(-5)) == .owes)
        #expect(BalanceDirection(usdAmount(0)) == .settled)
    }

    @Test func linesDropZerosAndSortByCurrency() {
        let eur = Money(minorUnits: -250, currencyCode: "EUR")
        let lines = BalanceLine.lines(for: [usdAmount(100), usdAmount(0), eur])
        #expect(lines.map(\.id) == ["EUR", "USD"])
        #expect(lines.map(\.direction) == [.owes, .owed])
    }

    @Test func nothingMeansSettled() {
        #expect(BalanceLine.lines(for: []).isEmpty)
    }
}
