import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

@MainActor
@Suite("Sync fields")
struct SyncFieldsTests {
    private let when = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func typedAccessorsReadWhatWasSet() {
        var fields = SyncFields()
        let id = UUID()
        fields.set("s", "text")
        fields.set("i", Int64(42))
        fields.set("d", 1.5)
        fields.set("t", when)
        fields.set("b", Data([1, 2]))
        fields.set("flag", true)
        fields.set("u", id)
        #expect(fields.string("s") == "text")
        #expect(fields.int("i") == 42)
        #expect(fields.double("d") == 1.5)
        #expect(fields.date("t") == when)
        #expect(fields.data("b") == Data([1, 2]))
        #expect(fields.bool("flag"))
        #expect(fields.uuid("u") == id)
    }

    @Test func settingNilRemovesTheKey() {
        var fields = SyncFields()
        fields.set("s", "text")
        fields.set("s", String?.none)
        #expect(fields.string("s") == nil)
        #expect(fields.values.isEmpty)
    }

    @Test func wrongTypeReadsAsNil() {
        var fields = SyncFields()
        fields.set("s", "text")
        #expect(fields.int("s") == nil)
        #expect(!fields.bool("s"))
    }

    @Test func canonicalTextIgnoresInsertionOrder() {
        var first = SyncFields()
        first.set("a", "1")
        first.set("b", Int64(2))
        var second = SyncFields()
        second.set("b", Int64(2))
        second.set("a", "1")
        #expect(first.canonicalText == second.canonicalText)
    }

    /// Copies fields from one record of each type into a blank one and expects the same fields back.
    @Test func everyRecordTypeSurvivesAFieldRoundTrip() throws {
        let a = PersonID()
        let group = GroupID()
        let expenseRecord = ExpenseRecord(Expense(
            groupID: group, title: "Dinner", total: usd(3000), date: when, category: .dining, paidBy: a,
            split: .equal(participants: [a]), note: "n"
        ), extras: ExpenseExtras(
            receiptFileName: "r.jpg", location: ExpenseLocation(name: "x", latitude: 1, longitude: 2),
            recurrence: RecurrenceRule(frequency: .daily, startDate: when), recurringExpenseID: UUID()
        ), createdBy: a, createdAt: when)
        expenseRecord.history = [ExpenseEditEntry(date: when, changedFields: [.note])]

        let commentRecord = CommentRecord(ExpenseComment(
            groupID: group, expenseID: ExpenseID(), authorID: a, text: "hi", createdAt: when, editedAt: when,
            reactions: [CommentReaction(person: a, emoji: "x")]
        ))
        let templateRecord = RecurringExpenseRecord(RecurringExpense(
            groupID: group, title: "Rent", total: usd(1000), payers: [a: usd(1000)], split: .equal(participants: [a]),
            rule: RecurrenceRule(frequency: .monthly, startDate: when), lastCreatedOccurrence: when, createdBy: a
        ))

        func check<R: SyncTracked>(_ original: R, _ blank: R) {
            blank.applySyncFields(original.syncFields)
            #expect(blank.syncFields == original.syncFields)
        }
        check(PersonRecord(Person(name: "A", contactHint: "x", claimedByCloudUserID: "y", avatarSeed: 3, createdAt: when)),
              PersonRecord.blank(recordName: UUID().uuidString))
        check(GroupRecord(SplitGroup(
            name: "G", currencyCode: "USD", memberIDs: [a], tripStart: when, tripEnd: when,
            pinnedRate: PinnedRate(from: "USD", to: "EUR", rate: 0.9), createdAt: when
        )), GroupRecord.blank(recordName: UUID().uuidString))
        check(expenseRecord, ExpenseRecord.blank(recordName: UUID().uuidString))
        check(PaymentRecord(Payment(groupID: group, payer: a, receiver: PersonID(), amount: usd(5), date: when, note: "n")),
              PaymentRecord.blank(recordName: UUID().uuidString))
        check(commentRecord, CommentRecord.blank(recordName: UUID().uuidString))
        check(ActivityRecord(ActivityEntry(groupID: group, actorID: a, event: .groupArchived, createdAt: when)),
              ActivityRecord.blank(recordName: UUID().uuidString))
        check(templateRecord, RecurringExpenseRecord.blank(recordName: UUID().uuidString))
    }

    @Test func activityReadFlagStaysOutOfSyncFields() {
        let record = ActivityRecord(ActivityEntry(event: .groupArchived, isRead: true))
        let fields = record.syncFields
        record.isRead = false
        #expect(record.syncFields == fields)
    }

    @Test func recordNameIsTheIDAndZoneIsTheGroup() {
        let group = GroupID()
        let record = ExpenseRecord(Expense(
            groupID: group, title: "x", total: usd(1), date: when, paidBy: PersonID(), split: .equal(participants: [PersonID()])
        ))
        #expect(record.recordName == record.id.uuidString)
        #expect(record.zoneName == group.description)
        #expect(PersonRecord(Person(name: "A")).zoneName == nil)
    }
}
