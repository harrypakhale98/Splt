import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Friends view model")
struct FriendsViewModelTests {
    private func model(_ fixture: Fixture) -> FriendsViewModel {
        FriendsViewModel(services: fixture.services, visibility: FriendVisibilityStore(defaults: isolatedDefaults()))
    }

    @Test func sectionsFollowTheBalances() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        try fixture.addExpense("Taxi", cents: 1200, paidBy: fixture.sam, splitBetween: [fixture.sam.id, fixture.priya.id])
        fixture.services.friendsStore.refresh()
        let model = model(fixture)
        let sections = model.sections
        #expect(sections.owesYou.map(\.person.name) == ["Priya", "Sam"])
        #expect(sections.youOwe.isEmpty)
        #expect(model.totals.owedToYou == [usdAmount(2000)])
    }

    @Test func aFriendWhoOwesYouAndIsOwedShowsBothWays() throws {
        let fixture = try Fixture()
        let other = SplitGroup(name: "Trip", currencyCode: "EUR", memberIDs: [fixture.me.id, fixture.sam.id])
        try fixture.services.groups.create(other)
        try fixture.addExpense("Dinner", cents: 3000)
        try fixture.services.expenses.add(Expense(
            groupID: other.id, title: "Hotel", total: Money(minorUnits: 4000, currencyCode: "EUR"), date: fixture.clock.start,
            paidBy: fixture.sam.id, split: .equal(participants: [fixture.me.id, fixture.sam.id])
        ))
        fixture.services.friendsStore.refresh()
        let sections = model(fixture).sections
        #expect(sections.mixed.map(\.person.name) == ["Sam"])
        #expect(sections.owesYou.map(\.person.name) == ["Priya"])
    }

    @Test func hidingAFriendRemovesThemFromTheSectionsUntilShown() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 3000)
        fixture.services.friendsStore.refresh()
        let model = model(fixture)
        model.setState(.hidden, for: fixture.sam.id)
        #expect(model.sections.owesYou.map(\.person.name) == ["Priya"])
        #expect(model.hiddenSummaries.map(\.person.name) == ["Sam"])
        #expect(model.state(of: fixture.sam.id) == .hidden)
        model.setState(nil, for: fixture.sam.id)
        #expect(model.sections.owesYou.count == 2)
        #expect(model.hiddenSummaries.isEmpty)
    }

    @Test func searchNarrowsTheSections() throws {
        let fixture = try Fixture()
        fixture.services.friendsStore.refresh()
        let model = model(fixture)
        model.query = "sa"
        #expect(model.sections.settled.map(\.person.name) == ["Sam"])
        model.query = "nobody"
        #expect(model.sections.isEmpty)
        #expect(!model.hasNoFriends)
    }

    @Test func noFriendsMeansTheEmptyState() throws {
        let services = try DataServices.inMemory()
        let model = FriendsViewModel(services: services, visibility: FriendVisibilityStore(defaults: isolatedDefaults()))
        #expect(model.hasNoFriends)
        #expect(model.sections.isEmpty)
    }

    @Test func settleRequestHasOneLegPerGroupAndCurrency() throws {
        let fixture = try Fixture()
        let trip = SplitGroup(name: "Trip", currencyCode: "EUR", memberIDs: [fixture.me.id, fixture.sam.id])
        try fixture.services.groups.create(trip)
        try fixture.addExpense("Dinner", cents: 3000)
        try fixture.services.expenses.add(Expense(
            groupID: trip.id, title: "Hotel", total: Money(minorUnits: 4000, currencyCode: "EUR"), date: fixture.clock.start,
            paidBy: fixture.sam.id, split: .equal(participants: [fixture.me.id, fixture.sam.id])
        ))
        fixture.services.friendsStore.refresh()
        let model = model(fixture)
        let summary = try #require(model.summaries.first { $0.person.id == fixture.sam.id })
        let request = try #require(model.settleRequest(for: summary))
        #expect(request.legs.count == 2)
        let flat = try #require(request.legs.first { $0.groupID == fixture.group.id })
        #expect(flat.debt == Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usdAmount(1000)))
        #expect(!flat.youOwe)
        let hotel = try #require(request.legs.first { $0.groupID == trip.id })
        #expect(hotel.debt.debtor == fixture.me.id)
        #expect(hotel.youOwe)
        #expect(hotel.route.debts == [hotel.debt])
    }

    @Test func nothingToSettleGivesNoRequest() throws {
        let fixture = try Fixture()
        fixture.services.friendsStore.refresh()
        let model = model(fixture)
        let summary = try #require(model.summaries.first)
        #expect(model.settleRequest(for: summary) == nil)
    }

    @Test func directGroupsAreLabelledAsDirectExpenses() {
        let direct = SplitGroup(name: "Sam", currencyCode: "USD", kind: .friend)
        let trip = SplitGroup(name: "Trip", currencyCode: "USD")
        #expect(SettleLeg.displayName(of: direct) == "Direct expenses")
        #expect(SettleLeg.displayName(of: trip) == "Trip")
    }
}
