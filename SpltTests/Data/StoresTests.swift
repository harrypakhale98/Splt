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
        #expect(store.totals == BalanceTotals(owedToYou: [usdAmount(2000)], youOwe: []))
    }

    @Test func groupsStoreSeparatesWhatYouOweFromWhatYouAreOwed() throws {
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
        #expect(store.totals.owedToYou == [usdAmount(2000)])
        #expect(store.totals.youOwe == [usdAmount(5000)])
        #expect(store.summaries.count == 2)
    }

    @Test func archivedGroupsStayOutOfTheTotals() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        try fixture.services.groups.setArchived(true, id: fixture.group.id)
        let store = fixture.services.groupsStore
        store.refresh()
        #expect(store.activeSummaries.isEmpty)
        #expect(store.archivedSummaries.count == 1)
        #expect(store.totals.isSettled)
    }

    @Test func groupsStoreRefreshesItselfAfterASave() async throws {
        let fixture = try Fixture()
        let store = fixture.services.groupsStore
        store.refresh()
        #expect(store.totals.isSettled)
        try fixture.addExpense(cents: 3000)
        #expect(await eventually { !store.totals.isSettled })
    }

    @Test func emptyStoresAreCalm() throws {
        let services = try DataServices.inMemory()
        #expect(services.groupsStore.summaries.isEmpty)
        #expect(services.friendsStore.summaries.isEmpty)
        #expect(services.expensesStore.rows.isEmpty)
        #expect(!services.groupsStore.didFailToLoad)
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
        #expect(store.unsettled.map(\.id) == [fixture.sam.id])
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
        #expect(await eventually { !store.unsettled.isEmpty })
    }

    @Test func expensesStoreBuildsRowsForAGroup() throws {
        let fixture = try Fixture()
        let mine = try fixture.addExpense("Mine", cents: 3000)
        let sams = try fixture.addExpense("Sams", cents: 900, paidBy: fixture.sam)
        let store = fixture.services.expensesStore
        store.load(group: fixture.group.id)
        let rows = Dictionary(uniqueKeysWithValues: store.rows.map { ($0.id, $0) })
        #expect(rows[mine.id]?.paidByMe == true)
        #expect(rows[mine.id]?.myNet == usdAmount(2000))
        #expect(rows[mine.id]?.payers.map(\.name) == ["Me"])
        #expect(rows[sams.id]?.paidByMe == false)
        #expect(rows[sams.id]?.myNet == usdAmount(-300))
        #expect(rows[sams.id]?.payers.map(\.name) == ["Sam"])
    }

    @Test func rowsLeaveOutMyNetWhenIAmNotInvolved() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Theirs", paidBy: fixture.sam, splitBetween: [fixture.sam.id, fixture.priya.id])
        let store = fixture.services.expensesStore
        store.load(group: fixture.group.id)
        #expect(store.rows.first { $0.id == expense.id }?.myNet == nil)
    }

    @Test func storeActionsRefreshTheRows() throws {
        let fixture = try Fixture()
        let store = fixture.services.expensesStore
        store.load(group: fixture.group.id)
        var expense = fixture.expense("Lunch", cents: 2000)
        try store.add(expense)
        #expect(store.rows.map(\.expense.title) == ["Lunch"])
        expense.title = "Late lunch"
        try store.update(expense)
        #expect(store.rows.map(\.expense.title) == ["Late lunch"])
        try store.delete(expense.id)
        #expect(store.rows.first?.expense.isDeleted == true)
        try store.restore(expense.id)
        #expect(store.rows.first?.expense.isDeleted == false)
    }

    @Test func expensesStoreCanShowAFriendship() throws {
        let fixture = try Fixture()
        let withSam = try fixture.addExpense("With Sam", splitBetween: [fixture.me.id, fixture.sam.id])
        try fixture.addExpense("Without Sam", splitBetween: [fixture.me.id, fixture.priya.id])
        let store = fixture.services.expensesStore
        store.load(friend: fixture.sam.id)
        #expect(store.rows.map(\.id) == [withSam.id])
        #expect(store.scope == .friend(fixture.sam.id))
    }

    @Test func expensesStoreWarnsAboutDuplicates() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", cents: 4200)
        let store = fixture.services.expensesStore
        #expect(store.possibleDuplicates(of: fixture.expense("Dinner", cents: 4200)).count == 1)
        #expect(store.possibleDuplicates(of: fixture.expense("Dinner", cents: 4300)).isEmpty)
    }

    @Test func expensesStoreRefreshesItselfAfterASave() async throws {
        let fixture = try Fixture()
        let store = fixture.services.expensesStore
        store.load(group: fixture.group.id)
        try fixture.addExpense("Late arrival")
        #expect(await eventually { store.rows.count == 1 })
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

    @Test func totalsCanBeConvertedToOneCurrency() throws {
        let totals = BalanceTotals(amounts: [usdAmount(1000), Money(minorUnits: -900, currencyCode: "EUR")])
        let rates = ExchangeRates(baseCurrency: "USD", rates: ["EUR": Decimal(string: "0.9")!])
        let converted = try #require(totals.converted(to: "USD", rates: rates))
        #expect(converted.owedToYou == usdAmount(1000))
        #expect(converted.youOwe == usdAmount(1000))
        let missing = ExchangeRates(baseCurrency: "USD", rates: [:])
        #expect(totals.converted(to: "USD", rates: missing) == nil)
    }

    @Test func moneyTotalsDropAmountsThatCancel() {
        #expect(MoneyTotals.sum([usdAmount(500), usdAmount(-500)]).isEmpty)
        #expect(MoneyTotals.sum([usdAmount(500), usdAmount(250)]) == [usdAmount(750)])
    }
}
