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
        #expect(rule.occurrences(from: date(10, 1, 0), through: date(12, 31, 0)).count == 3)
        #expect(calendar.isDate(end, inSameDayAs: date(12, 1, 9)))
    }

    @Test func aDayLongerOrShorterThanUsualEndsOnThatDay() {
        let spring = RepeatChoice.lastMoment(of: date(3, 8, 9), calendar: calendar)
        let autumn = RepeatChoice.lastMoment(of: date(11, 1, 9), calendar: calendar)
        #expect(calendar.isDate(spring, inSameDayAs: date(3, 8, 9)))
        #expect(calendar.isDate(autumn, inSameDayAs: date(11, 1, 9)))
    }
}
