import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

/// Two in-memory devices that exchange payloads through the tracker, the way the sync engine will.
@MainActor
@Suite("Two device convergence")
struct SyncConvergenceTests {
    @MainActor
    private struct Device {
        let services: DataServices
        let clock: TestClock

        var tracker: ChangeTracker { services.makeChangeTracker() }

        init(start: TimeInterval) throws {
            clock = TestClock(start: Date(timeIntervalSince1970: start))
            services = try DataServices.inMemory(now: clock.reading)
        }
    }

    private let a: Device
    private let b: Device
    private let group: SplitGroup
    private let sam = Person(name: "Sam", avatarSeed: 1)
    private let me: Person

    init() throws {
        a = try Device(start: 1_750_000_000)
        b = try Device(start: 1_750_000_000)
        me = try a.services.people.ensureMe(name: "Me")
        try a.services.people.add(sam)
        group = SplitGroup(name: "Flat", currencyCode: "USD", memberIDs: [me.id, sam.id])
        try a.services.groups.create(group)
        try push(from: a, to: b)
    }

    /// Uploads everything pending on `source` and applies it on `target`, then confirms the upload.
    private func push(from source: Device, to target: Device) throws {
        let tracker = source.tracker
        for change in try tracker.pendingChanges() {
            guard let payload = try tracker.payload(recordType: change.recordType, recordName: change.recordName) else { continue }
            switch change.operation {
            case .save:
                try target.tracker.applyRemote(payload)
            case .delete:
                try target.tracker.applyRemoteDeletion(
                    recordType: change.recordType, recordName: change.recordName, at: payload.deletedAt
                )
            }
            try tracker.markSynced(
                recordType: change.recordType, recordName: change.recordName,
                sentModifiedAt: payload.modifiedAt, systemFields: Data([1])
            )
        }
    }

    private func exchange() throws {
        try push(from: a, to: b)
        try push(from: b, to: a)
        try push(from: a, to: b)
    }

    private func expense() -> Expense {
        Expense(
            groupID: group.id, title: "Dinner", total: usdAmount(3000), date: a.clock.start,
            paidBy: me.id, split: .equal(participants: [me.id, sam.id])
        )
    }

    private func titles(on device: Device) throws -> [String] {
        try device.services.expenses.expenses(in: group.id, includeDeleted: true).map(\.title)
    }

    @Test func aNewExpenseReachesTheOtherDevice() throws {
        let created = expense()
        try a.services.expenses.add(created)
        try exchange()
        #expect(try b.services.expenses.expense(id: created.id) == created)
        #expect(try b.tracker.pendingChanges().isEmpty)
        #expect(try a.tracker.pendingChanges().isEmpty)
    }

    @Test func balancesMatchOnBothDevicesAfterSync() throws {
        try a.services.expenses.add(expense())
        try exchange()
        let onA = try a.services.groups.balances(for: group.id).netBalances
        let onB = try b.services.groups.balances(for: group.id).netBalances
        #expect(onA == onB)
        #expect(!onA.isEmpty)
    }

    @Test func theLaterOfTwoConflictingEditsWinsOnBothDevices() throws {
        var created = expense()
        try a.services.expenses.add(created)
        try exchange()

        created.title = "Edited on A"
        try a.services.expenses.update(created)
        b.clock.advance(by: 100)
        created.title = "Edited on B"
        try b.services.expenses.update(created)
        try exchange()

        #expect(try titles(on: a) == ["Edited on B"])
        #expect(try titles(on: b) == ["Edited on B"])
        #expect(try a.tracker.pendingChanges().isEmpty)
        #expect(try b.tracker.pendingChanges().isEmpty)
    }

    @Test func theResultDoesNotDependOnWhoSyncsFirst() throws {
        var created = expense()
        try a.services.expenses.add(created)
        try exchange()
        created.title = "Edited on A"
        try a.services.expenses.update(created)
        a.clock.advance(by: 100)
        created.title = "Edited later on A"
        try a.services.expenses.update(created)
        created.title = "Edited on B"
        try b.services.expenses.update(created)

        try push(from: b, to: a)
        try push(from: a, to: b)
        try push(from: b, to: a)
        #expect(try titles(on: a) == ["Edited later on A"])
        #expect(try titles(on: b) == ["Edited later on A"])
    }

    @Test func aDeleteBeatsAnEditMadeEarlierOnTheOtherDevice() throws {
        var created = expense()
        try a.services.expenses.add(created)
        try exchange()

        created.title = "Edited on B"
        try b.services.expenses.update(created)
        a.clock.advance(by: 100)
        try a.services.expenses.delete(id: created.id)
        try exchange()

        #expect(try a.services.expenses.expenses(in: group.id).isEmpty)
        #expect(try b.services.expenses.expenses(in: group.id).isEmpty)
    }

    @Test func anEditMadeAfterTheDeleteBringsTheExpenseBack() throws {
        var created = expense()
        try a.services.expenses.add(created)
        try exchange()

        try a.services.expenses.delete(id: created.id)
        b.clock.advance(by: 100)
        created.title = "Still needed"
        try b.services.expenses.update(created)
        try exchange()

        #expect(try a.services.expenses.expense(id: created.id)?.isDeleted == false)
        #expect(try titles(on: b) == ["Still needed"])
        #expect(try titles(on: a) == ["Still needed"])
    }

    @Test func undoingADeleteOnOneDeviceRestoresItEverywhere() throws {
        let created = expense()
        try a.services.expenses.add(created)
        try exchange()
        try a.services.expenses.delete(id: created.id)
        try exchange()
        #expect(try b.services.expenses.expenses(in: group.id).isEmpty)
        try b.services.expenses.restore(id: created.id)
        try exchange()
        #expect(try a.services.expenses.expenses(in: group.id).count == 1)
    }

    @Test func syncedActivityShowsUpOnTheOtherDevice() throws {
        try a.services.expenses.add(expense())
        try exchange()
        let kinds = try b.services.activity.entries(in: group.id, limit: 10).map(\.event.kind)
        #expect(kinds.contains(.expenseAdded))
        #expect(kinds.contains(.groupCreated))
    }

    @Test func readStateStaysOnTheDevice() throws {
        try a.services.expenses.add(expense())
        try exchange()
        try a.services.activity.markAllRead()
        #expect(try a.services.activity.unreadCount() == 0)
        #expect(try b.services.activity.unreadCount() > 0)
    }

    @Test func aRecordCannotMakeSomeoneTheLocalMe() throws {
        var fields = SyncFields()
        fields.set("name", "Sam")
        fields.set("kind", PersonKind.me.rawValue)
        try a.tracker.applyRemote(SyncPayload(
            recordType: .person, recordName: sam.id.description,
            modifiedAt: a.clock.start.addingTimeInterval(1_000), fields: fields
        ))
        #expect(try a.services.people.person(id: sam.id)?.kind == .friend)
        #expect(try a.services.people.me()?.id == me.id)
    }

    // MARK: Recurring expenses made before the first fetch

    private func rentTemplate() throws -> RecurringExpense {
        let template = RecurringExpense(
            groupID: group.id, title: "Rent", total: usdAmount(90_000), category: .rent,
            payers: [me.id: usdAmount(90_000)], split: .equal(participants: [me.id, sam.id]),
            rule: RecurrenceRule(frequency: .monthly, startDate: a.clock.start, timeZone: TimeZone(identifier: "UTC")!),
            createdAt: a.clock.start
        )
        try a.services.recurring.add(template)
        try exchange()
        return template
    }

    @Test func anOccurrenceMadeLateDoesNotUndoAnEditMadeElsewhere() throws {
        _ = try rentTemplate()
        var made = try #require(try a.services.recurring.createDueExpenses(through: a.clock.start).first)
        made.title = "Rent and bills"
        made.note = "Edited on the first phone"
        try a.services.expenses.update(made, extras: nil)
        // the second phone opens days later and makes its own copy before it has fetched anything
        b.clock.advance(by: 86_400 * 3)
        #expect(try b.services.recurring.createDueExpenses(through: a.clock.start).count == 1)
        try exchange()
        #expect(try a.services.expenses.expense(id: made.id)?.title == "Rent and bills")
        #expect(try b.services.expenses.expense(id: made.id)?.title == "Rent and bills")
    }

    @Test func anOccurrenceMadeLateDoesNotBringBackADeleteMadeElsewhere() throws {
        _ = try rentTemplate()
        let made = try #require(try a.services.recurring.createDueExpenses(through: a.clock.start).first)
        try a.services.expenses.delete(id: made.id)
        b.clock.advance(by: 86_400 * 3)
        _ = try b.services.recurring.createDueExpenses(through: a.clock.start)
        try exchange()
        #expect(try a.services.expenses.expense(id: made.id)?.deletedAt != nil)
        #expect(try b.services.expenses.expense(id: made.id)?.deletedAt != nil)
    }

    @Test func makingOccurrencesDoesNotUndoATemplateEditMadeElsewhere() throws {
        var template = try rentTemplate()
        template.title = "Rent and bills"
        try a.services.recurring.update(template)
        b.clock.advance(by: 86_400 * 3)
        _ = try b.services.recurring.createDueExpenses(through: a.clock.start)
        try exchange()
        #expect(try b.services.recurring.templates(in: group.id).first?.title == "Rent and bills")
        #expect(try a.services.recurring.templates(in: group.id).first?.title == "Rent and bills")
    }

    @Test func theSameOccurrenceMadeOnBothPhonesIsAnnouncedOnce() throws {
        _ = try rentTemplate()
        _ = try a.services.recurring.createDueExpenses(through: a.clock.start)
        b.clock.advance(by: 500)
        _ = try b.services.recurring.createDueExpenses(through: a.clock.start)
        try exchange()
        for device in [a, b] {
            let added = try device.services.activity.entries(in: group.id, limit: 20).filter { $0.event.kind == .expenseAdded }
            #expect(added.count == 1)
        }
    }

    @Test func theSameOccurrenceMadeOnBothPhonesEndsUpTheSame() throws {
        _ = try rentTemplate()
        let made = try #require(try a.services.recurring.createDueExpenses(through: a.clock.start).first)
        b.clock.advance(by: 500)
        _ = try b.services.recurring.createDueExpenses(through: a.clock.start)
        try exchange()
        let first = try a.tracker.payload(recordType: .expense, recordName: made.id.description)
        let second = try b.tracker.payload(recordType: .expense, recordName: made.id.description)
        #expect(first?.fields == second?.fields)
        #expect(first?.modifiedAt == second?.modifiedAt)
    }

    @Test func theOwnersProfileArrivesAsAFriendNotAsMe() throws {
        let received = try #require(try b.services.people.person(id: me.id))
        #expect(received.kind == .friend)
        #expect(try b.services.people.me() == nil)
    }

    @Test func deletingAGroupOnOneDeviceRemovesItOnTheOther() throws {
        try a.services.expenses.add(expense())
        try exchange()
        try a.services.groups.delete(id: group.id)
        try exchange()
        #expect(try b.services.groups.group(id: group.id) == nil)
        #expect(try b.services.groups.groups(includeArchived: true).isEmpty)
    }
}
