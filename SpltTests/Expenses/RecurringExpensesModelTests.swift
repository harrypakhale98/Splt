import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Recurring expenses")
@MainActor
struct RecurringExpensesModelTests {
    private func template(_ fixture: Fixture, last: Date? = nil) -> RecurringExpense {
        RecurringExpense(
            groupID: fixture.group.id, title: "Rent", total: usdAmount(90_000), category: .rent,
            payers: [fixture.me.id: usdAmount(90_000)], split: .equal(participants: fixture.everyone),
            rule: RecurrenceRule(frequency: .monthly, startDate: fixture.clock.start),
            lastCreatedOccurrence: last
        )
    }

    @Test func listsTemplatesWithTheirNextDate() throws {
        let fixture = try Fixture()
        let fresh = template(fixture)
        try fixture.services.recurring.add(fresh)
        let model = RecurringExpensesModel(groupID: fixture.group.id, services: fixture.services)

        #expect(model.templates.count == 1)
        #expect(model.nextDate(for: fresh) == fixture.clock.start)

        var made = fresh
        made.lastCreatedOccurrence = fixture.clock.start
        let next = try #require(model.nextDate(for: made))
        #expect(next > fixture.clock.start)
        #expect(model.payerSummary(for: fresh) == "You paid")
    }

    @Test func pausingStopsGeneration() throws {
        let fixture = try Fixture()
        let rent = template(fixture)
        try fixture.services.recurring.add(rent)
        let model = RecurringExpensesModel(groupID: fixture.group.id, services: fixture.services)

        model.setActive(false, for: rent)
        #expect(model.templates.first?.isActive == false)
        let whilePaused = RecurringExpenseGenerator.run(services: fixture.services, now: fixture.clock.start.addingTimeInterval(86_400 * 90))
        #expect(whilePaused.isEmpty)

        // Resuming does not bill what was missed, it picks up at the next future date.
        fixture.clock.advance(by: 86_400 * 90)
        let resumedAt = fixture.clock.start.addingTimeInterval(86_400 * 90)
        model.setActive(true, for: model.templates[0])
        #expect(RecurringExpenseGenerator.run(services: fixture.services, now: resumedAt.addingTimeInterval(60)).isEmpty)
        let next = try #require(model.nextDate(for: model.templates[0]))
        #expect(next > resumedAt)
        #expect(next < resumedAt.addingTimeInterval(86_400 * 32))
        #expect(RecurringExpenseGenerator.run(services: fixture.services, now: next).count == 1)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 1)
    }

    @Test func deletingLeavesPastExpenses() throws {
        let fixture = try Fixture()
        let rent = template(fixture)
        try fixture.services.recurring.add(rent)
        RecurringExpenseGenerator.run(services: fixture.services, now: fixture.clock.start.addingTimeInterval(60))
        let model = RecurringExpensesModel(groupID: fixture.group.id, services: fixture.services)

        model.delete(rent)
        #expect(model.templates.isEmpty)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 1)
    }

    @Test func generationIsIdempotent() throws {
        let fixture = try Fixture()
        try fixture.services.recurring.add(template(fixture))
        let now = fixture.clock.start.addingTimeInterval(86_400 * 70)
        let first = RecurringExpenseGenerator.run(services: fixture.services, now: now)
        let second = RecurringExpenseGenerator.run(services: fixture.services, now: now)
        #expect(first.count == 3)
        #expect(second.isEmpty)
        #expect(try fixture.services.expenses.expenses(in: fixture.group.id).count == 3)
    }

    @Test func frequencyTitlesAreDistinct() {
        let titles = RecurrenceFrequency.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(Set(RecurrenceFrequency.allCases.map(\.footerPhrase)).count == titles.count)
    }
}
