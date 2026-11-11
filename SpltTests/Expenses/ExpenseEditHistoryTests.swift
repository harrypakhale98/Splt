import Foundation
import SpltCore
import Testing
@testable import Splt

/// The event as version 1.0 declares it, to check what a 1.0 device reads and writes.
private struct ExpenseReferenceV1: Codable, Equatable {
    var id: ExpenseID
    var title: String
    var amount: Money
}

private enum ActivityEventV1: Codable, Equatable {
    case expenseAdded(ExpenseReferenceV1)
    case expenseEdited(ExpenseReferenceV1)
}

@MainActor
@Suite("Expense edit history")
struct ExpenseEditHistoryTests {
    private let us = Locale(identifier: "en_US")

    // MARK: Recording

    @Test func anEditRecordsEveryChangedFieldWithItsValues() throws {
        let fixture = try Fixture()
        let original = try fixture.addExpense("Dinner", cents: 3000)
        var edited = original
        edited.title = "Team dinner"
        edited.total = usdAmount(3600)
        edited.date = fixture.clock.start.addingTimeInterval(86_400)
        edited.category = .dining
        edited.payers = [fixture.sam.id: usdAmount(3600)]
        edited.split = .equal(participants: [fixture.me.id, fixture.sam.id])
        edited.note = "Birthday"
        let extras = ExpenseExtras(
            receiptFileName: "r.jpg", location: ExpenseLocation(name: "Luigi's", latitude: 1, longitude: 2),
            recurrence: RecurrenceRule(frequency: .monthly, startDate: fixture.clock.start, timeZone: TimeZone(identifier: "UTC")!)
        )
        try fixture.services.expenses.update(edited, extras: extras)

        let edit = try #require(try fixture.services.expenses.edits(of: original.id).last)
        let changes = edit.editChanges
        #expect(changes.map(\.field) == [.title, .total, .date, .category, .payers, .split, .note, .receipt, .location, .recurrence])
        let byField = Dictionary(uniqueKeysWithValues: changes.map { ($0.field, $0) })
        #expect(byField[.title]?.before?.text == "Dinner")
        #expect(byField[.total]?.before == ExpenseChangeValue(minorUnits: 3000, currencyCode: "USD"))
        #expect(byField[.total]?.after?.money == usdAmount(3600))
        #expect(byField[.date]?.after?.dateValue == edited.date)
        #expect(byField[.category]?.after?.text == "dining")
        #expect(byField[.payers]?.after?.payments.map(\.person) == [fixture.sam.id])
        #expect(byField[.split]?.after?.personIDs == [fixture.me.id, fixture.sam.id].sorted())
        #expect(byField[.note]?.before == nil)
        #expect(byField[.receipt]?.before == nil && byField[.receipt]?.after != nil)
        #expect(byField[.location]?.after?.text == "Luigi's")
        #expect(byField[.recurrence]?.after?.text == "monthly")
        #expect(edit.actorID == fixture.me.id)
    }

    @Test func theOldHistoryIsStillWrittenUnderTheSameID() throws {
        let fixture = try Fixture()
        var expense = try fixture.addExpense("Dinner", cents: 3000)
        expense.title = "Lunch"
        try fixture.services.expenses.update(expense)
        let embedded = try #require(try fixture.services.expenses.details(id: expense.id)?.history.first)
        #expect(embedded.previousTitle == "Dinner")
        #expect(try fixture.services.expenses.edits(of: expense.id).map(\.id) == [embedded.id])
    }

    @Test func editsOfOtherExpensesAreNotListed() throws {
        let fixture = try Fixture()
        var first = try fixture.addExpense("Dinner")
        var second = try fixture.addExpense("Taxi")
        first.title = "Lunch"
        second.title = "Bus"
        try fixture.services.expenses.update(first)
        try fixture.services.expenses.update(second)
        #expect(try fixture.services.expenses.edits(of: first.id).count == 1)
    }

    // MARK: Compatibility

    @Test func anEventFromVersionOneStillReads() throws {
        let reference = ExpenseReferenceV1(id: ExpenseID(), title: "Dinner", amount: usdAmount(3000))
        let data = RecordCoding.encode(ActivityEventV1.expenseEdited(reference))
        let event = try RecordCoding.decode(ActivityEvent.self, from: data)
        #expect(event == .expenseEdited(ExpenseReference(id: reference.id, title: "Dinner", amount: usdAmount(3000))))
    }

    @Test func versionOneReadsAnEditWithChanges() throws {
        var reference = ExpenseReference(id: ExpenseID(), title: "Dinner", amount: usdAmount(3600))
        reference.changes = ExpenseChanges([
            ExpenseChange(field: .total, before: .money(usdAmount(3000)), after: .money(usdAmount(3600)))
        ])
        let data = RecordCoding.encode(ActivityEvent.expenseEdited(reference))
        let old = try RecordCoding.decode(ActivityEventV1.self, from: data)
        #expect(old == .expenseEdited(ExpenseReferenceV1(id: reference.id, title: "Dinner", amount: usdAmount(3600))))
        #expect(try RecordCoding.decode(ActivityEvent.self, from: data) == .expenseEdited(reference))
    }

    @Test func otherEventsAreStoredExactlyAsBefore() {
        let id = ExpenseID()
        let new = RecordCoding.encode(ActivityEvent.expenseAdded(ExpenseReference(id: id, title: "Dinner", amount: usdAmount(3000))))
        let old = RecordCoding.encode(ActivityEventV1.expenseAdded(ExpenseReferenceV1(id: id, title: "Dinner", amount: usdAmount(3000))))
        #expect(new == old)
    }

    @Test func aChangeFromALaterVersionIsSkipped() throws {
        let id = ExpenseID()
        let json = """
        {"expenseEdited":{"_0":{"id":"\(id.description)","title":"Dinner","amount":\(String(decoding: RecordCoding.encode(usdAmount(3000)), as: UTF8.self)),
        "changes":[{"field":"mood","after":{"text":"happy"}},{"field":"title","before":{"text":"Lunch"},"after":{"text":"Dinner"}},7]}}}
        """
        let event = try RecordCoding.decode(ActivityEvent.self, from: Data(json.utf8))
        let entry = ActivityEntry(event: event)
        #expect(entry.editChanges.map(\.field) == [.title])
    }

    // MARK: Lines

    private func builder(_ fixture: Fixture, now: Date) -> ExpenseHistoryBuilder {
        ExpenseHistoryBuilder(locale: us, now: now, name: { id in
            id == fixture.me.id ? "You" : id == fixture.sam.id ? "Sam" : "Priya"
        }, groupName: { _ in "Trip" })
    }

    @Test func linesSayWhatChangedFromWhatToWhat() throws {
        let fixture = try Fixture()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        var reference = ExpenseReference(id: ExpenseID(), title: "Dinner", amount: usdAmount(3600))
        reference.changes = ExpenseChanges([
            ExpenseChange(field: .total, before: .money(usdAmount(3000)), after: .money(usdAmount(3600))),
            ExpenseChange(field: .receipt, before: nil, after: .present),
            ExpenseChange(field: .payers, before: .payers([fixture.me.id: usdAmount(3000)], currencyCode: "USD"),
                          after: .payers([fixture.sam.id: usdAmount(3600)], currencyCode: "USD"))
        ])
        let edit = ActivityEntry(actorID: fixture.sam.id, event: .expenseEdited(reference), createdAt: date)
        var text = builder(fixture, now: date)
        text.calendar = calendar
        let lines = text.lines(edits: [edit], embedded: []).map(\.text)
        #expect(lines == [
            "Sam changed the total from $30.00 to $36.00 · Nov 2",
            "Sam added a receipt · Nov 2",
            "Sam changed who paid from You to Sam · Nov 2"
        ])
    }

    @Test func editsFromBeforeVersionOneOneFallBackToTheOldHistory() throws {
        let fixture = try Fixture()
        let now = fixture.clock.start.addingTimeInterval(86_400 * 3)
        let shared = UUID()
        var reference = ExpenseReference(id: ExpenseID(), title: "Dinner", amount: usdAmount(3000))
        reference.changes = ExpenseChanges([ExpenseChange(field: .title, before: .text("Lunch"), after: .text("Dinner"))])
        let new = ActivityEntry(id: shared, actorID: fixture.me.id, event: .expenseEdited(reference), createdAt: now)
        let embedded = [
            ExpenseEditEntry(date: fixture.clock.start, editor: fixture.sam.id, changedFields: [.title], previousTitle: "Brunch"),
            ExpenseEditEntry(id: shared, date: now, editor: fixture.me.id, changedFields: [.title], previousTitle: "Lunch")
        ]
        let lines = builder(fixture, now: now).lines(edits: [new], embedded: embedded)
        #expect(lines.count == 2)
        #expect(lines[0].text.hasPrefix("You changed the title from \u{201C}Lunch\u{201D} to \u{201C}Dinner\u{201D} · "))
        #expect(lines[1].text.hasPrefix("Sam changed the title · "))
        #expect(lines[1].detail == "Title was Brunch")
    }

    @Test func theDetailScreenShowsTheFullLine() throws {
        let fixture = try Fixture()
        var expense = try fixture.addExpense("Dinner", cents: 3000)
        expense.total = usdAmount(4500)
        expense.payers = [fixture.me.id: usdAmount(4500)]
        try fixture.services.expenses.update(expense)
        let model = ExpenseDetailModel(expenseID: expense.id, services: fixture.services, locale: us)
        let lines = model.historyLines(locale: us).map(\.text)
        #expect(lines.contains { $0.hasPrefix("You changed the total from $30.00 to $45.00 · ") })
        // the one payer's amount follows the total, so it gets no line of its own
        #expect(lines.count == 1)
    }
}
