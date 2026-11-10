import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

@Suite("Balance cache")
struct BalanceCacheUnitTests {
    private let group = GroupID()

    private func ledger(_ cents: Int64) -> Ledger {
        let a = PersonID()
        let b = PersonID()
        return Ledger(expenses: [Expense(
            title: "x", total: usdAmount(cents), date: Date(), paidBy: a, split: .equal(participants: [a, b])
        )])
    }

    @Test func aSecondReadDoesNotRecompute() {
        let cache = BalanceCache()
        var computed = 0
        for _ in 0..<3 {
            _ = cache.ledger(for: group) {
                computed += 1
                return ledger(100)
            }
        }
        #expect(computed == 1)
        #expect(cache.cachedGroupCount == 1)
    }

    @Test func invalidatingOneGroupLeavesTheOthers() {
        let cache = BalanceCache()
        let other = GroupID()
        _ = cache.ledger(for: group) { ledger(100) }
        _ = cache.ledger(for: other) { ledger(200) }
        cache.invalidate(group)
        #expect(cache.cachedGroupCount == 1)
        var computed = 0
        _ = cache.ledger(for: other) { computed += 1; return ledger(200) }
        _ = cache.ledger(for: group) { computed += 1; return ledger(300) }
        #expect(computed == 1)
    }

    @Test func invalidateAllClearsEverything() {
        let cache = BalanceCache()
        _ = cache.ledger(for: group) { ledger(100) }
        cache.invalidateAll()
        #expect(cache.cachedGroupCount == 0)
    }

    @Test func aLedgerBuiltWhileAWriteLandsIsNotStored() {
        let cache = BalanceCache()
        _ = cache.ledger(for: group) {
            cache.invalidate(group)
            return ledger(100)
        }
        #expect(cache.cachedGroupCount == 0)
        _ = cache.ledger(for: group) {
            cache.invalidateAll()
            return ledger(100)
        }
        #expect(cache.cachedGroupCount == 0)
    }

    @Test func failedComputationsAreNotCached() {
        struct Failure: Error {}
        let cache = BalanceCache()
        #expect(throws: Failure.self) { try cache.ledger(for: group) { throw Failure() } }
        #expect(cache.cachedGroupCount == 0)
    }
}

/// After every kind of write, a cached ledger must equal one built from the rows.
@MainActor
@Suite("Balance cache agreement")
struct BalanceCacheAgreementTests {
    private func readEverything(_ services: DataServices) throws {
        for group in try services.groups.groups(includeArchived: true) {
            _ = try services.groups.balances(for: group.id)
        }
        _ = try services.people.friendBalances()
    }

    /// Reads the cached answers, then rebuilds them from scratch, and expects the same.
    private func expectAgreement(_ services: DataServices, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let env = services.environment
        var cachedLedgers: [GroupID: Ledger] = [:]
        for group in try services.groups.groups(includeArchived: true) {
            cachedLedgers[group.id] = try env.ledger(forGroup: group.id)
        }
        let cachedFriends = try services.people.friendBalances()
        for (id, cached) in cachedLedgers {
            let fresh = try env.freshLedger(forGroup: id)
            #expect(cached.netBalances == fresh.netBalances, sourceLocation: sourceLocation)
            #expect(cached.debts == fresh.debts, sourceLocation: sourceLocation)
            #expect(cached.issues == fresh.issues, sourceLocation: sourceLocation)
        }
        env.balanceCache.invalidateAll()
        #expect(try services.people.friendBalances() == cachedFriends, sourceLocation: sourceLocation)
    }

    private func twoGroups() throws -> (Fixture, SplitGroup) {
        let fixture = try Fixture()
        let second = SplitGroup(name: "Trip", currencyCode: "USD", memberIDs: [fixture.me.id, fixture.sam.id])
        try fixture.services.groups.create(second)
        try fixture.addExpense("Base", cents: 3000)
        try fixture.services.expenses.add(Expense(
            groupID: second.id, title: "Hotel", total: usdAmount(8000), date: fixture.clock.start,
            paidBy: fixture.sam.id, split: .equal(participants: [fixture.me.id, fixture.sam.id])
        ))
        try readEverything(fixture.services)
        return (fixture, second)
    }

    @Test func aWriteOnlyDropsTheGroupItTouched() throws {
        let (fixture, _) = try twoGroups()
        let cache = fixture.services.environment.balanceCache
        #expect(cache.cachedGroupCount == 2)
        try fixture.addExpense("More", cents: 100)
        #expect(cache.cachedGroupCount == 1)
    }

    @Test func addEditDeleteAndRestoreAgree() throws {
        let (fixture, _) = try twoGroups()
        let services = fixture.services
        var expense = try fixture.addExpense("Dinner", cents: 4200)
        try expectAgreement(services)
        try readEverything(services)
        expense.total = usdAmount(9000)
        expense.payers = [fixture.me.id: usdAmount(9000)]
        try services.expenses.update(expense)
        try expectAgreement(services)
        try readEverything(services)
        try services.expenses.delete(id: expense.id)
        try expectAgreement(services)
        try readEverything(services)
        try services.expenses.restore(id: expense.id)
        try expectAgreement(services)
    }

    @Test func movingAnExpenseBetweenGroupsFixesBothLedgers() throws {
        let (fixture, second) = try twoGroups()
        var moved = try fixture.addExpense("Moves", cents: 6000)
        try readEverything(fixture.services)
        moved.groupID = second.id
        try fixture.services.expenses.update(moved)
        try expectAgreement(fixture.services)
    }

    @Test func batchAddsAgree() throws {
        let (fixture, _) = try twoGroups()
        let batch = (1...20).map { fixture.expense("Batch \($0)", cents: Int64(100 * $0)) }
        try fixture.services.insertBatch(batch)
        try expectAgreement(fixture.services)
    }

    @Test func aFailedBatchChangesNothingAndStillAgrees() throws {
        let (fixture, _) = try twoGroups()
        var batch = (1...5).map { fixture.expense("Batch \($0)", cents: Int64(100 * $0)) }
        batch[3].payers = [fixture.me.id: usdAmount(1)]
        #expect(throws: DataError.self) { try fixture.services.insertBatch(batch) }
        try expectAgreement(fixture.services)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 1)
    }

    @discardableResult
    private func settleGroup(_ fixture: Fixture) throws -> [Payment] {
        try fixture.services.groups.balances(for: fixture.group.id).suggestedSettlements.map {
            try fixture.services.payments.settle($0, in: fixture.group.id, date: fixture.clock.start)
        }
    }

    @Test func paymentsAndUndoAgree() throws {
        let (fixture, _) = try twoGroups()
        let services = fixture.services
        let made = try settleGroup(fixture)
        try expectAgreement(services)
        try readEverything(services)
        try services.payments.undo(id: try #require(made.first).id)
        try expectAgreement(services)
        try readEverything(services)
        try services.payments.restore(id: try #require(made.first).id)
        try expectAgreement(services)
        try readEverything(services)
        try services.payments.record(Payment(
            groupID: fixture.group.id, payer: fixture.priya.id, receiver: fixture.me.id,
            amount: usdAmount(100), date: fixture.clock.start
        ))
        try expectAgreement(services)
    }

    @Test func memberAndGroupSettingChangesAgree() throws {
        let (fixture, _) = try twoGroups()
        let services = fixture.services
        try settleGroup(fixture)
        try readEverything(services)
        try services.groups.removeMember(fixture.priya.id, from: fixture.group.id)
        try expectAgreement(services)
        try readEverything(services)
        try services.groups.addMember(fixture.priya.id, to: fixture.group.id)
        try readEverything(services)
        var edited = try #require(try services.groups.group(id: fixture.group.id))
        edited.simplifiesDebts = false
        edited.pinnedRate = PinnedRate(from: "EUR", to: "USD", rate: Decimal(string: "1.1")!)
        try services.groups.update(edited)
        try expectAgreement(services)
        #expect(try services.groups.balances(for: fixture.group.id).simplifiesDebts == false)
    }

    @Test func deletingAGroupAgrees() throws {
        let (fixture, second) = try twoGroups()
        try fixture.services.groups.delete(id: second.id)
        try expectAgreement(fixture.services)
        #expect(try fixture.services.people.friendBalance(with: fixture.sam.id).byGroup.map(\.groupID) == [fixture.group.id])
    }

    @Test func importsAgree() throws {
        let (fixture, _) = try twoGroups()
        let csv = """
        Date,Description,Category,Cost,Currency,Me,Sam
        2025-03-14,Lunch,Dining out,20.00,USD,10.00,-10.00
        2025-03-15,Sam paid Me,Payment,5.00,USD,-5.00,5.00
        """
        _ = try fixture.services.groups.importSplitwiseCSV(csv, into: fixture.group.id)
        try expectAgreement(fixture.services)
    }

    @Test func recurringExpensesAgree() throws {
        let (fixture, _) = try twoGroups()
        try fixture.services.recurring.add(RecurringExpense(
            groupID: fixture.group.id, title: "Rent", total: usdAmount(90_000), payers: [fixture.me.id: usdAmount(90_000)],
            split: .equal(participants: fixture.everyone),
            rule: RecurrenceRule(frequency: .daily, startDate: fixture.clock.start, timeZone: TimeZone(identifier: "UTC")!)
        ))
        try fixture.services.recurring.createDueExpenses(through: fixture.clock.start.addingTimeInterval(3 * 86_400))
        try expectAgreement(fixture.services)
    }

    // Remote changes

    private func expensePayload(_ fixture: Fixture, _ expense: Expense, edit: (inout SyncPayload) -> Void) throws -> SyncPayload {
        let tracker = fixture.services.makeChangeTracker()
        var payload = try #require(try tracker.payload(recordType: .expense, recordName: expense.id.description))
        edit(&payload)
        return payload
    }

    @Test func remoteEditsAgree() throws {
        let (fixture, _) = try twoGroups()
        let expense = try fixture.addExpense("Remote", cents: 3000)
        let tracker = fixture.services.makeChangeTracker()
        try tracker.markSynced(recordType: .expense, recordName: expense.id.description, sentModifiedAt: .distantFuture, systemFields: Data([1]))
        try readEverything(fixture.services)

        var changed = expense
        changed.total = usdAmount(12_000)
        changed.payers = [fixture.sam.id: usdAmount(12_000)]
        let source = ExpenseRecord(changed)
        let payload = try expensePayload(fixture, expense) {
            $0.fields = source.syncFields
            $0.modifiedAt = $0.modifiedAt.addingTimeInterval(60)
        }
        #expect(try tracker.applyRemote(payload) == .updated)
        try expectAgreement(fixture.services)
    }

    @Test func remoteTombstonesAgree() throws {
        let (fixture, _) = try twoGroups()
        let expense = try fixture.addExpense("Remote", cents: 3000)
        let tracker = fixture.services.makeChangeTracker()
        try tracker.markSynced(recordType: .expense, recordName: expense.id.description, sentModifiedAt: .distantFuture, systemFields: Data([1]))
        try readEverything(fixture.services)
        let payload = try expensePayload(fixture, expense) {
            let at = $0.modifiedAt.addingTimeInterval(60)
            $0.modifiedAt = at
            $0.deletedAt = at
        }
        try tracker.applyRemote(payload)
        try expectAgreement(fixture.services)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 1)
    }

    @Test func remoteInsertsAndDeletionsAgree() throws {
        let (fixture, _) = try twoGroups()
        let tracker = fixture.services.makeChangeTracker()
        let incoming = ExpenseRecord(fixture.expense("From afar", cents: 5000))
        let payload = incoming.syncPayload
        try readEverything(fixture.services)
        try tracker.applyRemote(payload)
        try expectAgreement(fixture.services)
        try readEverything(fixture.services)
        try tracker.applyRemoteDeletion(
            recordType: .expense, recordName: incoming.recordName, at: Date().addingTimeInterval(3_600)
        )
        try expectAgreement(fixture.services)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 1)
    }

    @Test func remotePaymentsAgree() throws {
        let (fixture, _) = try twoGroups()
        let incoming = PaymentRecord(Payment(
            groupID: fixture.group.id, payer: fixture.sam.id, receiver: fixture.me.id,
            amount: usdAmount(700), date: fixture.clock.start
        ))
        try readEverything(fixture.services)
        try fixture.services.makeChangeTracker().applyRemote(incoming.syncPayload)
        try expectAgreement(fixture.services)
    }

    @Test func aRemoteExpenseThatMovesGroupFixesBothLedgers() throws {
        let (fixture, second) = try twoGroups()
        let expense = try fixture.addExpense("Travels", cents: 3000)
        let tracker = fixture.services.makeChangeTracker()
        try tracker.markSynced(recordType: .expense, recordName: expense.id.description, sentModifiedAt: .distantFuture, systemFields: Data([1]))
        try readEverything(fixture.services)
        var moved = expense
        moved.groupID = second.id
        let source = ExpenseRecord(moved)
        let payload = try expensePayload(fixture, expense) {
            $0.fields = source.syncFields
            $0.zoneName = second.id.description
            $0.modifiedAt = $0.modifiedAt.addingTimeInterval(60)
        }
        try tracker.applyRemote(payload)
        try expectAgreement(fixture.services)
    }

    @Test func aTrackerOnAnotherContextInvalidatesToo() throws {
        let (fixture, _) = try twoGroups()
        let services = fixture.services
        try readEverything(services)
        let background = ModelContext(services.container)
        let tracker = services.makeChangeTracker(context: background)
        let record = ExpenseRecord(fixture.expense("Elsewhere", cents: 7000))
        background.insert(record)
        tracker.recordEdit(record)
        try tracker.save()
        try expectAgreement(services)
        let fresh = try services.environment.freshLedger(forGroup: fixture.group.id)
        let net = try services.groups.balances(for: fixture.group.id).net(for: fixture.me.id)
        #expect(net == fresh.balances(of: fixture.me.id))
        #expect(net != [usdAmount(2000)])
    }

    @Test func directSoftDeletesThroughTheTrackerAgree() throws {
        let (fixture, _) = try twoGroups()
        let expense = try fixture.addExpense("Soft", cents: 3000)
        let tracker = fixture.services.makeChangeTracker()
        let record = try #require(try ExpenseRecord.find(recordName: expense.id.description, in: fixture.services.container.mainContext))
        try readEverything(fixture.services)
        tracker.softDelete(record)
        try tracker.save()
        try expectAgreement(fixture.services)
    }
}
