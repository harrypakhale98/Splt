import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Recurring expenses")
struct RecurringExpenseRepositoryTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func template(_ fixture: Fixture, frequency: RecurrenceFrequency = .monthly, startingDaysAgo: Int = 0) -> RecurringExpense {
        let start = fixture.clock.start.addingTimeInterval(TimeInterval(-startingDaysAgo) * 86_400)
        return RecurringExpense(
            groupID: fixture.group.id, title: "Rent", total: usd(90_000), category: .rent,
            payers: [fixture.me.id: usd(90_000)], split: .equal(participants: fixture.everyone),
            rule: RecurrenceRule(frequency: frequency, startDate: start, timeZone: utc)
        )
    }

    @Test func storesAndListsTemplates() throws {
        let fixture = try Fixture()
        let value = template(fixture)
        try fixture.services.recurring.add(value)
        #expect(try fixture.services.recurring.templates(in: fixture.group.id) == [value])
    }

    @Test func createsTheFirstOccurrenceRightAway() throws {
        let fixture = try Fixture()
        try fixture.services.recurring.add(template(fixture))
        let made = try fixture.services.recurring.createDueExpenses(through: fixture.clock.start)
        #expect(made.count == 1)
        #expect(made[0].date == fixture.clock.start)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 1)
    }

    @Test func catchesUpOnMissedOccurrencesOnce() throws {
        let fixture = try Fixture()
        try fixture.services.recurring.add(template(fixture, frequency: .weekly, startingDaysAgo: 21))
        let made = try fixture.services.recurring.createDueExpenses(through: fixture.clock.start)
        #expect(made.count == 4)
        #expect(try fixture.services.recurring.createDueExpenses(through: fixture.clock.start).isEmpty)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 4)
    }

    @Test func laterRunsOnlyAddWhatBecameDue() throws {
        let fixture = try Fixture()
        try fixture.services.recurring.add(template(fixture, frequency: .daily))
        try fixture.services.recurring.createDueExpenses(through: fixture.clock.start)
        let made = try fixture.services.recurring.createDueExpenses(through: fixture.clock.start.addingTimeInterval(2 * 86_400))
        #expect(made.count == 2)
    }

    @Test func createdExpensesPointBackToTheTemplateAndAreLogged() throws {
        let fixture = try Fixture()
        let value = template(fixture)
        try fixture.services.recurring.add(value)
        let made = try #require(try fixture.services.recurring.createDueExpenses(through: fixture.clock.start).first)
        #expect(try fixture.services.expenses.details(id: made.id)?.extras.recurringExpenseID == value.id)
        let latest = try #require(try fixture.services.activity.entries(in: fixture.group.id, limit: 1).first)
        #expect(latest.event.kind == .expenseAdded)
    }

    @Test func pausedAndDeletedTemplatesMakeNothing() throws {
        let fixture = try Fixture()
        var paused = template(fixture)
        paused.isActive = false
        try fixture.services.recurring.add(paused)
        let removed = template(fixture)
        try fixture.services.recurring.add(removed)
        try fixture.services.recurring.delete(id: removed.id)
        #expect(try fixture.services.recurring.createDueExpenses(through: fixture.clock.start).isEmpty)
    }

    @Test func templateEditsAreSaved() throws {
        let fixture = try Fixture()
        var value = template(fixture)
        try fixture.services.recurring.add(value)
        value.title = "Rent and bills"
        try fixture.services.recurring.update(value)
        #expect(try fixture.services.recurring.templates(in: fixture.group.id).first?.title == "Rent and bills")
    }

    @Test func twoDevicesMakeTheSameExpenseIDForTheSameOccurrence() {
        let templateID = UUID()
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        #expect(OccurrenceID.expenseID(template: templateID, occurrence: date) == OccurrenceID.expenseID(template: templateID, occurrence: date))
        #expect(OccurrenceID.expenseID(template: templateID, occurrence: date) != OccurrenceID.expenseID(template: templateID, occurrence: date.addingTimeInterval(86_400)))
        #expect(OccurrenceID.expenseID(template: templateID, occurrence: date) != OccurrenceID.expenseID(template: UUID(), occurrence: date))
    }

    @Test func anOccurrenceAnotherDeviceAlreadyMadeIsNotMadeTwice() throws {
        let fixture = try Fixture()
        let value = template(fixture)
        try fixture.services.recurring.add(value)
        var existing = value.expense(on: fixture.clock.start)
        existing.id = OccurrenceID.expenseID(template: value.id, occurrence: fixture.clock.start)
        try fixture.services.expenses.add(existing)
        #expect(try fixture.services.recurring.createDueExpenses(through: fixture.clock.start).isEmpty)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 1)
    }
}
