import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Expense row summary")
struct ExpenseSummaryTests {
    private let me = PersonID(), sam = PersonID(), priya = PersonID()
    private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currencyCode: "USD") }

    private func expense(payers: [PersonID: Money], split: Set<PersonID>? = nil) -> Expense {
        let total = payers.values.reduce(0) { $0 + $1.minorUnits }
        return Expense(
            title: "Dinner", total: usd(total), date: Date(timeIntervalSince1970: 0), payers: payers,
            split: .equal(participants: split ?? [me, sam, priya])
        )
    }

    @Test func namesWhoPaid() {
        let names = [sam: "Sam", priya: "Priya"]
        #expect(ExpenseSummary(expense: expense(payers: [me: usd(3000)]), currentPerson: me, names: names).paidBy == "You paid")
        #expect(ExpenseSummary(expense: expense(payers: [sam: usd(3000)]), currentPerson: me, names: names).paidBy == "Sam paid")
        let two = expense(payers: [sam: usd(1500), priya: usd(1500)])
        let paidBy = ExpenseSummary(expense: two, currentPerson: me, names: names).paidBy
        #expect(paidBy.hasSuffix("paid"))
        #expect(paidBy.contains("Sam") && paidBy.contains("Priya"))
        let three = expense(payers: [me: usd(1000), sam: usd(1000), priya: usd(1000)])
        #expect(ExpenseSummary(expense: three, currentPerson: me, names: names).paidBy == "3 people paid")
    }

    @Test func unknownPayersAreSomeone() {
        let summary = ExpenseSummary(expense: expense(payers: [sam: usd(3000)]), currentPerson: me, names: [:])
        #expect(summary.paidBy == "Someone paid")
    }

    @Test func yourShareAndPayment() {
        let paid = ExpenseSummary(expense: expense(payers: [me: usd(3000)]), currentPerson: me, names: [:])
        #expect(paid.myShare == usd(1000))
        #expect(paid.myPayment == usd(3000))

        let bystander = ExpenseSummary(
            expense: expense(payers: [sam: usd(3000)], split: [sam, priya]), currentPerson: me, names: [:]
        )
        #expect(bystander.myShare == nil)
        #expect(bystander.myPayment == nil)
    }

    @Test func noCurrentPersonHasNoShare() {
        let summary = ExpenseSummary(expense: expense(payers: [sam: usd(3000)]), currentPerson: nil, names: [:])
        #expect(summary.myShare == nil)
    }
}
