import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Activity repository")
struct ActivityRepositoryTests {
    @Test func newGroupsStartWithACreatedEvent() throws {
        let fixture = try Fixture()
        let entries = try fixture.services.activity.entries(limit: 10)
        #expect(entries.map(\.event) == [.groupCreated(name: "Flat")])
        #expect(entries[0].groupID == fixture.group.id)
    }

    @Test func entriesAreNewestFirstAndLimited() throws {
        let fixture = try Fixture()
        try fixture.addExpense("One")
        try fixture.addExpense("Two")
        let titles = try fixture.services.activity.entries(limit: 2).compactMap { entry -> String? in
            if case .expenseAdded(let reference) = entry.event { reference.title } else { nil }
        }
        #expect(titles == ["Two", "One"])
    }

    @Test func entriesCanBeFilteredByGroup() throws {
        let fixture = try Fixture()
        let other = SplitGroup(name: "Other", currencyCode: "USD", memberIDs: [fixture.me.id])
        try fixture.services.groups.create(other)
        #expect(try fixture.services.activity.entries(in: other.id, limit: 10).count == 1)
        #expect(try fixture.services.activity.entries(in: fixture.group.id, limit: 10).count == 1)
        #expect(try fixture.services.activity.entries(limit: 10).count == 2)
    }

    @Test func everyKindOfChangeLeavesAnEntry() throws {
        let fixture = try Fixture()
        let services = fixture.services
        var expense = try fixture.addExpense()
        expense.note = "changed"
        try services.expenses.update(expense)
        try services.expenses.delete(id: expense.id)
        try services.expenses.restore(id: expense.id)
        let payment = try services.payments.settle(
            Debt(debtor: fixture.sam.id, creditor: fixture.me.id, amount: usd(100)), in: fixture.group.id, date: fixture.clock.start
        )
        try services.payments.undo(id: payment.id)
        try services.groups.setArchived(true, id: fixture.group.id)
        try services.groups.setArchived(false, id: fixture.group.id)
        let alex = Person(name: "Alex")
        try services.people.add(alex)
        try services.groups.addMember(alex.id, to: fixture.group.id)
        try services.groups.removeMember(alex.id, from: fixture.group.id)
        try services.comments.add(ExpenseComment(groupID: fixture.group.id, authorID: fixture.me.id, text: "hi"))

        let kinds = Set(try services.activity.entries(limit: 100).map(\.event.kind))
        #expect(kinds == [
            .groupCreated, .expenseAdded, .expenseEdited, .expenseDeleted, .expenseRestored,
            .paymentRecorded, .paymentUndone, .groupArchived, .groupRestored, .memberAdded, .memberRemoved, .commentAdded
        ])
    }

    @Test func readStateCanBeTrackedPerEntryOrAllAtOnce() throws {
        let fixture = try Fixture()
        try fixture.addExpense()
        try fixture.addExpense("Second")
        let services = fixture.services
        #expect(try services.activity.unreadCount() == 3)
        let first = try #require(try services.activity.entries(limit: 10).first)
        try services.activity.markRead(ids: [first.id])
        #expect(try services.activity.unreadCount() == 2)
        try services.activity.markAllRead()
        #expect(try services.activity.unreadCount() == 0)
        #expect(try services.activity.entries(limit: 10).allSatisfy(\.isRead))
    }

    @Test func markingReadDoesNotCreateSyncWork() throws {
        let fixture = try Fixture()
        let tracker = fixture.services.makeChangeTracker()
        for change in try tracker.pendingChanges() {
            let payload = try #require(try tracker.payload(recordType: change.recordType, recordName: change.recordName))
            try tracker.markSynced(recordType: change.recordType, recordName: change.recordName, sentModifiedAt: payload.modifiedAt, systemFields: nil)
        }
        try fixture.services.activity.markAllRead()
        #expect(try tracker.pendingChanges().isEmpty)
    }
}
