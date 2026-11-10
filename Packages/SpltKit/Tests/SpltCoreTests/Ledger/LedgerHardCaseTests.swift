import Foundation
import Testing
@testable import SpltCore

/// Random groups that reach what the other property tests do not: every split strategy, currencies
/// with 0 and 3 decimals, one person splits, people left out, amounts of one unit and amounts near
/// the top of what can be typed, refunds, overpayments and deleted entries.
@Suite("Ledger hard cases")
struct LedgerHardCaseTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private let codes = ["USD", "JPY", "KWD"]

    private func magnitude(using generator: inout SeededGenerator) -> Int64 {
        switch Int.random(in: 0..<4, using: &generator) {
        case 0: Int64.random(in: 1...7, using: &generator)
        case 1: Int64.random(in: 8...5_000, using: &generator)
        case 2: Int64.random(in: 5_000...50_000_000, using: &generator)
        default: Int64.random(in: 900_000_000_000_000...1_000_000_000_000_000, using: &generator)
        }
    }

    /// One way of dividing `total` between `group`. Valid by construction, so the ledger must accept it.
    private func split(of total: Money, among group: [PersonID], using generator: inout SeededGenerator) throws -> SplitDefinition {
        let code = total.currencyCode
        let weights = group.map { _ in Int64.random(in: 0...9, using: &generator) }
        let usable = weights.contains { $0 > 0 } ? weights : weights.map { _ in 1 }
        let parts = try LargestRemainderAllocator.allocate(total: total.minorUnits, weights: usable)
        switch Int.random(in: 0..<(total.isNegative ? 5 : 6), using: &generator) {
        case 0:
            return .equal(participants: Set(group))
        case 1:
            return .exact(amounts: Dictionary(uniqueKeysWithValues: zip(group, parts.map { Money(minorUnits: $0, currencyCode: code) })))
        case 2:
            let points = try LargestRemainderAllocator.allocate(total: 10_000, weights: usable)
            return .percentages(basisPoints: Dictionary(uniqueKeysWithValues: zip(group, points)))
        case 3:
            return .shares(weights: Dictionary(uniqueKeysWithValues: zip(group, usable)))
        case 4:
            // Each person's own amount is their exact part minus a common base, so no share points the wrong way.
            let base = parts.min() ?? 0
            let adjustments = zip(group, parts).map { ($0, Money(minorUnits: $1 - base, currencyCode: code)) }
            return .adjustments(participants: Set(group), adjustments: Dictionary(uniqueKeysWithValues: adjustments))
        default:
            let discount = total.minorUnits / 10
            let tax = total.minorUnits / 7
            let tip = total.minorUnits / 9
            let itemTotal = total.minorUnits - tax - tip + discount
            let itemParts = try LargestRemainderAllocator.allocate(total: itemTotal, weights: usable)
            let items = zip(group, itemParts).map {
                SplitItem(name: "item", amount: Money(minorUnits: $1, currencyCode: code), assignees: [$0])
            }
            return .itemized(ItemizedSplit(
                items: items,
                tax: Money(minorUnits: tax, currencyCode: code),
                tip: Money(minorUnits: tip, currencyCode: code),
                discount: Money(minorUnits: discount, currencyCode: code)
            ))
        }
    }

    private func randomEntries(seed: UInt64) throws -> (expenses: [Expense], payments: [Payment]) {
        var generator = SeededGenerator(seed: seed)
        let everyone = (1...Int.random(in: 2...14, using: &generator)).map { person($0) }
        var expenses: [Expense] = []
        for _ in 0..<Int.random(in: 1...10, using: &generator) {
            let code = codes.randomElement(using: &generator)!
            let size = Int.random(in: 1...everyone.count, using: &generator)
            let group = Array(everyone.shuffled(using: &generator).prefix(size)).sorted()
            let units = magnitude(using: &generator) * (Int.random(in: 0..<6, using: &generator) == 0 ? -1 : 1)
            let total = Money(minorUnits: units, currencyCode: code)
            let payers = Array(everyone.shuffled(using: &generator).prefix(Int.random(in: 1...2, using: &generator))).sorted()
            let paid = try LargestRemainderAllocator.allocate(total: units, weights: payers.map { _ in 1 })
            expenses.append(Expense(
                title: "e", total: total, date: date,
                payers: Dictionary(uniqueKeysWithValues: zip(payers, paid.map { Money(minorUnits: $0, currencyCode: code) })),
                split: try split(of: total, among: group, using: &generator),
                deletedAt: Int.random(in: 0..<8, using: &generator) == 0 ? date : nil
            ))
        }
        var payments: [Payment] = []
        for _ in 0..<Int.random(in: 0...4, using: &generator) {
            let pair = Array(everyone.shuffled(using: &generator).prefix(2))
            payments.append(Payment(
                payer: pair[0], receiver: pair[1],
                amount: Money(minorUnits: magnitude(using: &generator), currencyCode: codes.randomElement(using: &generator)!),
                date: date,
                deletedAt: Int.random(in: 0..<8, using: &generator) == 0 ? date : nil
            ))
        }
        return (expenses, payments)
    }

    @Test func balancesStayExactAndSimplifiedPaymentsSettleEveryone() throws {
        for seed in 0..<600 {
            let (expenses, payments) = try randomEntries(seed: UInt64(seed))
            let ledger = Ledger(expenses: expenses, payments: payments)
            #expect(ledger.issues.isEmpty, "seed \(seed)")

            for expense in expenses {
                let shares = try expense.shares().shares.values.reduce(0) { $0 + Int128($1.minorUnits) }
                #expect(shares == Int128(expense.total.minorUnits), "seed \(seed)")
            }

            for (currency, table) in ledger.netBalances {
                #expect(table.values.reduce(Int128(0)) { $0 + Int128($1.minorUnits) } == 0, "seed \(seed)")
                #expect(table.values.allSatisfy { $0.currencyCode == currency })

                var implied: [PersonID: Int128] = [:]
                for debt in ledger.debts where debt.amount.currencyCode == currency {
                    implied[debt.debtor, default: 0] -= Int128(debt.amount.minorUnits)
                    implied[debt.creditor, default: 0] += Int128(debt.amount.minorUnits)
                }
                for (person, balance) in table {
                    #expect(implied[person, default: 0] == Int128(balance.minorUnits), "seed \(seed)")
                }
            }

            let settling = ledger.simplifiedDebts.map { Payment(settling: $0, date: date) }
            let settled = Ledger(expenses: expenses, payments: payments + settling)
            #expect(settled.isSettled, "seed \(seed)")
        }
    }

    @Test func eachSimplifiedCurrencyStaysInItsOwnCurrency() throws {
        for seed in 0..<200 {
            let (expenses, payments) = try randomEntries(seed: UInt64(seed))
            let ledger = Ledger(expenses: expenses, payments: payments)
            for debt in ledger.simplifiedDebts {
                #expect(debt.amount.isPositive)
                #expect(debt.debtor != debt.creditor)
                let debtorOwes = try #require(ledger.netBalances[debt.amount.currencyCode]?[debt.debtor])
                let creditorIsOwed = try #require(ledger.netBalances[debt.amount.currencyCode]?[debt.creditor])
                #expect(debtorOwes.isNegative)
                #expect(creditorIsOwed.isPositive)
            }
        }
    }

    @Test func convertedBalancesStillAddUpAndStayWithinOneUnit() throws {
        var generator = SeededGenerator(seed: 77)
        let rates = ExchangeRates(
            baseCurrency: "EUR",
            rates: ["USD": Decimal(string: "1.0873")!, "JPY": Decimal(string: "162.37")!, "KWD": Decimal(string: "0.33413")!]
        )
        for target in ["USD", "JPY", "KWD", "EUR"] {
            for _ in 0..<200 {
                var amounts: [PersonID: [Money]] = [:]
                let people = (1...Int.random(in: 2...9, using: &generator)).map { person($0) }
                for code in codes {
                    var left: Int64 = 0
                    for someone in people.dropLast() {
                        let value = Int64.random(in: -5_000_000...5_000_000, using: &generator)
                        amounts[someone, default: []].append(Money(minorUnits: value, currencyCode: code))
                        left -= value
                    }
                    amounts[people.last!, default: []].append(Money(minorUnits: left, currencyCode: code))
                }
                let converted = try rates.convert(amounts, to: target)
                #expect(converted.values.reduce(0) { $0 + $1.minorUnits } == 0)
                for (someone, money) in converted {
                    let single = try (amounts[someone] ?? []).map { try rates.convert($0, to: target).minorUnits }.reduce(0, +)
                    #expect(abs(money.minorUnits - single) <= Int64(codes.count) + 1)
                }
            }
        }
    }
}
