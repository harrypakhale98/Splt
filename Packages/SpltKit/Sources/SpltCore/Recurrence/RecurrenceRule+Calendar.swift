import Foundation

extension RecurrenceRule {
    private static let searchLimit = 1 << 22

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The occurrence at an index, ignoring the end date and the occurrence cap.
    func unboundedOccurrence(at index: Int, calendar: Calendar) -> Date? {
        if index == 0 { return startDate }
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: startDate)
        guard let year = start.year, let month = start.month, let day = start.day else { return nil }

        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: index, to: startDate)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * index, to: startDate)
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14 * index, to: startDate)
        case .monthly:
            return date(monthsAfter: index, day: day, start: start, year: year, month: month, calendar: calendar)
        case .quarterly:
            return date(monthsAfter: 3 * index, day: day, start: start, year: year, month: month, calendar: calendar)
        case .yearly:
            return date(monthsAfter: 12 * index, day: day, start: start, year: year, month: month, calendar: calendar)
        case .semiMonthly:
            let early = day <= 15 ? day : day - 15
            let position = index + (day > 15 ? 1 : 0)
            return date(
                monthsAfter: position / 2, day: position % 2 == 0 ? early : early + 15,
                start: start, year: year, month: month, calendar: calendar
            )
        }
    }

    /// The index of the first occurrence whose date satisfies `predicate`, which must turn
    /// true at some point and stay true. Looks past the end date; callers check the limits.
    func firstIndex(where predicate: (Date) -> Bool) -> Int? {
        let calendar = self.calendar
        guard let first = unboundedOccurrence(at: 0, calendar: calendar) else { return nil }
        if predicate(first) { return 0 }

        var low = 0
        var high = 1
        while true {
            guard let date = unboundedOccurrence(at: high, calendar: calendar) else { return nil }
            if predicate(date) { break }
            guard high < Self.searchLimit else { return nil }
            low = high
            high *= 2
        }
        while high - low > 1 {
            let middle = low + (high - low) / 2
            guard let date = unboundedOccurrence(at: middle, calendar: calendar) else { return nil }
            if predicate(date) { high = middle } else { low = middle }
        }
        return high
    }

    /// The date `months` calendar months after the start month, on `day` or the month's last day,
    /// at the start's wall clock time.
    private func date(
        monthsAfter months: Int, day: Int, start: DateComponents, year: Int, month: Int, calendar: Calendar
    ) -> Date? {
        let monthIndex = year * 12 + (month - 1) + months
        let targetYear = monthIndex / 12
        let targetMonth = monthIndex % 12 + 1

        var probe = DateComponents(year: targetYear, month: targetMonth, day: 1, hour: 12)
        probe.calendar = calendar
        guard let monthStart = calendar.date(from: probe),
              let days = calendar.range(of: .day, in: .month, for: monthStart)?.count else { return nil }

        var components = DateComponents(
            year: targetYear, month: targetMonth, day: min(day, days),
            hour: start.hour, minute: start.minute, second: start.second, nanosecond: start.nanosecond
        )
        components.calendar = calendar
        return calendar.date(from: components)
    }
}
