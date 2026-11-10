import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Group totals")
struct GroupTotalsTests {
    private let ana = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!)
    private let ben = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000B2")!)
    private var names: [PersonID: String] { [ana: "Ana", ben: "Ben"] }

    private func expense(
        _ title: String, _ cents: Int64, currency: String = "USD", category: ExpenseCategory = .general,
        payers: [PersonID: Int64]? = nil, deleted: Bool = false
    ) -> Expense {
        let paid = (payers ?? [ana: cents]).mapValues { Money(minorUnits: $0, currencyCode: currency) }
        return Expense(
            title: title, total: Money(minorUnits: cents, currencyCode: currency), date: Date(timeIntervalSince1970: 0),
            category: category, payers: paid, split: .equal(participants: [ana, ben]),
            deletedAt: deleted ? Date(timeIntervalSince1970: 1) : nil
        )
    }

    @Test func noExpensesMeansNoTotals() {
        #expect(GroupTotals.make(expenses: [], names: names).isEmpty)
    }

    @Test func addsUpByPersonAndCategory() throws {
        let totals = GroupTotals.make(expenses: [
            expense("Dinner", 6000, category: .dining, payers: [ana: 4000, ben: 2000]),
            expense("Taxi", 1500, category: .transport, payers: [ben: 1500]),
            expense("Lunch", 1000, category: .dining)
        ], names: names)

        let usd = try #require(totals.first)
        #expect(totals.count == 1)
        #expect(usd.currencyCode == "USD")
        #expect(usd.total == usdAmount(8500))
        #expect(usd.expenseCount == 3)
        #expect(usd.byPerson.map(\.name) == ["Ana", "Ben"])
        #expect(usd.byPerson.map(\.paid) == [usdAmount(5000), usdAmount(3500)])
        #expect(usd.byCategory.map(\.category) == [.dining, .transport])
        #expect(usd.byCategory.map(\.amount) == [usdAmount(7000), usdAmount(1500)])
    }

    @Test func deletedExpensesDoNotCount() throws {
        let totals = GroupTotals.make(expenses: [
            expense("Real", 1000), expense("Mistake", 9000, deleted: true)
        ], names: names)
        #expect(totals.first?.total == usdAmount(1000))
        #expect(totals.first?.expenseCount == 1)
    }

    @Test func refundsReduceWhatTheyRefund() throws {
        let totals = GroupTotals.make(expenses: [
            expense("Tickets", 5000, category: .entertainment),
            expense("Refund", -1200, category: .entertainment, payers: [ben: -1200])
        ], names: names)
        let usd = try #require(totals.first)
        #expect(usd.total == usdAmount(3800))
        #expect(usd.byCategory.first?.amount == usdAmount(3800))
        #expect(usd.byPerson.map(\.paid) == [usdAmount(5000), usdAmount(-1200)])
    }

    @Test func eachCurrencyGetsItsOwnTotalsMostUsedFirst() {
        let totals = GroupTotals.make(expenses: [
            expense("Lunch", 3000), expense("Ramen", 5000, currency: "JPY"), expense("Coffee", 400)
        ], names: names)
        #expect(totals.map(\.currencyCode) == ["USD", "JPY"])
        #expect(totals[0].total == usdAmount(3400))
        #expect(totals[1].total == Money(minorUnits: 5000, currencyCode: "JPY"))
    }

    @Test func peopleWithoutANameAreSomeone() {
        let stranger = PersonID()
        let totals = GroupTotals.make(expenses: [expense("Gift", 1000, payers: [stranger: 1000])], names: names)
        #expect(totals.first?.byPerson.first?.name == "Someone")
    }

    @Test func tiesKeepAStableOrder() {
        let items = [expense("A", 1000, category: .dining), expense("B", 1000, category: .drinks)]
        let first = GroupTotals.make(expenses: items, names: names)
        let second = GroupTotals.make(expenses: items.reversed(), names: names)
        #expect(first == second)
        #expect(first.first?.byCategory.map(\.category) == [.dining, .drinks])
    }

    @Test func hugeAmountsStopAtTheLimitInsteadOfOverflowing() {
        let totals = GroupTotals.make(expenses: [expense("A", .max), expense("B", 10)], names: names)
        #expect(totals.first?.total.minorUnits == .max)
    }

    @Test func summaryFactsFollowTheGroupKind() throws {
        let totals = try #require(GroupTotals.make(expenses: [
            expense("Dinner", 6000, category: .dining, payers: [ana: 4000, ben: 2000])
        ], names: names).first)

        let trip = totals.insightInput(groupName: "Lisbon", kind: .trip)
        #expect(trip.kind == .trip)
        #expect(trip.groupName == "Lisbon")
        #expect(trip.expenseCount == 1)
        #expect(trip.categories == [InsightInput.CategoryAmount(name: ExpenseCategory.dining.title, minorUnits: 6000)])
        #expect(trip.members == [
            InsightInput.MemberAmount(name: "Ana", paidMinorUnits: 4000),
            InsightInput.MemberAmount(name: "Ben", paidMinorUnits: 2000)
        ])
        #expect(totals.insightInput(groupName: "x", kind: .couple).kind == .household)
        #expect(totals.insightInput(groupName: "x", kind: .standard).kind == .other)
        #expect(totals.insightInput(groupName: "x", kind: .friend).kind == .other)
    }

    @Test func summaryFactsListMembersWhoPaidNothing() throws {
        let cal = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000C3")!)
        let dee = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000D4")!)
        let everyone = names.merging([cal: "Cal", dee: "Dee"]) { first, _ in first }
        let totals = try #require(GroupTotals.make(expenses: [
            expense("Dinner", 10_000, category: .dining, payers: [ana: 5000, ben: 5000])
        ], names: everyone).first)

        let input = totals.insightInput(groupName: "Flat", kind: .standard, members: [ana, ben, cal, dee], names: everyone)
        #expect(input.members == [
            InsightInput.MemberAmount(name: "Ana", paidMinorUnits: 5000),
            InsightInput.MemberAmount(name: "Ben", paidMinorUnits: 5000),
            InsightInput.MemberAmount(name: "Cal", paidMinorUnits: 0),
            InsightInput.MemberAmount(name: "Dee", paidMinorUnits: 0)
        ])
        #expect(!InsightSummarizer.template(for: input).contains("Everyone"))

        // when all four paid about the same, everyone did
        let even = try #require(GroupTotals.make(expenses: [
            expense("Dinner", 10_000, category: .dining, payers: [ana: 2500, ben: 2500, cal: 2500, dee: 2500])
        ], names: everyone).first)
        let evenInput = even.insightInput(groupName: "Flat", kind: .standard, members: [ana, ben, cal, dee], names: everyone)
        #expect(InsightSummarizer.template(for: evenInput).contains("Everyone has paid a similar amount."))
    }
}
