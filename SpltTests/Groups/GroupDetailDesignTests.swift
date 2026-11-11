import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Group detail design logic")
struct GroupDetailDesignTests {
    private func model(_ fixture: Fixture, groupID: GroupID? = nil) -> GroupDetailViewModel {
        GroupDetailViewModel(
            groupID: groupID ?? fixture.group.id, services: fixture.services,
            now: { utcDate(2026, 5, 15) }, calendar: GroupsTestCalendar.utc
        )
    }

    // MARK: Expense rows

    @Test func youLentWhenYouPaidMoreThanYourShare() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Dinner", cents: 3000, paidBy: fixture.me)
        let summary = ExpenseRowSummary(
            expense: expense, currentPerson: fixture.me.id, names: [fixture.me.id: "Me", fixture.sam.id: "Sam"]
        )
        #expect(summary.yourNet == usdAmount(2000))
        #expect(summary.caption == "you lent")
        #expect(summary.detail(locale: GroupsTestCalendar.english) == "you lent $20.00")
        #expect(summary.payerText == "You paid")
        #expect(summary.payers == [fixture.me.id])
    }

    @Test func youBorrowedWhenSomeoneElsePaid() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Taxi", cents: 3000, paidBy: fixture.sam)
        let summary = ExpenseRowSummary(expense: expense, currentPerson: fixture.me.id, names: [fixture.sam.id: "Sam"])
        #expect(summary.yourNet == usdAmount(-1000))
        #expect(summary.caption == "you owe")
        #expect(summary.detail(locale: GroupsTestCalendar.english) == "you owe $10.00")
        #expect(summary.payerText == "Sam paid")
    }

    @Test func youComeFirstWhenTwoPeoplePaid() throws {
        let fixture = try Fixture()
        let both = ExpenseSummary.payerText(
            [fixture.me.id: usdAmount(1000), fixture.sam.id: usdAmount(2000)],
            currentPerson: fixture.me.id, names: [fixture.me.id: "Me", fixture.sam.id: "Sam"]
        )
        #expect(both == "You and Sam paid")
    }

    @Test func notBeingInvolvedHasNoNet() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Lunch", cents: 2000, paidBy: fixture.sam, splitBetween: [fixture.sam.id, fixture.priya.id])
        let summary = ExpenseRowSummary(expense: expense, currentPerson: fixture.me.id, names: [:])
        #expect(summary.yourNet == nil)
        #expect(summary.caption == nil)
        #expect(summary.detail(locale: GroupsTestCalendar.english) == nil)
    }

    @Test func payingExactlyYourShareIsEven() throws {
        let fixture = try Fixture()
        let expense = Expense(
            groupID: fixture.group.id, title: "Even", total: usdAmount(2000), date: utcDate(2026, 5, 1),
            payers: [fixture.me.id: usdAmount(1000), fixture.sam.id: usdAmount(1000)],
            split: .equal(participants: [fixture.me.id, fixture.sam.id])
        )
        let summary = ExpenseRowSummary(expense: expense, currentPerson: fixture.me.id, names: [fixture.sam.id: "Sam"])
        #expect(summary.yourNet == usdAmount(0))
        #expect(summary.caption == "even")
        #expect(summary.detail(locale: GroupsTestCalendar.english) == "even")
        #expect(summary.payers.count == 2)
    }

    @Test func withoutAProfileThereIsNoNet() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Dinner")
        #expect(ExpenseRowSummary(expense: expense, currentPerson: nil, names: [:]).yourNet == nil)
    }

    // MARK: Day totals

    @Test func aSectionAddsUpItsExpenses() throws {
        let fixture = try Fixture()
        _ = try fixture.add("A", cents: 1000, on: utcDate(2026, 5, 3))
        _ = try fixture.add("B", cents: 250, on: utcDate(2026, 5, 3, hour: 18))
        let sections = model(fixture).sections
        #expect(sections.count == 1)
        #expect(sections.first?.total == usdAmount(1250))
    }

    @Test func aSectionThatMixesCurrenciesHasNoTotal() {
        let ana = PersonID()
        func expense(_ code: String) -> Expense {
            Expense(
                title: code, total: Money(minorUnits: 100, currencyCode: code), date: utcDate(2026, 5, 3),
                paidBy: ana, split: .equal(participants: [ana])
            )
        }
        let section = ExpenseSection(start: utcDate(2026, 5, 3, hour: 0), expenses: [expense("USD"), expense("EUR")])
        #expect(section.total == nil)
        #expect(ExpenseSection(start: .now, expenses: []).total == nil)
    }

    // MARK: Orbit board

    @Test func theBoardHasYouFirstAndTheCurrentPayments() throws {
        let fixture = try Fixture(simplifies: true)
        try fixture.addExpense("Dinner", cents: 3000)
        let board = model(fixture).orbitBoard(currency: "USD")
        #expect(board.nodes.first?.id == fixture.me.id)
        #expect(board.nodes.count == 3)
        #expect(Set(board.transfers.map(\.debtor)) == [fixture.sam.id, fixture.priya.id])
        #expect(board.center(for: .none).kind == .owed)
        #expect(board.center(for: .none).amount == usdAmount(2000))
    }

    @Test func theBoardFollowsTheSimplifySwitch() throws {
        let fixture = try Fixture(simplifies: true)
        try fixture.addExpense("Tickets", cents: 2000, paidBy: fixture.me, splitBetween: [fixture.me.id, fixture.sam.id])
        try fixture.addExpense("Lunch", cents: 2000, paidBy: fixture.sam, splitBetween: [fixture.sam.id, fixture.priya.id])
        let model = model(fixture)
        #expect(model.orbitBoard(currency: "USD").transfers.count == 1)
        model.setSimplifiesDebts(false)
        #expect(model.orbitBoard(currency: "USD").transfers.count == 2)
    }

    @Test func balanceCurrenciesStartWithTheGroupCurrency() throws {
        let fixture = try Fixture()
        #expect(model(fixture).balanceCurrencies == ["USD"])
        try fixture.addExpense("Dinner", cents: 3000)
        try fixture.services.expenses.add(Expense(
            groupID: fixture.group.id, title: "Ramen", total: Money(minorUnits: 3000, currencyCode: "JPY"),
            date: utcDate(2026, 5, 2), paidBy: fixture.sam.id, split: .equal(participants: fixture.everyone)
        ))
        let model = model(fixture)
        #expect(model.balanceCurrencies == ["USD", "JPY"])
        #expect(model.orbitBoard(currency: "JPY").transfers.allSatisfy { $0.amount.currencyCode == "JPY" })
    }

    @Test func aSquareGroupHasACalmBoard() throws {
        let fixture = try Fixture()
        let board = model(fixture).orbitBoard(currency: "USD")
        #expect(board.isSettled)
        #expect(board.center(for: .none).kind == .settled)
    }

    // MARK: Recap entry

    @Test func theRecapIsOnlyAvailableOnceThereIsSpending() throws {
        let fixture = try Fixture()
        #expect(model(fixture).recapStats == nil)
        _ = try fixture.add("Dinner", cents: 3000, on: utcDate(2026, 5, 1))
        #expect(model(fixture).recapStats?.total == usdAmount(3000))
    }
}
