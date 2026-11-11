import Foundation
import SpltCore
import SwiftData
import Testing
@testable import Splt

@MainActor
@Suite("Record mapping")
struct RecordMappingTests {
    private let when = Date(timeIntervalSince1970: 1_750_000_000)
    private let a = PersonID()
    private let b = PersonID()
    private let c = PersonID()
    private let group = GroupID()

    private func expense(split: SplitDefinition, payers: [PersonID: Money]? = nil, total: Money = usdAmount(3000)) -> Expense {
        Expense(
            groupID: group, title: "Dinner, with \"quotes\"", total: total, date: when, category: .dining,
            payers: payers ?? [a: total], split: split, note: "second line\nof the note"
        )
    }

    @Test func personRoundTrips() {
        let person = Person(
            name: "Maya", contactHint: "maya@example.com", kind: .placeholder,
            claimedByCloudUserID: "_abc", avatarSeed: 7, createdAt: when
        )
        #expect(Person(PersonRecord(person)) == person)
    }

    @Test func groupRoundTripsWithPinnedRate() {
        let value = SplitGroup(
            name: "Lisbon", symbol: "airplane", currencyCode: "eur", kind: .trip, memberIDs: [a, b, c],
            simplifiesDebts: false, isArchived: true, tripStart: when, tripEnd: when.addingTimeInterval(86_400),
            pinnedRate: PinnedRate(from: "usd", to: "eur", rate: Decimal(string: "0.9231")!), createdAt: when
        )
        let record = GroupRecord(value)
        #expect(SplitGroup(record) == value)
        #expect(record.currencyCode == "EUR")
        #expect(record.zoneName == value.id.description)
    }

    @Test(arguments: [
        "equal", "exact", "percentages", "shares", "adjustments", "itemized"
    ])
    func expenseRoundTripsForEverySplit(kind: String) throws {
        let split: SplitDefinition
        switch kind {
        case "equal": split = .equal(participants: [a, b, c])
        case "exact": split = .exact(amounts: [a: usdAmount(1000), b: usdAmount(2000)])
        case "percentages": split = .percentages(basisPoints: [a: 2500, b: 7500])
        case "shares": split = .shares(weights: [a: 2, b: 1])
        case "adjustments": split = .adjustments(participants: [a, b], adjustments: [b: usdAmount(500)])
        default:
            split = .itemized(ItemizedSplit(
                items: [SplitItem(name: "Pizza", amount: usdAmount(2000), assignees: [a, b]),
                        SplitItem(name: "Soda", amount: usdAmount(800), assignees: [a])],
                tax: usdAmount(100), tip: usdAmount(100)
            ))
        }
        let original = expense(split: split)
        let record = ExpenseRecord(original)
        #expect(try Expense(record) == original)
    }

    @Test func expenseKeepsMultiplePayersAndRefundSigns() throws {
        let multi = expense(split: .equal(participants: [a, b]), payers: [a: usdAmount(1000), b: usdAmount(2000)])
        #expect(try Expense(ExpenseRecord(multi)) == multi)

        let refund = expense(split: .equal(participants: [a, b]), payers: [a: usdAmount(-4000)], total: usdAmount(-4000))
        #expect(try Expense(ExpenseRecord(refund)) == refund)
    }

    @Test func expenseKeepsTheSoftDeleteDate() throws {
        var deleted = expense(split: .equal(participants: [a, b]))
        deleted.deletedAt = when
        let record = ExpenseRecord(deleted)
        #expect(record.deletedAt == when)
        #expect(try Expense(record) == deleted)
    }

    @Test func updateCopiesCoreFieldsButNotTheTombstone() throws {
        var original = expense(split: .equal(participants: [a, b]))
        let record = ExpenseRecord(original)
        record.deletedAt = when
        original.title = "Lunch"
        original.total = usdAmount(900)
        original.payers = [a: usdAmount(900)]
        record.update(from: original)
        #expect(record.title == "Lunch")
        #expect(record.totalMinorUnits == 900)
        #expect(record.deletedAt == when)
    }

    @Test func extrasRoundTrip() {
        let rule = RecurrenceRule(frequency: .monthly, startDate: when, timeZone: TimeZone(identifier: "Europe/Lisbon")!)
        let extras = ExpenseExtras(
            receiptFileName: "receipt-1.jpg",
            location: ExpenseLocation(name: "Time Out Market", latitude: 38.7066, longitude: -9.1459),
            recurrence: rule, recurringExpenseID: UUID()
        )
        let record = ExpenseRecord(expense(split: .equal(participants: [a])), extras: extras)
        #expect(record.extras == extras)
        record.apply(ExpenseExtras())
        #expect(record.extras == ExpenseExtras())
    }

    @Test func historyRoundTrips() {
        let record = ExpenseRecord(expense(split: .equal(participants: [a])))
        let entry = ExpenseEditEntry(
            date: when, editor: a, changedFields: [.title, .total], previousTitle: "Old", previousTotal: usdAmount(100)
        )
        record.history = [entry]
        #expect(record.history == [entry])
        #expect(record.details.history == [entry])
    }

    @Test func unreadableBlobsThrowCorruptRecord() {
        let record = ExpenseRecord(expense(split: .equal(participants: [a])))
        record.splitData = Data("not json".utf8)
        #expect(throws: DataError.corruptRecord("expense \(record.recordName)")) {
            try Expense(record)
        }
    }

    @Test func paymentRoundTrips() {
        let payment = Payment(
            groupID: group, payer: a, receiver: b, amount: usdAmount(2500), date: when, note: "Cash", deletedAt: when
        )
        #expect(Payment(PaymentRecord(payment)) == payment)
    }

    @Test func commentRoundTrips() {
        let comment = ExpenseComment(
            groupID: group, expenseID: ExpenseID(), authorID: a, text: "Thanks!", createdAt: when,
            editedAt: when, reactions: [CommentReaction(person: b, emoji: "\u{2764}\u{FE0F}")]
        )
        #expect(ExpenseComment(CommentRecord(comment)) == comment)
    }

    @Test func activityRoundTripsEveryEventShape() {
        let ref = ExpenseReference(id: ExpenseID(), title: "Dinner", amount: usdAmount(3000))
        let pay = PaymentReference(id: PaymentID(), payer: a, receiver: b, amount: usdAmount(500))
        let events: [ActivityEvent] = [
            .groupCreated(name: "Flat"), .groupRenamed(from: "A", to: "B"), .groupArchived, .groupRestored,
            .memberAdded(a), .memberRemoved(b), .expenseAdded(ref), .expenseEdited(ref), .expenseDeleted(ref),
            .expenseRestored(ref), .paymentRecorded(pay), .paymentUndone(pay),
            .commentAdded(expense: ref, text: "hi"), .commentAdded(expense: nil, text: "hi"),
            .expensesImported(expenses: 4, payments: 1), .reminderSent(to: b, amounts: [usdAmount(1200)])
        ]
        for event in events {
            let entry = ActivityEntry(groupID: group, actorID: a, event: event, createdAt: when, isRead: true)
            let record = ActivityRecord(entry)
            #expect(ActivityEntry(record) == entry)
            #expect(record.kindRaw == event.kind.rawValue)
        }
        #expect(Set(events.map(\.kind)) == Set(ActivityKind.allCases))
    }

    @Test func unknownActivityEventsAreSkippedNotFatal() {
        let record = ActivityRecord(kindRaw: "futureKind", eventData: Data(#"{"futureKind":{}}"#.utf8))
        #expect(ActivityEntry(record) == nil)
    }

    @Test func recurringExpenseRoundTrips() throws {
        let rule = RecurrenceRule(frequency: .weekly, startDate: when, endDate: when.addingTimeInterval(86_400 * 90), maxOccurrences: 8)
        let template = RecurringExpense(
            groupID: group, title: "Cleaner", total: usdAmount(6000), category: .home, payers: [a: usdAmount(6000)],
            split: .equal(participants: [a, b]), note: "weekly", rule: rule, lastCreatedOccurrence: when,
            isActive: false, createdBy: a, createdAt: when
        )
        #expect(try RecurringExpense(RecurringExpenseRecord(template)) == template)
    }

    @Test func templateMakesAnExpenseForAnOccurrence() {
        let rule = RecurrenceRule(frequency: .monthly, startDate: when)
        let template = RecurringExpense(
            groupID: group, title: "Rent", total: usdAmount(90_000), payers: [a: usdAmount(90_000)],
            split: .equal(participants: [a, b]), rule: rule
        )
        let next = when.addingTimeInterval(86_400 * 30)
        let made = template.expense(on: next)
        #expect(made.date == next)
        #expect(made.groupID == group)
        #expect(made.title == "Rent")
    }
}
