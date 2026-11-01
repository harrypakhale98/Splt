import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Expense filter and sections")
struct ExpenseFilterTests {
    private let calendar = GroupsTestCalendar.utc
    private let now = utcDate(2026, 5, 15)

    private func expense(_ title: String, on date: Date) -> Expense {
        Expense(
            title: title, total: usdAmount(1000), date: date, paidBy: PersonID(),
            split: .equal(participants: [PersonID()])
        )
    }

    @Test func anEmptyFilterIsNotActive() {
        let filter = ExpenseFilter()
        #expect(!filter.isActive)
        #expect(!filter.isFiltering)
        #expect(filter.dateRange(now: now, calendar: calendar) == nil)
    }

    @Test func aQueryIsActiveButNotFiltering() {
        var filter = ExpenseFilter()
        filter.query = "dinner"
        #expect(filter.isActive)
        #expect(!filter.isFiltering)
    }

    @Test func periodsCoverTheRightDays() throws {
        var filter = ExpenseFilter()
        filter.period = .thisMonth
        let month = try #require(filter.dateRange(now: now, calendar: calendar))
        #expect(month.lowerBound == utcDate(2026, 5, 1, hour: 0))
        #expect(month.upperBound == utcDate(2026, 6, 1, hour: 0))

        filter.period = .lastMonth
        let previous = try #require(filter.dateRange(now: now, calendar: calendar))
        #expect(previous.lowerBound == utcDate(2026, 4, 1, hour: 0))
        #expect(previous.upperBound == utcDate(2026, 5, 1, hour: 0))

        filter.period = .last30Days
        let recent = try #require(filter.dateRange(now: now, calendar: calendar))
        #expect(recent.lowerBound == utcDate(2026, 4, 16, hour: 0))
        #expect(recent.upperBound == utcDate(2026, 5, 16, hour: 0))
    }

    @Test func customRangesIncludeTheLastDayAndAcceptReversedDates() throws {
        var filter = ExpenseFilter()
        filter.period = .custom
        filter.customStart = utcDate(2026, 5, 5)
        filter.customEnd = utcDate(2026, 5, 3)
        let range = try #require(filter.dateRange(now: now, calendar: calendar))
        #expect(range.contains(utcDate(2026, 5, 5, hour: 23)))
        #expect(range.contains(utcDate(2026, 5, 3, hour: 0)))
        #expect(!range.contains(utcDate(2026, 5, 6, hour: 0)))
    }

    @Test func everyWordOfTheQueryMustMatch() {
        var filter = ExpenseFilter()
        let item = expense("Seafood dinner", on: now)
        filter.query = "sea din"
        #expect(filter.matches(item, names: [:], now: now, calendar: calendar))
        filter.query = "sea lunch"
        #expect(!filter.matches(item, names: [:], now: now, calendar: calendar))
    }

    @Test func sectionsSortNewestFirst() {
        let items = [
            expense("a", on: utcDate(2026, 3, 1)),
            expense("b", on: utcDate(2026, 5, 20)),
            expense("c", on: utcDate(2026, 5, 3)),
            expense("d", on: utcDate(2026, 4, 9))
        ]
        let sections = ExpenseSectioning.sections(items, grouping: .month, calendar: calendar)
        #expect(sections.map { $0.expenses.map(\.title) } == [["b", "c"], ["d"], ["a"]])
        #expect(sections.map(\.start) == sections.map(\.start).sorted(by: >))
    }

    @Test func dayNumbersStartAtOne() {
        let start = utcDate(2026, 5, 8)
        #expect(ExpenseSectioning.dayNumber(of: utcDate(2026, 5, 8), tripStart: start, calendar: calendar) == 1)
        #expect(ExpenseSectioning.dayNumber(of: utcDate(2026, 5, 11), tripStart: start, calendar: calendar) == 4)
        #expect(ExpenseSectioning.dayNumber(of: utcDate(2026, 5, 7), tripStart: start, calendar: calendar) == 0)
        #expect(ExpenseSectioning.dayNumber(of: start, tripStart: nil, calendar: calendar) == nil)
    }
}
