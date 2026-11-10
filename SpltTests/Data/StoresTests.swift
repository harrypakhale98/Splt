import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Stores")
struct StoresTests {
    /// Waits for a store that refreshes on its own after a save.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test func groupsStoreShowsYourBalanceInEachGroup() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        let store = fixture.services.groupsStore
        store.refresh()
        let summary = try #require(store.summaries.first)
        #expect(summary.group.id == fixture.group.id)
        #expect(summary.memberCount == 3)
        #expect(summary.myBalance == [usdAmount(2000)])
        #expect(!summary.isSettled)
        #expect(summary.lastActivity != nil)
    }

    @Test func groupsStoreKeepsEachGroupsBalanceApart() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        let other = SplitGroup(name: "Trip", currencyCode: "USD", memberIDs: [fixture.me.id, fixture.sam.id])
        try fixture.services.groups.create(other)
        try fixture.services.expenses.add(Expense(
            groupID: other.id, title: "Hotel", total: usdAmount(10_000), date: fixture.clock.start,
            paidBy: fixture.sam.id, split: .equal(participants: [fixture.me.id, fixture.sam.id])
        ))
        let store = fixture.services.groupsStore
        store.refresh()
        #expect(store.summaries.count == 2)
        #expect(Set(store.summaries.map(\.myBalance)) == [[usdAmount(2000)], [usdAmount(-5000)]])
    }

    @Test func groupsStoreRefreshesItselfAfterASave() async throws {
        let fixture = try Fixture()
        let store = fixture.services.groupsStore
        store.refresh()
        #expect(store.summaries.first?.isSettled == true)
        try fixture.addExpense(cents: 3000)
        #expect(await eventually { store.summaries.first?.isSettled == false })
    }

    @Test func emptyStoresAreCalm() throws {
        let services = try DataServices.inMemory()
        #expect(services.groupsStore.summaries.isEmpty)
        #expect(services.friendsStore.summaries.isEmpty)
    }

    @Test func friendsStoreListsEveryFriendWithTheirBalance() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, paidBy: fixture.sam, splitBetween: [fixture.me.id, fixture.sam.id])
        let store = fixture.services.friendsStore
        store.refresh()
        #expect(store.summaries.map(\.person.name) == ["Priya", "Sam"])
        let sam = try #require(store.summaries.first { $0.person.id == fixture.sam.id })
        #expect(sam.balance == [usdAmount(-1500)])
        #expect(sam.byGroup.map(\.groupID) == [fixture.group.id])
        let priya = try #require(store.summaries.first { $0.person.id == fixture.priya.id })
        #expect(priya.isSettled)
        #expect(store.summaries.filter { !$0.isSettled }.map(\.id) == [fixture.sam.id])
        #expect(store.totals == BalanceTotals(owedToYou: [], youOwe: [usdAmount(1500)]))
    }

    @Test func friendsStoreTotalsKeepCurrenciesApart() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        try fixture.services.expenses.add(Expense(
            groupID: fixture.group.id, title: "Cafe", total: Money(minorUnits: 600, currencyCode: "EUR"),
            date: fixture.clock.start, paidBy: fixture.sam.id, split: .equal(participants: [fixture.me.id, fixture.sam.id])
        ))
        let store = fixture.services.friendsStore
        store.refresh()
        #expect(store.totals.owedToYou == [usdAmount(1500)])
        #expect(store.totals.youOwe == [Money(minorUnits: 300, currencyCode: "EUR")])
    }

    @Test func friendsStoreRefreshesItselfAfterASave() async throws {
        let fixture = try Fixture()
        let store = fixture.services.friendsStore
        store.refresh()
        try fixture.addExpense(cents: 3000, splitBetween: [fixture.me.id, fixture.sam.id])
        #expect(await eventually { store.summaries.contains { !$0.isSettled } })
    }

    @Test func totalsSplitSignedAmountsPerCurrency() {
        let totals = BalanceTotals(amounts: [
            usdAmount(500), usdAmount(-200), usdAmount(100), Money(minorUnits: -700, currencyCode: "EUR"), usdAmount(0)
        ])
        #expect(totals.owedToYou == [usdAmount(600)])
        #expect(totals.youOwe == [Money(minorUnits: 700, currencyCode: "EUR"), usdAmount(200)])
        #expect(!totals.isSettled)
        #expect(BalanceTotals(amounts: []).isSettled)
    }

    @Test func moneyTotalsDropAmountsThatCancel() {
        #expect(MoneyTotals.sum([usdAmount(500), usdAmount(-500)]).isEmpty)
        #expect(MoneyTotals.sum([usdAmount(500), usdAmount(250)]) == [usdAmount(750)])
    }

    @Test func aTotalCanAlwaysBeNegated() {
        let half = usdAmount(Int64.min / 2)
        #expect(MoneyTotals.sum([half, half]) == [usdAmount(-Int64.max)])
        #expect(MoneyTotals.sum([half, half, half]) == [usdAmount(-Int64.max)])
        #expect(MoneyTotals.sum([usdAmount(Int64.max), usdAmount(1)]) == [usdAmount(Int64.max)])
        #expect(BalanceTotals(amounts: MoneyTotals.sum([half, half])).youOwe == [usdAmount(Int64.max)])
    }
}
