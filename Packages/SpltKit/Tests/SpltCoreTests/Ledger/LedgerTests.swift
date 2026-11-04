import Foundation
import Testing
@testable import SpltCore

@Suite("Ledger")
struct LedgerTests {
    private let a = person(1), b = person(2), c = person(3), d = person(4)
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func expense(
        _ total: Int64, paidBy payer: PersonID, among people: Set<PersonID>, code: String = "USD"
    ) -> Expense {
        Expense(
            title: "Expense", total: money(total, code), date: date,
            paidBy: payer, split: .equal(participants: people)
        )
    }

    @Test func emptyLedgerIsSettled() {
        let ledger = Ledger()
        #expect(ledger.isSettled)
        #expect(ledger.debts.isEmpty)
        #expect(ledger.currencies.isEmpty)
        #expect(ledger.issues.isEmpty)
    }

    @Test func oneExpenseCreatesBalancesAndDebts() {
        let ledger = Ledger(expenses: [expense(9000, paidBy: a, among: [a, b, c])])
        #expect(ledger.netBalances["USD"] == [a: usd(6000), b: usd(-3000), c: usd(-3000)])
        #expect(ledger.debts == [
            Debt(debtor: b, creditor: a, amount: usd(3000)),
            Debt(debtor: c, creditor: a, amount: usd(3000))
        ])
        #expect(!ledger.isSettled)
    }

    @Test func debtsBetweenTwoPeopleNetOut() {
        let ledger = Ledger(expenses: [
            expense(1000, paidBy: a, among: [a, b]),
            expense(400, paidBy: b, among: [a, b])
        ])
        // b owes 500 for the first, a owes 200 for the second
        #expect(ledger.debts == [Debt(debtor: b, creditor: a, amount: usd(300))])
    }

    @Test func debtsFlipDirectionWhenTheBalanceSwings() {
        let ledger = Ledger(expenses: [
            expense(200, paidBy: a, among: [a, b]),
            expense(1000, paidBy: b, among: [a, b])
        ])
        #expect(ledger.debts == [Debt(debtor: a, creditor: b, amount: usd(400))])
    }

    @Test func exactlyOffsettingExpensesLeaveNoDebt() {
        let ledger = Ledger(expenses: [
            expense(1000, paidBy: a, among: [a, b]),
            expense(1000, paidBy: b, among: [a, b])
        ])
        #expect(ledger.debts.isEmpty)
        #expect(ledger.isSettled)
        #expect(ledger.netBalances["USD"] == [a: usd(0), b: usd(0)])
    }

    @Test func paymentsReduceDebts() {
        let ledger = Ledger(
            expenses: [expense(9000, paidBy: a, among: [a, b, c])],
            payments: [Payment(payer: b, receiver: a, amount: usd(3000), date: date)]
        )
        #expect(ledger.netBalances["USD"] == [a: usd(3000), b: usd(0), c: usd(-3000)])
        #expect(ledger.debts == [Debt(debtor: c, creditor: a, amount: usd(3000))])
    }

    @Test func overpayingFlipsTheDebt() {
        let ledger = Ledger(
            expenses: [expense(1000, paidBy: a, among: [a, b])],
            payments: [Payment(payer: b, receiver: a, amount: usd(800), date: date)]
        )
        #expect(ledger.debts == [Debt(debtor: a, creditor: b, amount: usd(300))])
    }

    @Test func severalPayersRepayProportionally() {
        let expense = Expense(
            title: "Cabin", total: usd(10_000), date: date,
            payers: [a: usd(6000), b: usd(4000)], split: .equal(participants: [a, b, c, d])
        )
        let ledger = Ledger(expenses: [expense])
        // c and d each owe 25.00, split between a and b in the ratio 35 to 15
        #expect(ledger.debts == [
            Debt(debtor: c, creditor: a, amount: usd(1750)),
            Debt(debtor: c, creditor: b, amount: usd(750)),
            Debt(debtor: d, creditor: a, amount: usd(1750)),
            Debt(debtor: d, creditor: b, amount: usd(750))
        ])
    }

    @Test func refundsMoveMoneyBack() {
        let spend = expense(9000, paidBy: a, among: [a, b, c])
        let refund = Expense(
            title: "Refund", total: usd(-3000), date: date,
            paidBy: a, split: .equal(participants: [a, b, c])
        )
        let ledger = Ledger(expenses: [spend, refund])
        #expect(ledger.netBalances["USD"] == [a: usd(4000), b: usd(-2000), c: usd(-2000)])
        #expect(ledger.debts == [
            Debt(debtor: b, creditor: a, amount: usd(2000)),
            Debt(debtor: c, creditor: a, amount: usd(2000))
        ])
    }

    @Test func currenciesStaySeparate() {
        let ledger = Ledger(expenses: [
            expense(1000, paidBy: a, among: [a, b], code: "USD"),
            expense(2000, paidBy: b, among: [a, b], code: "EUR"),
            expense(5000, paidBy: a, among: [a, b], code: "JPY")
        ])
        #expect(ledger.currencies == ["EUR", "JPY", "USD"])
        #expect(ledger.balances(of: a) == [eur(-1000), money(2500, "JPY"), usd(500)])
        #expect(ledger.debts.map(\.amount.currencyCode) == ["EUR", "JPY", "USD"])
    }

    @Test func deletedEntriesAreIgnored() {
        var gone = expense(9000, paidBy: a, among: [a, b])
        gone.deletedAt = date
        var undone = Payment(payer: b, receiver: a, amount: usd(100), date: date)
        undone.deletedAt = date
        let ledger = Ledger(expenses: [gone], payments: [undone])
        #expect(ledger.isSettled)
        #expect(ledger.issues.isEmpty)
    }

    @Test func badEntriesAreSkippedAndReported() {
        let good = expense(1000, paidBy: a, among: [a, b])
        let broken = Expense(
            title: "Broken", total: usd(1000), date: date,
            payers: [a: usd(900)], split: .equal(participants: [a, b])
        )
        let selfPayment = Payment(payer: a, receiver: a, amount: usd(100), date: date)
        let ledger = Ledger(expenses: [good, broken], payments: [selfPayment])
        #expect(ledger.debts == [Debt(debtor: b, creditor: a, amount: usd(500))])
        #expect(ledger.issues == [
            .expense(broken.id, .payersDoNotMatchTotal(expected: usd(1000), actual: usd(900))),
            .payment(selfPayment.id, .samePerson)
        ])
    }

    @Test func balancesOfAPersonSkipZeros() {
        let ledger = Ledger(expenses: [expense(1000, paidBy: a, among: [a, b])])
        #expect(ledger.balances(of: a) == [usd(500)])
        #expect(ledger.balances(of: b) == [usd(-500)])
        #expect(ledger.balances(of: c).isEmpty)
    }

    @Test func balancesWithMeAreFromMyPointOfView() {
        let ledger = Ledger(expenses: [
            expense(9000, paidBy: a, among: [a, b, c]),
            expense(2000, paidBy: b, among: [b, c]),
            expense(800, paidBy: c, among: [a, c])
        ])
        let mine = ledger.balances(with: a)
        #expect(mine[b] == [usd(3000)])
        #expect(mine[c] == [usd(2600)])
        let theirs = ledger.balances(with: c)
        #expect(theirs[a] == [usd(-2600)])
        #expect(theirs[b] == [usd(-1000)])
        #expect(ledger.balances(with: d).isEmpty)
    }

    @Test func balancesWithMeKeepCurrenciesApart() {
        let ledger = Ledger(expenses: [
            expense(1000, paidBy: a, among: [a, b], code: "USD"),
            expense(600, paidBy: b, among: [a, b], code: "EUR")
        ])
        #expect(ledger.balances(with: a)[b] == [eur(-300), usd(500)])
    }

    @Test func convertsNetBalancesIntoOneCurrencyAndStillSumsToZero() throws {
        let ledger = Ledger(expenses: [
            expense(1001, paidBy: a, among: [a, b, c], code: "USD"),
            expense(2003, paidBy: b, among: [a, b, c], code: "EUR"),
            expense(7001, paidBy: c, among: [a, b], code: "JPY")
        ])
        let rates = ExchangeRates(
            baseCurrency: "EUR",
            rates: ["USD": Decimal(string: "1.0873")!, "JPY": Decimal(string: "161.27")!]
        )
        let converted = try ledger.netBalances(in: "EUR", rates: rates)
        #expect(converted.values.allSatisfy { $0.currencyCode == "EUR" })
        #expect(converted.values.reduce(0) { $0 + $1.minorUnits } == 0)
        #expect(Set(converted.keys) == [a, b, c])
    }

    @Test func conversionNeedsRates() {
        let ledger = Ledger(expenses: [expense(1000, paidBy: a, among: [a, b], code: "USD")])
        let rates = ExchangeRates(baseCurrency: "EUR", rates: [:])
        #expect(throws: ExchangeRatesError.missingRate(from: "USD", to: "EUR")) {
            try ledger.netBalances(in: "EUR", rates: rates)
        }
    }

    @Test func convertsBalancesWithMe() throws {
        let ledger = Ledger(expenses: [
            expense(1000, paidBy: a, among: [a, b], code: "USD"),
            expense(600, paidBy: b, among: [a, b], code: "EUR")
        ])
        let rates = ExchangeRates(baseCurrency: "EUR", rates: ["USD": 2])
        let converted = try ledger.balances(with: a, in: "EUR", rates: rates)
        // b owes 5.00 USD (2.50 EUR) and is owed 3.00 EUR, so a owes b 0.50 EUR
        #expect(converted[b] == eur(-50))
    }

    @Test func orderOfEntriesDoesNotMatter() {
        let entries = [
            expense(1001, paidBy: a, among: [a, b, c]),
            expense(2002, paidBy: b, among: [b, c, d]),
            expense(3003, paidBy: c, among: [a, c, d]),
            expense(4004, paidBy: d, among: [a, b, c, d])
        ]
        let forward = Ledger(expenses: entries)
        let backward = Ledger(expenses: entries.reversed())
        #expect(forward.netBalances == backward.netBalances)
        #expect(forward.debts == backward.debts)
    }

    @Test func aNetThatCannotBeNegatedIsSkippedInsteadOfCrashing() {
        let a = person(1), b = person(2), c = person(3)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let half = Int64.min / 2
        let ledger = Ledger(expenses: [
            Expense(title: "x", total: usd(half), date: date, paidBy: a, split: .exact(amounts: [b: usd(half)])),
            Expense(title: "y", total: usd(half), date: date, paidBy: a, split: .exact(amounts: [c: usd(half)]))
        ])
        #expect(ledger.issues.count == 1)
        #expect(ledger.simplifiedDebts.count == 1)
    }

    @Test func simplifiedBalancesLeaveNoDebtsOnceTheShortcutIsPaid() {
        let a = person(1), b = person(2), c = person(3)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expenses = [
            Expense(title: "x", total: usd(1000), date: date, paidBy: b, split: .exact(amounts: [a: usd(1000)])),
            Expense(title: "y", total: usd(1000), date: date, paidBy: c, split: .exact(amounts: [b: usd(1000)]))
        ]
        let before = Ledger(expenses: expenses)
        #expect(before.balances(with: a) == [b: [usd(-1000)]])
        #expect(before.balances(with: a, simplified: true) == [c: [usd(-1000)]])

        let after = Ledger(expenses: expenses, payments: before.simplifiedDebts.map { Payment(settling: $0, date: date) })
        #expect(after.isSettled)
        #expect(after.balances(with: a, simplified: true).isEmpty)
        #expect(after.balances(with: a).count == 2)
    }
}
