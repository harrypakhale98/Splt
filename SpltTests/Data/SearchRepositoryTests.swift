import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Search")
struct SearchRepositoryTests {
    private func fixtureWithExpenses() throws -> Fixture {
        let fixture = try Fixture()
        try fixture.addExpense("Sushi dinner", cents: 4250, paidBy: fixture.sam)
        try fixture.addExpense("Taxi to airport", cents: 1800)
        var rent = fixture.expense("Rent", cents: 90_000)
        rent.note = "March, paid early"
        rent.category = .rent
        try fixture.services.expenses.add(rent)
        return fixture
    }

    @Test func findsExpensesByTitleIgnoringCaseAndAccents() throws {
        let fixture = try fixtureWithExpenses()
        #expect(try fixture.services.search.search("SUSHI", limit: 10).expenses.map(\.title) == ["Sushi dinner"])
        #expect(try fixture.services.search.search("sushí", limit: 10).expenses.count == 1)
    }

    @Test func findsExpensesByNoteCategoryAndGroupName() throws {
        let fixture = try fixtureWithExpenses()
        #expect(try fixture.services.search.search("early", limit: 10).expenses.map(\.title) == ["Rent"])
        #expect(try fixture.services.search.search("rent", limit: 10).expenses.map(\.title) == ["Rent"])
        #expect(try fixture.services.search.search("flat", limit: 10).expenses.count == 3)
    }

    @Test func findsExpensesByAmount() throws {
        let fixture = try fixtureWithExpenses()
        #expect(try fixture.services.search.search("42.50", limit: 10).expenses.map(\.title) == ["Sushi dinner"])
    }

    @Test func findsExpensesByWhoPaidOrOwes() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Sushi dinner", paidBy: fixture.sam, splitBetween: [fixture.sam.id, fixture.me.id])
        try fixture.addExpense("Taxi", splitBetween: [fixture.me.id, fixture.priya.id])
        #expect(try fixture.services.search.search("sam", limit: 10).expenses.map(\.title) == ["Sushi dinner"])
        #expect(try fixture.services.search.search("priya", limit: 10).expenses.map(\.title) == ["Taxi"])
    }

    @Test func everyWordMustMatch() throws {
        let fixture = try Fixture()
        try fixture.addExpense("Sushi dinner", paidBy: fixture.sam, splitBetween: [fixture.sam.id, fixture.me.id])
        try fixture.addExpense("Sushi lunch", splitBetween: [fixture.me.id, fixture.priya.id])
        let results = try fixture.services.search.search("sushi sam", limit: 10)
        #expect(results.expenses.map(\.title) == ["Sushi dinner"])
        #expect(try fixture.services.search.search("sushi nobody", limit: 10).expenses.isEmpty)
    }

    @Test func findsPeopleAndGroups() throws {
        let fixture = try Fixture()
        let results = try fixture.services.search.search("pri", limit: 10)
        #expect(results.people.map(\.name) == ["Priya"])
        #expect(results.groups.isEmpty)
        #expect(try fixture.services.search.search("fla", limit: 10).groups.map(\.name) == ["Flat"])
    }

    @Test func deletedExpensesAreNotFound() throws {
        let fixture = try Fixture()
        let expense = try fixture.addExpense("Sushi dinner")
        try fixture.services.expenses.delete(id: expense.id)
        #expect(try fixture.services.search.search("sushi", limit: 10).isEmpty)
    }

    @Test func blankQueriesAndLimitsBehave() throws {
        let fixture = try Fixture()
        for index in 1...5 { try fixture.addExpense("Coffee \(index)") }
        #expect(try fixture.services.search.search("   ", limit: 10).isEmpty)
        #expect(try fixture.services.search.search("coffee", limit: 3).expenses.count == 3)
    }

    @Test func resultsAreNewestFirst() throws {
        let fixture = try Fixture()
        let old = try fixture.addExpense("Coffee old", date: fixture.clock.start)
        let new = try fixture.addExpense("Coffee new", date: fixture.clock.start.addingTimeInterval(86_400))
        #expect(try fixture.services.search.search("coffee", limit: 10).expenses.map(\.id) == [new.id, old.id])
    }
}
