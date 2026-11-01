import Foundation
import Testing
@testable import SpltCore

@Suite("Ledger properties")
struct LedgerPropertyTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func randomSplit(among group: [PersonID], total: Int64, using generator: inout SeededGenerator) -> SplitDefinition {
        switch Int.random(in: 0..<3, using: &generator) {
        case 0:
            return .equal(participants: Set(group))
        case 1:
            return .shares(weights: Dictionary(uniqueKeysWithValues: group.map { ($0, Int64.random(in: 1...5, using: &generator)) }))
        default:
            var remaining: Int64 = 10_000
            var basisPoints: [PersonID: Int64] = [:]
            for person in group.dropLast() {
                let part = Int64.random(in: 0...remaining, using: &generator)
                basisPoints[person] = part
                remaining -= part
            }
            basisPoints[group.last!] = remaining
            return .percentages(basisPoints: basisPoints)
        }
    }

    private func randomLedger(seed: UInt64) -> (Ledger, [Expense], [Payment]) {
        var generator = SeededGenerator(seed: seed)
        let everyone = (1...6).map { person($0) }
        var expenses: [Expense] = []
        for _ in 0..<Int.random(in: 1...12, using: &generator) {
            let size = Int.random(in: 1...everyone.count, using: &generator)
            let group = Array(everyone.shuffled(using: &generator).prefix(size)).sorted()
            let magnitude = Int64.random(in: 1...200_000, using: &generator)
            let total = Int.random(in: 0..<6, using: &generator) == 0 ? -magnitude : magnitude
            let payerCount = Int.random(in: 1...min(3, everyone.count), using: &generator)
            let payers = Array(everyone.shuffled(using: &generator).prefix(payerCount)).sorted()
            let paid = try! LargestRemainderAllocator.allocate(
                total: total,
                weights: payers.map { _ in Int64.random(in: 1...9, using: &generator) }
            )
            expenses.append(Expense(
                title: "e", total: usd(total), date: date,
                payers: Dictionary(uniqueKeysWithValues: zip(payers, paid.map { usd($0) })),
                split: randomSplit(among: group, total: total, using: &generator)
            ))
        }
        var payments: [Payment] = []
        for _ in 0..<Int.random(in: 0...5, using: &generator) {
            let pair = everyone.shuffled(using: &generator).prefix(2)
            payments.append(Payment(
                payer: pair[pair.startIndex], receiver: pair[pair.startIndex + 1],
                amount: usd(Int64.random(in: 1...50_000, using: &generator)), date: date
            ))
        }
        return (Ledger(expenses: expenses, payments: payments), expenses, payments)
    }

    @Test func balancesAlwaysSumToZeroAndNothingIsSkipped() {
        for seed in 0..<300 {
            let (ledger, _, _) = randomLedger(seed: UInt64(seed))
            #expect(ledger.issues.isEmpty)
            let sum = ledger.netBalances["USD"]?.values.reduce(0) { $0 + $1.minorUnits } ?? 0
            #expect(sum == 0)
        }
    }

    @Test func directDebtsExplainTheNetBalancesExactly() {
        for seed in 0..<300 {
            let (ledger, _, _) = randomLedger(seed: UInt64(seed))
            var implied: [PersonID: Int64] = [:]
            for debt in ledger.debts {
                #expect(debt.amount.isPositive)
                #expect(debt.debtor != debt.creditor)
                implied[debt.debtor, default: 0] -= debt.amount.minorUnits
                implied[debt.creditor, default: 0] += debt.amount.minorUnits
            }
            for (person, balance) in ledger.netBalances["USD"] ?? [:] {
                #expect(implied[person, default: 0] == balance.minorUnits)
            }
        }
    }

    @Test func eachPairAppearsInOnlyOneDirection() {
        for seed in 0..<200 {
            let (ledger, _, _) = randomLedger(seed: UInt64(seed))
            var seen = Set<PersonPair>()
            for debt in ledger.debts {
                #expect(seen.insert(PersonPair(debt.debtor, debt.creditor)).inserted)
            }
        }
    }

    @Test func balancesWithMeAreMirrorImages() {
        for seed in 0..<100 {
            let (ledger, _, _) = randomLedger(seed: UInt64(seed))
            for me in (1...6).map({ person($0) }) {
                for (other, amounts) in ledger.balances(with: me) {
                    let back = ledger.balances(with: other)[me]
                    #expect(back == amounts.map { usd(-$0.minorUnits) })
                }
            }
        }
    }
}
