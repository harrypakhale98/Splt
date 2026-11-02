import Foundation
import SpltCore
import Testing
@testable import Splt

/// Thresholds are loose on purpose: they catch an accidental quadratic loop, not a few milliseconds.
@MainActor
@Suite("Large store", .serialized)
struct LargeStoreTests {
    private static let fixture = try? LargeStoreFixture()

    private func measure(_ label: String, limit: Duration, _ work: () throws -> Void) rethrows {
        let clock = ContinuousClock()
        let elapsed = try clock.measure(work)
        print("perf \(label): \(elapsed)")
        #expect(elapsed < limit, "\(label) took \(elapsed)")
    }

    @Test func fixtureHoldsThousandsOfExpenses() throws {
        let fixture = try #require(Self.fixture)
        let count = try fixture.groups.reduce(0) {
            $0 + (try fixture.services.expenses.expenses(in: $1.id, includeDeleted: false).count)
        }
        #expect(count == fixture.expenseCount)
        #expect(fixture.groups.count == 30)
    }

    @Test func groupsListLoadsQuickly() throws {
        let fixture = try #require(Self.fixture)
        measure("groups list", limit: .seconds(3)) { fixture.services.groupsStore.refresh() }
        #expect(fixture.services.groupsStore.summaries.count == 30)
    }

    @Test func friendsListLoadsQuickly() throws {
        let fixture = try #require(Self.fixture)
        measure("friends list", limit: .seconds(3)) { fixture.services.friendsStore.refresh() }
    }

    @Test func theBiggestGroupOpensAndComputesBalances() throws {
        let fixture = try #require(Self.fixture)
        let biggest = fixture.groups[0]
        var model: GroupDetailViewModel?
        measure("group detail load", limit: .seconds(2)) {
            model = GroupDetailViewModel(groupID: biggest.id, services: fixture.services)
        }
        let loaded = try #require(model)
        #expect(loaded.expenses.count > 1500)

        measure("group sections", limit: .milliseconds(500)) { _ = loaded.sections }
        measure("group totals", limit: .milliseconds(500)) { _ = loaded.totals }
        measure("group net rows", limit: .milliseconds(200)) { _ = loaded.netRows }
        measure("group transfers", limit: .milliseconds(200)) { _ = loaded.transfers }
    }

    @Test func searchStaysResponsive() throws {
        let fixture = try #require(Self.fixture)
        measure("search", limit: .seconds(2)) {
            _ = try? fixture.services.search.search("Expense 12", limit: 50)
        }
    }

    @Test func addingOneExpenseRefreshesQuickly() throws {
        let fixture = try #require(Self.fixture)
        let group = fixture.groups[0]
        let expense = Expense(
            groupID: group.id, title: "One more", total: Money(minorUnits: 1_000, currencyCode: group.currencyCode),
            date: Date(), paidBy: fixture.me.id, split: .equal(participants: Set(group.memberIDs))
        )
        measure("add then refresh", limit: .seconds(3)) {
            try? fixture.services.expenses.add(expense)
            fixture.services.groupsStore.refresh()
        }
    }
}
