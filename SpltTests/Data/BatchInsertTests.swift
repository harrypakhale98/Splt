import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Batch inserts")
struct BatchInsertTests {
    private func batch(_ fixture: Fixture, count: Int) -> [Expense] {
        (1...count).map { fixture.expense("Item \($0)", cents: Int64(100 + $0)) }
    }

    @Test func batchedExpensesAreTrackedForSyncLikeSingleOnes() throws {
        let fixture = try Fixture()
        let expenses = batch(fixture, count: 3)
        try fixture.services.insertBatch(expenses)
        let pending = try fixture.services.makeChangeTracker().pendingChanges()
            .filter { $0.recordType == .expense }.map(\.recordName)
        #expect(Set(pending) == Set(expenses.map(\.id.description)))
        let details = try #require(try fixture.services.expenses.details(id: expenses[0].id))
        #expect(details.createdBy == fixture.me.id)
    }

    @Test func anInvalidExpenseStoresNothing() throws {
        let fixture = try Fixture()
        var expenses = batch(fixture, count: 10)
        expenses[7].payers = [fixture.me.id: usdAmount(1)]
        let entriesBefore = try fixture.services.activity.entries(limit: 100).count
        #expect(throws: DataError.self) { try fixture.services.insertBatch(expenses) }
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).isEmpty)
        #expect(try fixture.services.activity.entries(limit: 100).count == entriesBefore)
    }

    @Test func duplicateIDsInsideOrOutsideTheBatchAreRefused() throws {
        let fixture = try Fixture()
        var expenses = batch(fixture, count: 3)
        expenses[2].id = expenses[0].id
        #expect(throws: DataError.alreadyExists("expense \(expenses[0].id)")) {
            try fixture.services.insertBatch(expenses)
        }
        let stored = try fixture.addExpense("Stored")
        var clash = batch(fixture, count: 2)
        clash[1].id = stored.id
        #expect(throws: DataError.alreadyExists("expense \(stored.id)")) {
            try fixture.services.insertBatch(clash)
        }
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 1)
    }

    @Test func missingOrUnknownGroupsAreRefused() throws {
        let fixture = try Fixture()
        var loose = batch(fixture, count: 2)
        loose[1].groupID = nil
        #expect(throws: DataError.missingGroup) { try fixture.services.insertBatch(loose) }
        var stray = batch(fixture, count: 2)
        stray[0].groupID = GroupID()
        #expect(throws: DataError.self) { try fixture.services.insertBatch(stray) }
    }

    @Test func singleAddsStillLogOneEntryEach() throws {
        let fixture = try Fixture()
        try fixture.addExpense("One")
        try fixture.addExpense("Two")
        let kinds = try fixture.services.activity.entries(in: fixture.group.id, limit: 10).map(\.event.kind)
        #expect(kinds.filter { $0 == .expenseAdded }.count == 2)
        #expect(!kinds.contains(.expensesImported))
    }

    @Test func theImporterWritesOneSummaryAndBalancesMatch() throws {
        let fixture = try Fixture()
        var rows = ["Date,Description,Category,Cost,Currency,Me,Sam"]
        for day in 1...28 { rows.append("2025-02-\(String(format: "%02d", day)),Meal \(day),Dining out,20.00,USD,10.00,-10.00") }
        let summary = try fixture.services.groups.importSplitwiseCSV(rows.joined(separator: "\n"), into: fixture.group.id)
        #expect(summary.expensesAdded == 28)
        let entries = try fixture.services.activity.entries(in: fixture.group.id, limit: 100)
        #expect(entries.filter { $0.event.kind == .expensesImported }.count == 1)
        #expect(entries.filter { $0.event.kind == .expenseAdded }.isEmpty)
        #expect(try fixture.services.groups.balances(for: fixture.group.id).net(for: fixture.me.id) == [usdAmount(28 * 1000)])
    }
}
