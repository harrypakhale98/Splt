import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Spending sums")
struct SpendingSummaryTests {
    private let me = PersonID()
    private let sam = PersonID()
    private let flat = GroupID()
    private let trip = GroupID()

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private let now = SpendingSummaryTests.day(2026, 11, 10)

    private func expense(
        _ cents: Int64, _ code: String = "USD", on date: Date, in group: GroupID? = nil, paidBy payer: PersonID? = nil,
        between people: Set<PersonID>? = nil, category: ExpenseCategory = .general, deleted: Bool = false
    ) -> Expense {
        Expense(
            groupID: group ?? flat, title: "Thing", total: Money(minorUnits: cents, currencyCode: code), date: date,
            category: category, paidBy: payer ?? sam, split: .equal(participants: people ?? [me, sam]),
            deletedAt: deleted ? date : nil
        )
    }

    private func make(
        _ expenses: [Expense], range: SpendingRange = .last12Months, target: String? = nil,
        convert: @escaping SpendingSummary.Converter = { _, _ in nil }, lead: String? = nil
    ) -> SpendingSummary {
        SpendingSummary.make(
            expenses: expenses, me: me, range: range, now: now, calendar: Self.calendar,
            target: target, convert: convert, lead: lead
        )
    }

    // MARK: Ranges

    @Test func last12MonthsEndsWithThisMonth() {
        let months = SpendingRange.last12Months.months(now: now, earliest: nil, calendar: Self.calendar)
        #expect(months.count == 12)
        #expect(months.first == Self.calendar.date(from: DateComponents(year: 2025, month: 12, day: 1)))
        #expect(months.last == Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
    }

    @Test func thisYearStartsInJanuary() {
        let months = SpendingRange.thisYear.months(now: now, earliest: nil, calendar: Self.calendar)
        #expect(months.count == 11)
        #expect(months.first == Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
    }

    @Test func allTimeStartsAtTheOldestExpense() {
        let months = SpendingRange.allTime.months(now: now, earliest: Self.day(2024, 3, 9), calendar: Self.calendar)
        #expect(months.count == 33)
        #expect(SpendingRange.allTime.months(now: now, earliest: nil, calendar: Self.calendar).count == 1)
        #expect(SpendingRange.allTime.dateRange(now: now, calendar: Self.calendar) == nil)
    }

    @Test func expensesOutsideTheRangeAreLeftOut() {
        let summary = make([
            expense(10_000, on: Self.day(2026, 11, 2)),
            expense(4_000, on: Self.day(2025, 12, 1)),
            expense(9_000, on: Self.day(2025, 11, 30)),
            expense(8_000, on: Self.day(2026, 12, 1)),
        ])
        #expect(summary.buckets.first?.share == 7_000)
        #expect(summary.buckets.first?.expenseCount == 2)
        let year = make([expense(10_000, on: Self.day(2026, 11, 2)), expense(4_000, on: Self.day(2025, 12, 1))], range: .thisYear)
        #expect(year.buckets.first?.share == 5_000)
    }

    // MARK: Your share

    @Test func yourShareCountsOnlyWhatIsYours() {
        let summary = make([
            expense(3_000, on: Self.day(2026, 11, 1), between: [me, sam]),
            expense(9_000, on: Self.day(2026, 10, 3), paidBy: me, between: [sam]),
            expense(-1_000, on: Self.day(2026, 10, 4), between: [me, sam]),
            expense(5_000, on: Self.day(2026, 10, 5), deleted: true),
        ])
        let bucket = try! #require(summary.buckets.first)
        // 1,500 of the first, none of the second, minus 500 for the refund; deleted ones are ignored
        #expect(bucket.share == 1_000)
        #expect(bucket.total == 11_000)
        #expect(bucket.expenseCount == 3)
        #expect(summary.yourExpenseCount == 2)
        #expect(bucket.months.last == 1_500)
        #expect(bucket.months[10] == -500)
        #expect(bucket.payers[me] == 9_000)
        #expect(bucket.payers[sam] == 2_000)
    }

    @Test func categoriesAndGroupsAreYourShare() {
        let summary = make([
            expense(4_000, on: Self.day(2026, 9, 1), category: .groceries),
            expense(2_000, on: Self.day(2026, 9, 2), in: trip, category: .dining),
            expense(6_000, on: Self.day(2026, 9, 3), between: [sam], category: .travel),
        ])
        let bucket = try! #require(summary.buckets.first)
        #expect(bucket.categories == [.groceries: 2_000, .dining: 1_000])
        #expect(bucket.groups == [flat: 2_000, trip: 1_000])
        #expect(bucket.categoryRows.map(\.money.minorUnits) == [2_000, 1_000])
        #expect(summary.yourGroups == [flat, trip])
    }

    @Test func eachCurrencyKeepsItsOwnBucketWithTheLeadFirst() {
        let summary = make([
            expense(1_000, "EUR", on: Self.day(2026, 9, 1)),
            expense(1_000, "EUR", on: Self.day(2026, 9, 2)),
            expense(4_000, on: Self.day(2026, 9, 3)),
        ], lead: "USD")
        #expect(summary.buckets.map(\.currencyCode) == ["USD", "EUR"])
        #expect(summary.buckets.map(\.share) == [2_000, 1_000])
        #expect(summary.converted.isEmpty)
    }

    // MARK: Converting

    @Test func otherCurrenciesAreConvertedIntoOne() {
        let rates = ExchangeRates(baseCurrency: "USD", rates: ["EUR": Decimal(string: "0.8")!, "JPY": 150])
        let convert = SpendingSummary.converter(into: "USD") { _ in rates }
        let summary = make([
            expense(4_000, on: Self.day(2026, 9, 1)),
            expense(1_600, "EUR", on: Self.day(2026, 9, 2), in: trip),
            expense(3_000, "JPY", on: Self.day(2026, 9, 3), in: trip),
        ], target: "USD", convert: convert)
        #expect(summary.buckets.count == 1)
        let bucket = try! #require(summary.buckets.first)
        // 20.00 + €8.00 → 10.00 + ¥1,500 → 10.00
        #expect(bucket.share == 4_000)
        #expect(bucket.groups[trip] == 2_000)
        #expect(summary.converted == ["EUR": 800, "JPY": 1_500])
        #expect(summary.convertedByGroup[trip] == ["EUR", "JPY"])
        #expect(summary.notConverted.isEmpty)
    }

    @Test func aCurrencyWithoutARateStaysOutOfTheTotal() {
        let rates = ExchangeRates(baseCurrency: "USD", rates: ["EUR": Decimal(string: "0.8")!])
        let convert = SpendingSummary.converter(into: "USD") { _ in rates }
        let summary = make([
            expense(4_000, on: Self.day(2026, 9, 1)),
            expense(3_000, "JPY", on: Self.day(2026, 9, 3), in: trip),
        ], target: "USD", convert: convert)
        #expect(summary.buckets.first?.share == 2_000)
        #expect(summary.buckets.first?.expenseCount == 1)
        #expect(summary.notConverted == ["JPY": 1_500])
        #expect(summary.yourExpenseCount == 2)
        #expect(summary.yourGroups == [flat, trip])
    }

    @Test func eachExpenseUsesTheRatesItIsGiven() {
        let september = ExchangeRates(baseCurrency: "USD", rates: ["EUR": Decimal(string: "0.5")!])
        let october = ExchangeRates(baseCurrency: "USD", rates: ["EUR": 1])
        let cutoff = Self.day(2026, 10, 1)
        let convert = SpendingSummary.converter(into: "USD") { $0.date < cutoff ? september : october }
        let summary = make([
            expense(1_000, "EUR", on: Self.day(2026, 9, 15)),
            expense(1_000, "EUR", on: Self.day(2026, 10, 15)),
        ], target: "USD", convert: convert)
        let bucket = try! #require(summary.buckets.first)
        #expect(bucket.months[9] == 1_000)
        #expect(bucket.months[10] == 500)
        #expect(bucket.share == 1_500)
    }
}
