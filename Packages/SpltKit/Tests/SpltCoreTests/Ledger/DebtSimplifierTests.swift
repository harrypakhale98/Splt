import Foundation
import Testing
@testable import SpltCore

@Suite("Debt simplifier")
struct DebtSimplifierTests {
    private func balances(_ values: [Int64], code: String = "USD") -> [PersonID: Money] {
        Dictionary(uniqueKeysWithValues: values.enumerated().map { (person($0.offset + 1), money($0.element, code)) })
    }

    /// What each person ends up with after the debts are paid: positive means still owed.
    private func remaining(_ original: [PersonID: Money], after debts: [Debt]) -> [PersonID: Int64] {
        var result = original.mapValues(\.minorUnits)
        for debt in debts {
            result[debt.debtor, default: 0] += debt.amount.minorUnits
            result[debt.creditor, default: 0] -= debt.amount.minorUnits
        }
        return result
    }

    @Test func nothingToSettle() throws {
        #expect(try DebtSimplifier.simplify([PersonID: Money]()).isEmpty)
        #expect(try DebtSimplifier.simplify(balances([0, 0, 0])).isEmpty)
    }

    @Test func twoPeopleNeedOnePayment() throws {
        let debts = try DebtSimplifier.simplify(balances([500, -500]))
        #expect(debts == [Debt(debtor: person(2), creditor: person(1), amount: usd(500))])
    }

    @Test func aChainCollapsesToDirectPayments() throws {
        // a owes b 10, b owes c 10: a pays c directly
        let debts = try DebtSimplifier.simplify(balances([-1000, 0, 1000]))
        #expect(debts == [Debt(debtor: person(1), creditor: person(3), amount: usd(1000))])
    }

    @Test func oneCreditorManyDebtors() throws {
        let debts = try DebtSimplifier.simplify(balances([900, -300, -300, -300]))
        #expect(debts.count == 3)
        #expect(debts.allSatisfy { $0.creditor == person(1) && $0.amount == usd(300) })
    }

    @Test func greedyPairsLargestWithLargest() throws {
        let debts = try DebtSimplifier.greedy(balances([1000, 300, -800, -500]))
        #expect(debts == [
            Debt(debtor: person(3), creditor: person(1), amount: usd(800)),
            Debt(debtor: person(4), creditor: person(2), amount: usd(300)),
            Debt(debtor: person(4), creditor: person(1), amount: usd(200))
        ])
    }

    @Test func exactSearchBeatsGreedyWhenTheGroupSplitsIntoCircles() throws {
        // {+8, -8} and {-2, -7, +9} are separate circles: 3 payments, but greedy needs 4
        let input = balances([800, -800, -200, -700, 900])
        let greedy = try DebtSimplifier.greedy(input)
        let simplified = try DebtSimplifier.simplify(input)
        #expect(greedy.count == 4)
        #expect(simplified.count == 3)
        #expect(remaining(input, after: simplified).values.allSatisfy { $0 == 0 })
        #expect(simplified.contains(Debt(debtor: person(2), creditor: person(1), amount: usd(800))))
    }

    @Test func largeGroupsFallBackToGreedy() throws {
        var values: [Int64] = []
        for index in 0..<7 { values.append(Int64(100 * (index + 1))) }
        for index in 0..<7 { values.append(-Int64(100 * (index + 1))) }
        let input = balances(values)
        #expect(input.count == 14)
        let simplified = try DebtSimplifier.simplify(input)
        #expect(simplified == (try DebtSimplifier.greedy(input)))
        #expect(remaining(input, after: simplified).values.allSatisfy { $0 == 0 })
    }

    @Test func peopleWithZeroBalanceDoNotCountTowardTheSearchLimit() throws {
        let values: [Int64] = [800, -800, -200, -700, 900] + Array(repeating: 0, count: 20)
        #expect(try DebtSimplifier.simplify(balances(values)).count == 3)
    }

    @Test func rejectsUnbalancedInput() {
        #expect(throws: DebtSimplifierError.balancesDoNotSumToZero(currencyCode: "USD", difference: 100)) {
            try DebtSimplifier.simplify(balances([500, -400]))
        }
    }

    @Test func rejectsMixedCurrencies() {
        var input = balances([500, -500])
        input[person(2)] = eur(-500)
        #expect(throws: DebtSimplifierError.self) { try DebtSimplifier.simplify(input) }
        #expect(throws: DebtSimplifierError.self) { try DebtSimplifier.greedy(input) }
    }

    @Test func settlesEachCurrencySeparately() throws {
        let debts = try DebtSimplifier.simplify([
            "USD": balances([500, -500], code: "USD"),
            "JPY": balances([-300, 300], code: "JPY")
        ])
        #expect(debts == [
            Debt(debtor: person(1), creditor: person(2), amount: money(300, "JPY")),
            Debt(debtor: person(2), creditor: person(1), amount: usd(500))
        ])
    }

    @Test func outputOrderIsLargestFirstThenById() throws {
        let debts = try DebtSimplifier.simplify(balances([300, 300, -300, -300]))
        #expect(debts.map(\.amount.minorUnits) == [300, 300])
        #expect(debts.map(\.debtor) == [person(3), person(4)])
    }

    @Test func netEffectMatchesBalancesAndNeverBeatsTheBound() throws {
        var generator = SeededGenerator(seed: 314)
        for _ in 0..<600 {
            let count = Int.random(in: 2...14, using: &generator)
            var values = (0..<count - 1).map { _ in Int64.random(in: -5_000...5_000, using: &generator) }
            values.append(-values.reduce(0, +))
            let input = balances(values)
            let simplified = try DebtSimplifier.simplify(input)
            let greedy = try DebtSimplifier.greedy(input)

            #expect(remaining(input, after: simplified).values.allSatisfy { $0 == 0 })
            #expect(simplified.count <= greedy.count)
            let open = values.filter { $0 != 0 }.count
            #expect(simplified.count <= max(open - 1, 0))
            #expect(simplified.allSatisfy { $0.amount.isPositive && $0.debtor != $0.creditor })

            let payers = Set(simplified.map(\.debtor))
            let receivers = Set(simplified.map(\.creditor))
            #expect(payers.isDisjoint(with: receivers))
        }
    }

    @Test func countMatchesTheBruteForceOptimumForSmallGroups() throws {
        var generator = SeededGenerator(seed: 8)
        for _ in 0..<300 {
            let count = Int.random(in: 2...8, using: &generator)
            var values = (0..<count - 1).map { _ in Int64.random(in: -6...6, using: &generator) }
            values.append(-values.reduce(0, +))
            let open = values.filter { $0 != 0 }
            let optimum = open.isEmpty ? 0 : open.count - maximumZeroSumGroups(open)
            #expect(try DebtSimplifier.simplify(balances(values)).count == optimum)
        }
    }

    /// Plain recursion over subsets, independent of the production search.
    private func maximumZeroSumGroups(_ values: [Int64]) -> Int {
        func best(_ remaining: Int) -> Int {
            guard remaining != 0 else { return 0 }
            let first = remaining & -remaining
            var result = Int.min
            var subset = remaining
            while subset > 0 {
                if subset & first != 0 {
                    var sum: Int64 = 0
                    for index in values.indices where subset & (1 << index) != 0 { sum += values[index] }
                    if sum == 0 {
                        let rest = best(remaining ^ subset)
                        if rest != Int.min { result = max(result, rest + 1) }
                    }
                }
                subset = (subset - 1) & remaining
            }
            return result
        }
        return best((1 << values.count) - 1)
    }

    @Test func ledgerSimplifiedDebtsSettleTheGroup() {
        let a = person(1), b = person(2), c = person(3), d = person(4)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expenses = [
            Expense(title: "Rent", total: usd(120_000), date: date, paidBy: a, split: .equal(participants: [a, b, c, d])),
            Expense(title: "Food", total: usd(8_000), date: date, paidBy: b, split: .equal(participants: [a, b, c])),
            Expense(title: "Taxi", total: usd(3_001), date: date, paidBy: c, split: .equal(participants: [c, d])),
            Expense(title: "Trip", total: money(30_000, "JPY"), date: date, paidBy: d, split: .equal(participants: [a, d]))
        ]
        let ledger = Ledger(expenses: expenses)
        let suggestions = ledger.simplifiedDebts
        #expect(suggestions.count <= ledger.debts.count)

        let payments = suggestions.map { Payment(settling: $0, date: date) }
        let settled = Ledger(expenses: expenses, payments: payments)
        #expect(settled.isSettled)
        #expect(settled.balances(of: a).isEmpty)
    }

    @Test func ledgerSimplifiedDebtsAreSortedByCurrency() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let ledger = Ledger(expenses: [
            Expense(title: "x", total: usd(1000), date: date, paidBy: person(1), split: .equal(participants: [person(1), person(2)])),
            Expense(title: "y", total: eur(1000), date: date, paidBy: person(1), split: .equal(participants: [person(1), person(2)]))
        ])
        #expect(ledger.simplifiedDebts.map(\.amount.currencyCode) == ["EUR", "USD"])
    }
}
