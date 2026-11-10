import Foundation
import SpltCore
import Testing
@testable import Splt

@MainActor
@Suite("Charts open their expenses")
struct ChartDrillTests {
    private func makeModel(_ fixture: Fixture) -> GroupDetailViewModel {
        GroupDetailViewModel(
            groupID: fixture.group.id, services: fixture.services,
            now: { utcDate(2026, 5, 15) }, calendar: GroupsTestCalendar.utc
        )
    }

    @Test func aPersonsBarShowsTheExpensesTheyPaidFor() throws {
        let fixture = try Fixture()
        try fixture.addExpense(cents: 3000, paidBy: fixture.sam)
        let model = makeModel(fixture)
        model.segment = .totals
        model.filter.query = "old search"
        let before = model.drillRevision

        model.showExpenses(paidBy: fixture.sam.id)

        #expect(model.segment == .expenses)
        #expect(model.filter.payer == fixture.sam.id)
        #expect(model.filter.category == nil)
        #expect(model.filter.query.isEmpty)
        #expect(model.drillRevision == before + 1)
        #expect(model.filterDescription(locale: Locale(identifier: "en_US")) == "Paid by \(fixture.sam.name)")
    }

    @Test func aCategoryBarReplacesAnEarlierPayerFilter() throws {
        let fixture = try Fixture()
        let model = makeModel(fixture)
        model.showExpenses(paidBy: fixture.sam.id)
        model.showExpenses(in: .dining)
        #expect(model.filter.payer == nil)
        #expect(model.filter.category == .dining)
        #expect(model.filterDescription(locale: Locale(identifier: "en_US")) == ExpenseCategory.dining.title)
    }

    @Test func noFilterHasNoDescription() throws {
        let model = makeModel(try Fixture())
        #expect(model.filterDescription(locale: Locale(identifier: "en_US")) == nil)
    }
}

@Suite("Paid strip")
struct PaidStripTests {
    private let ana = PersonID(rawValue: UUID())
    private let ben = PersonID(rawValue: UUID())
    private let cy = PersonID(rawValue: UUID())

    private func paid(_ person: PersonID, _ cents: Int64) -> GroupTotals.PersonAmount {
        GroupTotals.PersonAmount(personID: person, name: "", paid: Money(minorUnits: cents, currencyCode: "USD"))
    }

    @Test func slicesFollowWhatEachPersonPaidLargestFirst() {
        let strip = PaidStrip(members: [ana, ben, cy], paid: [paid(ana, 1000), paid(ben, 9000)])
        #expect(strip.people == [ben, ana, cy])
        let weights = strip.weights ?? []
        #expect(weights[0] == 9000)
        #expect(weights[1] == 1000)
        // cy paid nothing but keeps a sliver so the strip still shows everyone
        #expect(weights[2] == 10_000 * PaidStrip.sliver)
    }

    @Test func withNoSpendingEveryoneGetsAnEqualSlice() {
        let strip = PaidStrip(members: [ana, ben], paid: [])
        #expect(strip.people == [ana, ben])
        #expect(strip.weights == nil)
    }

    @Test func refundsNeverMakeASliceNegative() {
        let strip = PaidStrip(members: [ana, ben], paid: [paid(ana, 5000), paid(ben, -2000)])
        #expect((strip.weights ?? []).allSatisfy { $0 > 0 })
    }

    @Test func voiceOverReadsTheShares() {
        let strip = PaidStrip(members: [ana, ben], paid: [paid(ana, 7500), paid(ben, 2500)])
        #expect(strip.spoken(names: [ana: "Ana", ben: "Ben"]) == "Paid: Ana 75%, Ben 25%")
    }
}
