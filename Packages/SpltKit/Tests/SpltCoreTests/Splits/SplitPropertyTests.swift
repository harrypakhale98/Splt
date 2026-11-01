import Foundation
import Testing
@testable import SpltCore

@Suite("Split properties")
struct SplitPropertyTests {
    private func people(_ count: Int) -> [PersonID] { (1...count).map { person($0) } }

    @Test func everyStrategyAddsUpToTheTotal() throws {
        var generator = SeededGenerator(seed: 2024)
        for round in 0..<1_500 {
            let count = Int.random(in: 1...9, using: &generator)
            let group = people(count)
            let magnitude = Int64.random(in: 0...5_000_000, using: &generator)
            let total = usd(round % 5 == 0 ? -magnitude : magnitude)

            let equal = try SplitCalculator.shares(for: .equal(participants: Set(group)), total: total)
            #expect(equal.values.reduce(0) { $0 + $1.minorUnits } == total.minorUnits)

            let weights = Dictionary(uniqueKeysWithValues: group.map { ($0, Int64.random(in: 1...20, using: &generator)) })
            let weighted = try SplitCalculator.shares(for: .shares(weights: weights), total: total)
            #expect(weighted.values.reduce(0) { $0 + $1.minorUnits } == total.minorUnits)

            var remaining: Int64 = 10_000
            var basisPoints: [PersonID: Int64] = [:]
            for person in group.dropLast() {
                let part = Int64.random(in: 0...remaining, using: &generator)
                basisPoints[person] = part
                remaining -= part
            }
            basisPoints[group.last!] = remaining
            let percent = try SplitCalculator.shares(for: .percentages(basisPoints: basisPoints), total: total)
            #expect(percent.values.reduce(0) { $0 + $1.minorUnits } == total.minorUnits)

            for (person, share) in weighted {
                let ideal = Double(total.minorUnits) * Double(weights[person]!) / Double(weights.values.reduce(0, +))
                #expect(abs(Double(share.minorUnits) - ideal) < 1.0 + 1e-6)
            }
        }
    }

    @Test func resultsDoNotDependOnInsertionOrder() throws {
        let group = people(7)
        let forward = try SplitCalculator.shares(for: .equal(participants: Set(group)), total: usd(1_000_003))
        let backward = try SplitCalculator.shares(for: .equal(participants: Set(group.reversed())), total: usd(1_000_003))
        #expect(forward == backward)
    }

    @Test func itemizedBillsAlwaysAddUp() throws {
        var generator = SeededGenerator(seed: 99)
        for _ in 0..<500 {
            let group = people(Int.random(in: 1...6, using: &generator))
            var items: [SplitItem] = []
            var subtotal: Int64 = 0
            for index in 0..<Int.random(in: 1...8, using: &generator) {
                let amount = Int64.random(in: 0...20_000, using: &generator)
                let assignees = Set(group.filter { _ in Bool.random(using: &generator) })
                items.append(SplitItem(name: "item \(index)", amount: usd(amount), assignees: assignees.isEmpty ? [group[0]] : assignees))
                subtotal += amount
            }
            let tax = Int64.random(in: 0...3_000, using: &generator)
            let tip = Int64.random(in: 0...5_000, using: &generator)
            let discount = Int64.random(in: 0...subtotal, using: &generator)
            let split = ItemizedSplit(items: items, tax: usd(tax), tip: usd(tip), discount: usd(discount))
            let total = subtotal + tax + tip - discount
            let result = try SplitCalculator.calculate(.itemized(split), total: usd(total))
            #expect(result.shares.values.reduce(0) { $0 + $1.minorUnits } == total)
            #expect(result.shares.values.allSatisfy { $0.minorUnits >= 0 })
            #expect(Set(result.shares.keys) == split.participants)
        }
    }

    @Test func adjustmentsAlwaysAddUp() throws {
        var generator = SeededGenerator(seed: 5)
        for _ in 0..<500 {
            let group = people(Int.random(in: 1...6, using: &generator))
            let total = Int64.random(in: 100_000...900_000, using: &generator)
            var adjustments: [PersonID: Money] = [:]
            for person in group where Bool.random(using: &generator) {
                adjustments[person] = usd(Int64.random(in: -500...500, using: &generator))
            }
            let result = try SplitCalculator.shares(
                for: .adjustments(participants: Set(group), adjustments: adjustments),
                total: usd(total)
            )
            #expect(result.values.reduce(0) { $0 + $1.minorUnits } == total)
        }
    }

    @Test func definitionsSurviveJSON() throws {
        let definitions: [SplitDefinition] = [
            .equal(participants: [person(1), person(2)]),
            .exact(amounts: [person(1): usd(100)]),
            .percentages(basisPoints: [person(1): 10_000]),
            .shares(weights: [person(1): 2, person(2): 3]),
            .adjustments(participants: [person(1)], adjustments: [person(1): usd(-5)]),
            .itemized(ItemizedSplit(
                items: [SplitItem(name: "tea", amount: usd(300), assignees: [person(1)])],
                tax: usd(30)
            ))
        ]
        for definition in definitions {
            let data = try JSONEncoder().encode(definition)
            #expect(try JSONDecoder().decode(SplitDefinition.self, from: data) == definition)
        }
    }
}
