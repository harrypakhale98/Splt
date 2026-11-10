import Foundation
import SpltCore
import Testing
@testable import Splt

@Suite("Repeat end date")
struct RepeatEndDateTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func anOccurrenceLaterOnTheEndDayStillHappens() {
        let end = RepeatChoice.lastMoment(of: date(12, 1, 9), calendar: calendar)
        let rule = RecurrenceRule(frequency: .monthly, startDate: date(10, 1, 18), timeZone: calendar.timeZone, endDate: end)
        #expect(rule.dueOccurrences(after: nil, through: date(12, 31, 0)).count == 3)
        #expect(calendar.isDate(end, inSameDayAs: date(12, 1, 9)))
    }

    @Test func theFirstEndDateOfAnOldTemplateIsAYearFromToday() throws {
        let started = calendar.date(from: DateComponents(year: 2024, month: 3, day: 1, hour: 9))!
        let today = date(11, 10, 15)
        let earliest = RepeatChoice.earliestEnd(start: started, now: today)
        #expect(earliest == today)
        let end = try #require(RepeatChoice.defaultEnd(from: earliest, calendar: calendar))
        #expect(end > today)
        #expect(calendar.isDate(end, inSameDayAs: calendar.date(from: DateComponents(year: 2027, month: 11, day: 10))!))
    }

    @Test func theFirstEndDateOfAFutureStartIsAYearAfterIt() throws {
        let earliest = RepeatChoice.earliestEnd(start: date(12, 24, 9), now: date(11, 10, 15))
        #expect(earliest == date(12, 24, 9))
        let end = try #require(RepeatChoice.defaultEnd(from: earliest, calendar: calendar))
        #expect(calendar.isDate(end, inSameDayAs: calendar.date(from: DateComponents(year: 2027, month: 12, day: 24))!))
    }

    @Test func aDayLongerOrShorterThanUsualEndsOnThatDay() {
        let spring = RepeatChoice.lastMoment(of: date(3, 8, 9), calendar: calendar)
        let autumn = RepeatChoice.lastMoment(of: date(11, 1, 9), calendar: calendar)
        #expect(calendar.isDate(spring, inSameDayAs: date(3, 8, 9)))
        #expect(calendar.isDate(autumn, inSameDayAs: date(11, 1, 9)))
    }
}
