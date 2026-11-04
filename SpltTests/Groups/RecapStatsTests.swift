import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Recap stats")
struct RecapStatsTests {
    private let calendar = GroupsTestCalendar.utc
    private let ana = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!)
    private let ben = PersonID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-0000000000B2")!)
    private var names: [PersonID: String] { [ana: "Ana", ben: "Ben"] }

    private func trip(start: Date? = utcDate(2026, 5, 8), end: Date? = utcDate(2026, 5, 10)) -> SplitGroup {
        SplitGroup(name: "Lisbon", currencyCode: "USD", kind: .trip, memberIDs: [ana, ben], tripStart: start, tripEnd: end)
    }

    private func expense(
        _ title: String, _ cents: Int64, day: Int, category: ExpenseCategory = .general, payer: PersonID? = nil,
        month: Int = 5, currency: String = "USD", deleted: Bool = false
    ) -> Expense {
        Expense(
            title: title, total: Money(minorUnits: cents, currencyCode: currency), date: utcDate(2026, month, day),
            category: category, paidBy: payer ?? ana, split: .equal(participants: [ana, ben]),
            deletedAt: deleted ? utcDate(2026, 6, 1) : nil
        )
    }

    private func stats(_ group: SplitGroup, _ expenses: [Expense], now: Date = utcDate(2026, 5, 20)) -> RecapStats? {
        RecapStats(group: group, expenses: expenses, names: names, now: now, calendar: calendar)
    }

    @Test func nothingSpentMeansNoRecap() {
        #expect(stats(trip(), []) == nil)
        #expect(stats(trip(), [expense("Old", 100, day: 9, deleted: true)]) == nil)
        #expect(stats(trip(), [expense("Yen", 100, day: 9, currency: "JPY")]) == nil)
    }

    @Test func totalsAndDaysCoverTheWholeTrip() throws {
        let result = try #require(stats(trip(), [
            expense("Airbnb", 6000, day: 8, category: .lodging),
            expense("Dinner", 3000, day: 10, category: .dining, payer: ben)
        ]))
        #expect(result.total == usdAmount(9000))
        #expect(result.expenseCount == 2)
        #expect(result.bucket == .day)
        #expect(result.slices.map(\.total.minorUnits) == [6000, 0, 3000])
        #expect(result.average == usdAmount(3000))
        #expect(result.busiest?.total == usdAmount(6000))
        #expect(result.busiest?.start == utcDate(2026, 5, 8, hour: 0))
    }

    @Test func spendingOutsideTheTripDatesStretchesTheRange() throws {
        let result = try #require(stats(trip(), [expense("Early", 500, day: 6), expense("Late", 500, day: 12)]))
        #expect(result.slices.count == 7)
        #expect(result.first == utcDate(2026, 5, 6, hour: 0))
        #expect(result.last == utcDate(2026, 5, 12, hour: 0))
    }

    @Test func groupsWithoutDatesUseTheirExpenses() throws {
        let flat = SplitGroup(name: "Flat", currencyCode: "USD", memberIDs: [ana, ben])
        let result = try #require(stats(flat, [expense("Rent", 1000, day: 3), expense("Gas", 200, day: 5)]))
        #expect(result.slices.count == 3)
        #expect(result.total == usdAmount(1200))
    }

    @Test func longSpansGroupByMonth() throws {
        let flat = SplitGroup(name: "Flat", currencyCode: "USD", memberIDs: [ana, ben])
        let result = try #require(stats(flat, [
            expense("Jan", 1000, day: 5, month: 1), expense("Mar", 2000, day: 5, month: 3), expense("Jun", 500, day: 9, month: 6)
        ]))
        #expect(result.bucket == .month)
        #expect(result.slices.count == 6)
        #expect(result.slices.map(\.total.minorUnits) == [1000, 0, 2000, 0, 0, 500])
        #expect(result.busiest?.start == utcDate(2026, 3, 1, hour: 0))
    }

    @Test func theBiggestExpenseKnowsWhoPaid() throws {
        let result = try #require(stats(trip(), [
            expense("Airbnb", 6000, day: 8, category: .lodging, payer: ben), expense("Coffee", 300, day: 9)
        ]))
        let biggest = try #require(result.biggest)
        #expect(biggest.title == "Airbnb")
        #expect(biggest.amount == usdAmount(6000))
        #expect(biggest.payerName == "Ben")
        #expect(biggest.category == .lodging)
    }

    @Test func theTopPayerHasAWholePercent() throws {
        let result = try #require(stats(trip(), [
            expense("A", 7000, day: 8, payer: ben), expense("B", 2000, day: 9), expense("C", 1000, day: 9)
        ]))
        let payer = try #require(result.topPayer)
        #expect(payer.name == "Ben")
        #expect(payer.paid == usdAmount(7000))
        #expect(payer.percent == 70)
    }

    @Test func categoriesKeepFourAndGatherTheRest() throws {
        let categories: [ExpenseCategory] = [.dining, .lodging, .transport, .drinks, .gifts, .health]
        let expenses = categories.enumerated().map { index, category in
            expense("E\(index)", Int64(6000 - index * 800), day: 8 + index % 3, category: category)
        }
        let result = try #require(stats(trip(), expenses))
        #expect(result.categories.count == 5)
        #expect(result.categories.map(\.category).prefix(4) == [.dining, .lodging, .transport, .drinks])
        #expect(result.categories.last?.category == .other)
        let sum = result.categories.map(\.percent).reduce(0, +)
        #expect((99...101).contains(sum))
        #expect(result.categories.map(\.amount.minorUnits).reduce(0, +) == result.total.minorUnits)
    }

    @Test func refundsReduceTheTotalButNotTheCategoryShares() throws {
        let result = try #require(stats(trip(), [
            expense("Tickets", 5000, day: 8, category: .entertainment),
            expense("Refund", -1000, day: 9, category: .entertainment, payer: ben)
        ]))
        #expect(result.total == usdAmount(4000))
        #expect(result.categories.first?.amount == usdAmount(4000))
        #expect(result.topPayer?.name == "Ana")
    }

    @Test func aSingleDayStillHasASlice() throws {
        let one = trip(start: utcDate(2026, 5, 8), end: utcDate(2026, 5, 8))
        let result = try #require(stats(one, [expense("Lunch", 1500, day: 8)]))
        #expect(result.slices.count == 1)
        #expect(result.average == usdAmount(1500))
        #expect(result.dayCount == 1)
    }

    @Test func daysAfterAClockChangeAtMidnightKeepTheirSpending() throws {
        var havana = Calendar(identifier: .gregorian)
        havana.timeZone = TimeZone(identifier: "America/Havana")!
        let day = { (day: Int) in havana.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 12))! }
        let group = SplitGroup(name: "Cuba", currencyCode: "USD", kind: .trip, memberIDs: [ana, ben], tripStart: day(6), tripEnd: day(12))
        let expense = Expense(
            title: "Dinner", total: Money(minorUnits: 5000, currencyCode: "USD"), date: day(10),
            paidBy: ana, split: .equal(participants: [ana, ben])
        )
        let stats = try #require(RecapStats(group: group, expenses: [expense], names: names, now: day(20), calendar: havana))
        #expect(stats.slices.count == 7)
        #expect(stats.slices.reduce(0) { $0 + $1.total.minorUnits } == 5000)
        #expect(stats.busiest.map { havana.component(.day, from: $0.start) } == 10)
    }
}
