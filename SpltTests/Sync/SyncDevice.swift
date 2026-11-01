import CloudKit
import Foundation
import SpltCore
import Testing
@testable import Splt

/// One simulated phone: an in-memory store, its sync bookkeeping and a clock.
@MainActor
final class SyncDevice {
    let services: DataServices
    let clock: TestClock
    let store = InMemorySyncStateStore()
    let adapter: SyncStoreAdapter

    var tracker: ChangeTracker { services.makeChangeTracker() }

    init(start: TimeInterval = 1_750_000_000) throws {
        clock = TestClock(start: Date(timeIntervalSince1970: start))
        services = try DataServices.inMemory(now: clock.reading)
        adapter = SyncStoreAdapter(tracker: services.makeChangeTracker(), store: store)
    }

    /// Everything the adapter currently wants to send, built the way the engine would build it.
    func outgoing() throws -> (plan: OutgoingPlan, records: [CKRecord]) {
        let plan = try adapter.collectOutgoing()
        let records = try plan.saves.compactMap { try adapter.outgoingRecord(for: $0) }
        return (plan, records)
    }
}

/// A server that keeps the last record for each id and no more. It has no conflict detection of its
/// own: tests that need a conflict hand the adapter a `serverRecordChanged` error directly.
@MainActor
final class FakeCloud {
    private(set) var records: [CKRecord.ID: CKRecord] = [:]
    private(set) var zones: Set<CKRecordZone.ID> = []

    /// Uploads whatever the device has pending and confirms it, like one successful send.
    @discardableResult
    func upload(from device: SyncDevice) throws -> OutgoingPlan {
        let (plan, saved) = try device.outgoing()
        zones.formUnion(plan.zonesToSave)
        device.adapter.zonesSaved(plan.zonesToSave.map { CKRecordZone(zoneID: $0) })
        for record in saved {
            records[record.recordID] = record
        }
        for id in plan.deletes {
            records[id] = nil
        }
        for zone in plan.zonesToDelete {
            zones.remove(zone)
            records = records.filter { $0.key.zoneID != zone }
        }
        try device.adapter.didSend(saved: saved, deleted: plan.deletes)
        for zone in plan.zonesToDelete {
            try device.adapter.zoneDeleteConfirmed(zone)
        }
        return plan
    }

    /// Hands every record in the cloud to the device, like a first fetch.
    @discardableResult
    func download(to device: SyncDevice) throws -> ApplyReport {
        try device.adapter.applyFetched(modifications: Array(records.values), deletions: [])
    }
}

/// A user with two friends and a group holding all three, plus one of each kind of record.
@MainActor
struct PopulatedDevice {
    let device: SyncDevice
    let me: Person
    let sam: Person
    let priya: Person
    let group: SplitGroup

    init(start: TimeInterval = 1_750_000_000) throws {
        device = try SyncDevice(start: start)
        let services = device.services
        me = try services.people.ensureMe(name: "Me")
        let created = device.clock.start
        sam = Person(name: "Sam", contactHint: "sam@example.com", avatarSeed: 1, createdAt: created)
        priya = Person(name: "Priya", avatarSeed: 2, createdAt: created)
        try services.people.add(sam)
        try services.people.add(priya)
        group = SplitGroup(name: "Flat", currencyCode: "USD", memberIDs: [me.id, sam.id, priya.id])
        try services.groups.create(group)
    }

    @discardableResult
    func addExpense(_ title: String = "Dinner", cents: Int64 = 3000) throws -> Expense {
        let expense = Expense(
            groupID: group.id, title: title, total: usdAmount(cents), date: device.clock.start,
            paidBy: me.id, split: .equal(participants: [me.id, sam.id, priya.id])
        )
        try device.services.expenses.add(expense)
        return expense
    }

    /// A comment, a payment and a recurring template, so every record type is present.
    func addEverythingElse() throws {
        let expense = try addExpense("Taxi", cents: 1500)
        let services = device.services
        try services.comments.add(ExpenseComment(
            groupID: group.id, expenseID: expense.id, authorID: me.id, text: "Worth it", createdAt: device.clock.start
        ))
        try services.payments.record(Payment(
            groupID: group.id, payer: sam.id, receiver: me.id, amount: usdAmount(500), date: device.clock.start
        ))
        try services.recurring.add(RecurringExpense(
            groupID: group.id, title: "Rent", total: usdAmount(90_000), category: .rent,
            payers: [me.id: usdAmount(90_000)], split: .equal(participants: [me.id, sam.id, priya.id]),
            rule: RecurrenceRule(
                frequency: .monthly, startDate: device.clock.start, timeZone: TimeZone(identifier: "UTC")!
            )
        ))
    }

    var zone: String { group.id.description }
}
