import Foundation
import SpltCore
import Testing
@testable import Splt

/// Bounds are loose on purpose: they catch an accidental return to recomputing everything or to a query per insert.
@MainActor
@Suite("Bulk performance", .serialized)
struct BulkPerformanceTests {
    private static let fixture = try? LargeStoreFixture()

    private func seconds(_ work: () throws -> Void) rethrows -> Double {
        let elapsed = try ContinuousClock().measure(work)
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    @Test func aSaveOnlyRecomputesTheGroupItTouched() throws {
        let fixture = try #require(Self.fixture)
        let services = fixture.services
        let cache = services.environment.balanceCache

        cache.invalidateAll()
        let cold = seconds { services.groupsStore.refresh() }
        #expect(cache.cachedGroupCount == fixture.groups.count)

        let small = fixture.groups[fixture.groups.count - 1]
        let expense = Expense(
            groupID: small.id, title: "One more", total: Money(minorUnits: 1_000, currencyCode: small.currencyCode),
            date: Date(), paidBy: fixture.me.id, split: .equal(participants: Set(small.memberIDs))
        )
        try services.expenses.add(expense)
        #expect(cache.cachedGroupCount == fixture.groups.count - 1)
        let warm = seconds { services.groupsStore.refresh() }
        print("perf groups refresh cold \(cold) warm \(warm)")
        #expect(warm < cold * 0.6, "warm \(warm) cold \(cold)")
        #expect(warm < 2)

        let friendsWarm = seconds { services.friendsStore.refresh() }
        print("perf friends refresh warm \(friendsWarm)")
        #expect(friendsWarm < cold * 0.6, "friends \(friendsWarm) cold \(cold)")
    }

    @Test func cachedAnswersMatchRowsOnTheBigStore() throws {
        let fixture = try #require(Self.fixture)
        let env = fixture.services.environment
        for group in fixture.groups.prefix(5) {
            let cached = try env.ledger(forGroup: group.id)
            let fresh = try env.freshLedger(forGroup: group.id)
            #expect(cached.netBalances == fresh.netBalances)
        }
    }

    @Test func thousandsOfExpensesGoInQuicklyWithOneSave() throws {
        let fixture = try #require(Self.fixture)
        let group = fixture.groups[1]
        let members = group.memberIDs
        let batch = (0..<2_000).map { number in
            Expense(
                groupID: group.id, title: "Bulk \(number)",
                total: Money(minorUnits: Int64(100 + number), currencyCode: group.currencyCode),
                date: Date(timeIntervalSince1970: 1_800_000_000 + Double(number)),
                paidBy: members[number % members.count], split: .equal(participants: Set(members.prefix(6)))
            )
        }
        let elapsed = try seconds { try fixture.services.insertBatch(batch) }
        print("perf batch of 2000 into a store of 5000: \(elapsed)")
        #expect(elapsed < 20)
        let stored = try fixture.services.expenses.expenses(in: group.id).filter { $0.title.hasPrefix("Bulk ") }
        #expect(stored.count == 2_000)
    }

    @Test func singleInsertsDoNotSlowDownAsTheStoreGrows() throws {
        let fixture = try #require(Self.fixture)
        let group = fixture.groups[2]
        func addOne(_ number: Int) throws {
            try fixture.services.expenses.add(Expense(
                groupID: group.id, title: "Single \(number)",
                total: Money(minorUnits: 500, currencyCode: group.currencyCode), date: Date(),
                paidBy: fixture.me.id, split: .equal(participants: Set(group.memberIDs))
            ))
        }
        let perInsert = try seconds { for number in 0..<100 { try addOne(number) } } / 100
        print("perf single insert in a large store: \(perInsert)")
        #expect(perInsert < 0.2)
    }
}
