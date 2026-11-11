import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Group detail")
struct GroupDetailViewModelTests {
    private func makeModel(
        _ fixture: Fixture, groupID: GroupID? = nil, now: Date = utcDate(2026, 5, 15)
    ) -> GroupDetailViewModel {
        GroupDetailViewModel(
            groupID: groupID ?? fixture.group.id, services: fixture.services,
            now: { now }, calendar: GroupsTestCalendar.utc
        )
    }

    // MARK: Header

    @Test func headerShowsWhatYouAreOwed() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        let model = makeModel(fixture)
        #expect(model.myBalance.map(\.money) == [usdAmount(2000)])
        #expect(model.myTotals.owedToYou == [usdAmount(2000)])
        #expect(model.myTotals.youOwe.isEmpty)
        #expect(!model.isSettled)
    }

    @Test func headerShowsWhatYouOwe() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, paidBy: fixture.sam)
        let model = makeModel(fixture)
        #expect(model.myTotals.youOwe == [usdAmount(1000)])
        #expect(model.myTotals.owedToYou.isEmpty)
    }

    /// Sam owes you 10 and you owe Priya 10. Your net is even, but the group settles pair by pair.
    @Test func pairDebtsShowInTheHeaderWhenTheGroupDoesNotSimplify() throws {
        let fixture = try Fixture(simplifies: false)
        try fixture.addExpense(cents: 1000, splitBetween: [fixture.sam.id])
        try fixture.addExpense(cents: 1000, paidBy: fixture.priya, splitBetween: [fixture.me.id])
        let model = makeModel(fixture)
        #expect(model.myBalance.isEmpty)
        #expect(model.myTotals.owedToYou == [usdAmount(1000)])
        #expect(model.myTotals.youOwe == [usdAmount(1000)])
        #expect(!model.myTotals.isSettled)
        fixture.services.groupsStore.refresh()
        let row = fixture.services.groupsStore.summaries.first { $0.id == fixture.group.id }
        #expect(row?.isSettled == false)
    }

    @Test func aGroupWithoutExpensesIsSettled() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        #expect(model.myBalance.isEmpty)
        #expect(model.myTotals.isSettled)
        #expect(model.isSettled)
        #expect(model.settleRoute() == nil)
    }

    @Test func missingGroupsLoadAsNil() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture, groupID: GroupID())
        #expect(model.group == nil)
        #expect(model.didLoad)
    }

    @Test func youAreNamedYou() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        #expect(model.name(of: fixture.me.id) == "You")
        #expect(model.name(of: fixture.sam.id) == "Sam")
    }

    // MARK: Balances

    private func chain(_ fixture: Fixture) throws {
        try fixture.addExpense("Tickets", cents: 2000, paidBy: fixture.me, splitBetween: [fixture.me.id, fixture.sam.id])
        try fixture.addExpense("Lunch", cents: 2000, paidBy: fixture.sam, splitBetween: [fixture.sam.id, fixture.priya.id])
    }

    @Test func simplifiedListHasTheFewestPayments() throws {
        let fixture = try Fixture(simplifies: true)
        try chain(fixture)
        let model = makeModel(fixture)
        #expect(model.simplifiesDebts)
        #expect(model.transfers == [Debt(debtor: fixture.priya.id, creditor: fixture.me.id, amount: usdAmount(1000))])
    }

    @Test func turningSimplifyOffShowsDirectDebtsAndSavesTheChoice() throws {
        let fixture = try Fixture(simplifies: true)
        try chain(fixture)
        let model = makeModel(fixture)

        model.setSimplifiesDebts(false)
        #expect(!model.simplifiesDebts)
        #expect(Set(model.transfers) == [
            Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usdAmount(1000)),
            Debt(debtor: fixture.priya.id, creditor: fixture.sam.id, amount: usdAmount(1000))
        ])
        #expect(try fixture.services.groups.group(id: fixture.group.id)?.simplifiesDebts == false)

        model.setSimplifiesDebts(true)
        #expect(model.transfers.count == 1)
    }

    @Test func settleRoutesCarryTheDebts() throws {
        let fixture = try Fixture(simplifies: false)
        try chain(fixture)
        let model = makeModel(fixture)
        let all = try #require(model.settleRoute())
        #expect(all.groupID == fixture.group.id)
        #expect(all.debts.count == 2)
        let one = try #require(model.settleRoute(for: model.transfers[0]))
        #expect(one.debts == [model.transfers[0]])
    }

    @Test func netRowsListWhoIsOwedFirst() throws {
        let fixture = try Fixture()
        try chain(fixture)
        let rows = makeModel(fixture).netRows
        #expect(rows.first?.person.id == fixture.me.id)
        #expect(rows.last?.person.id == fixture.priya.id)
        #expect(rows.first(where: { $0.person.id == fixture.sam.id })?.isSettled == true)
    }

    @Test func recordingAPaymentSettlesTheGroup() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000)
        let model = makeModel(fixture)
        let route = try #require(model.settleRoute())
        for debt in route.debts {
            try fixture.services.payments.settle(debt, in: route.groupID, date: utcDate(2026, 5, 15))
        }
        model.refresh()
        #expect(model.isSettled)
        #expect(model.transfers.isEmpty)
    }

    // MARK: Expenses

    @Test func expensesGroupByMonthNewestFirst() throws {
        let fixture = try Fixture()
        _ = try fixture.add("Dinner", cents: 6000, on: utcDate(2026, 5, 10))
        _ = try fixture.add("Museum", cents: 1500, on: utcDate(2026, 5, 2))
        _ = try fixture.add("Taxi", cents: 2000, on: utcDate(2026, 4, 20))
        let model = makeModel(fixture)

        let sections = model.sections
        #expect(sections.map { $0.expenses.map(\.title) } == [["Dinner", "Museum"], ["Taxi"]])
        #expect(model.grouping == .month)
        #expect(sections.map { model.sectionTitle($0, locale: GroupsTestCalendar.english) } == ["May 2026", "April 2026"])
    }

    @Test func tripsGroupByDayWithDayNumbers() throws {
        let fixture = try Fixture()
        let trip = SplitGroup(
            name: "Lisbon", currencyCode: "USD", kind: .trip, memberIDs: [fixture.me.id, fixture.sam.id],
            tripStart: utcDate(2026, 5, 8), tripEnd: utcDate(2026, 5, 12)
        )
        try fixture.services.groups.create(trip)
        _ = try fixture.add("Airbnb", cents: 9000, on: utcDate(2026, 5, 8), in: trip)
        _ = try fixture.add("Coffee", cents: 400, on: utcDate(2026, 5, 8, hour: 18), in: trip)
        _ = try fixture.add("Fado", cents: 5000, on: utcDate(2026, 5, 10), in: trip)
        let model = makeModel(fixture, groupID: trip.id)

        #expect(model.grouping == .day)
        #expect(model.sections.map { $0.expenses.count } == [1, 2])
        let titles = model.sections.map { model.sectionTitle($0, locale: GroupsTestCalendar.english) }
        #expect(titles == ["Day 3, Sun, May 10", "Day 1, Fri, May 8"])
    }

    @Test func deletedExpensesAreHidden() throws {
        let fixture = try Fixture()
        let dinner = try fixture.addExpense("Dinner")
        try fixture.services.expenses.delete(id: dinner.id)
        #expect(makeModel(fixture).expenses.isEmpty)
    }

    // MARK: Filters

    private func filterFixture() throws -> Fixture {
        let fixture = try Fixture()
        _ = try fixture.add("Dinner", cents: 6000, on: utcDate(2026, 5, 10), category: .dining, paidBy: fixture.sam)
        _ = try fixture.add("Museum", cents: 1500, on: utcDate(2026, 5, 2), category: .entertainment, paidBy: fixture.priya)
        _ = try fixture.add("Taxi", cents: 2000, on: utcDate(2026, 4, 20), category: .transport)
        return fixture
    }

    @Test func filtersByPayer() throws {
        let fixture = try filterFixture()
        let model = makeModel(fixture)
        model.filter.payer = fixture.sam.id
        #expect(model.visibleExpenses.map(\.title) == ["Dinner"])
        #expect(model.filter.isFiltering)
        #expect(model.payers.count == 3)
    }

    @Test func filtersByCategory() throws {
        let fixture = try filterFixture()
        let model = makeModel(fixture)
        model.filter.category = .transport
        #expect(model.visibleExpenses.map(\.title) == ["Taxi"])
        #expect(Set(model.categories) == [.dining, .entertainment, .transport])
    }

    @Test func filtersByPeriod() throws {
        let fixture = try filterFixture()
        let model = makeModel(fixture)

        model.filter.period = .thisMonth
        #expect(model.visibleExpenses.map(\.title) == ["Dinner", "Museum"])
        model.filter.period = .lastMonth
        #expect(model.visibleExpenses.map(\.title) == ["Taxi"])
        model.filter.period = .last30Days
        #expect(model.visibleExpenses.count == 3)

        model.filter.period = .custom
        model.filter.customStart = utcDate(2026, 5, 1)
        model.filter.customEnd = utcDate(2026, 5, 2)
        #expect(model.visibleExpenses.map(\.title) == ["Museum"])
    }

    @Test func searchMatchesTitleCategoryAndPayerNames() throws {
        let fixture = try filterFixture()
        let model = makeModel(fixture)

        model.filter.query = "din"
        #expect(model.visibleExpenses.map(\.title) == ["Dinner"])
        model.filter.query = "priya"
        #expect(model.visibleExpenses.map(\.title) == ["Museum"])
        model.filter.query = "transport"
        #expect(model.visibleExpenses.map(\.title) == ["Taxi"])
        model.filter.query = "nothing here"
        #expect(model.visibleExpenses.isEmpty)
        #expect(model.sections.isEmpty)
    }

    @Test func filtersCombineAndClear() throws {
        let fixture = try filterFixture()
        let model = makeModel(fixture)
        model.filter.payer = fixture.sam.id
        model.filter.category = .transport
        #expect(model.visibleExpenses.isEmpty)

        model.filter.clearFilters()
        #expect(!model.filter.isFiltering)
        #expect(model.visibleExpenses.count == 3)
    }

    // MARK: Totals

    @Test func totalsSplitByPersonAndCategory() throws {
        let fixture = try filterFixture()
        let totals = try #require(makeModel(fixture).primaryTotals)
        #expect(totals.total == usdAmount(9500))
        #expect(totals.expenseCount == 3)
        #expect(totals.byPerson.map(\.name) == ["Sam", "You", "Priya"])
        #expect(totals.byPerson.map(\.paid) == [usdAmount(6000), usdAmount(2000), usdAmount(1500)])
        #expect(totals.byCategory.map(\.category) == [.dining, .transport, .entertainment])
    }

    @Test func refundsReduceTheTotals() throws {
        let fixture = try Fixture()
        _ = try fixture.add("Tickets", cents: 5000, on: utcDate(2026, 5, 1), category: .entertainment)
        let refund = Expense(
            groupID: fixture.group.id, title: "Refund", total: usdAmount(-1000), date: utcDate(2026, 5, 2),
            category: .entertainment, payers: [fixture.me.id: usdAmount(-1000)],
            split: .equal(participants: fixture.everyone)
        )
        try fixture.services.expenses.add(refund)
        let totals = try #require(makeModel(fixture).primaryTotals)
        #expect(totals.total == usdAmount(4000))
        #expect(totals.byCategory.first?.amount == usdAmount(4000))
    }

    @Test func noExpensesMeansNoTotalsAndNoSummaryFacts() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        #expect(model.totals.isEmpty)
        #expect(model.insightInput == nil)
    }

    @Test func summaryFactsDescribeTheSpending() throws {
        let fixture = try filterFixture()
        let input = try #require(makeModel(fixture).insightInput)
        #expect(input.groupName == "Flat")
        #expect(input.expenseCount == 3)
        #expect(input.totalByCategory == 9500)
        #expect(input.members.first?.name == "Sam")
    }

    @Test func expensesInOtherCurrenciesGetTheirOwnTotals() throws {
        let fixture = try Fixture()
        _ = try fixture.add("Lunch", cents: 3000, on: utcDate(2026, 5, 1))
        let yen = Money(minorUnits: 5000, currencyCode: "JPY")
        try fixture.services.expenses.add(Expense(
            groupID: fixture.group.id, title: "Ramen", total: yen, date: utcDate(2026, 5, 2),
            paidBy: fixture.me.id, split: .equal(participants: fixture.everyone)
        ))
        let model = makeModel(fixture)
        #expect(Set(model.totals.map(\.currencyCode)) == ["USD", "JPY"])
        #expect(model.primaryTotals?.currencyCode == "USD")
    }

    // MARK: Activity

    @Test func activityDescribesWhatHappened() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Dinner", paidBy: fixture.sam)
        let model = makeModel(fixture)
        let sentences = model.activity.map { model.activityText.sentence(for: $0) }
        #expect(sentences.first == "You added Dinner")
        #expect(sentences.contains("You created Flat"))
    }

    @Test func activityNamesPaymentsAndMembers() throws {
        let text = GroupActivityText(
            currentPerson: nil, names: [PersonID(): "Ghost"], locale: GroupsTestCalendar.english
        )
        let payer = PersonID(), receiver = PersonID()
        let entry = ActivityEntry(event: .paymentRecorded(PaymentReference(
            id: PaymentID(), payer: payer, receiver: receiver, amount: usdAmount(1250)
        )))
        #expect(text.sentence(for: entry) == "Someone paid Someone $12.50")
    }

    @Test func activitySaysJoinedAndLeftAndCallsTheReaderYou() {
        let sam = PersonID(), me = PersonID(), priya = PersonID()
        let text = GroupActivityText(currentPerson: me, names: [sam: "Sam", priya: "Priya"], locale: GroupsTestCalendar.english)
        func sentence(_ actor: PersonID, _ event: ActivityEvent) -> String {
            text.sentence(for: ActivityEntry(actorID: actor, event: event))
        }
        #expect(sentence(sam, .memberAdded(sam)) == "Sam joined the group")
        #expect(sentence(sam, .memberRemoved(sam)) == "Sam left the group")
        #expect(sentence(me, .memberAdded(me)) == "You joined the group")
        #expect(sentence(me, .memberRemoved(me)) == "You left the group")
        #expect(sentence(sam, .memberAdded(me)) == "Sam added you")
        #expect(sentence(sam, .memberRemoved(me)) == "Sam removed you")
        #expect(sentence(sam, .memberAdded(priya)) == "Sam added Priya")
        #expect(sentence(me, .memberRemoved(priya)) == "You removed Priya")
    }
}
