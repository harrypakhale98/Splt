import Foundation
import SpltCore

enum ExpenseGrouping: Hashable, Sendable {
    case month
    case day
}

struct ExpenseSection: Identifiable, Equatable, Sendable {
    /// The first instant of the month or day.
    var start: Date
    /// Newest first.
    var expenses: [Expense]

    var id: Date { start }

    /// What the section adds up to, or nil when it mixes currencies.
    var total: Money? {
        guard let code = expenses.first?.total.currencyCode,
              expenses.allSatisfy({ $0.total.currencyCode == code }) else { return nil }
        let units = expenses.reduce(Int64(0)) { sum, expense in
            let (value, overflow) = sum.addingReportingOverflow(expense.total.minorUnits)
            return overflow ? sum : value
        }
        return Money(minorUnits: units, currencyCode: code)
    }
}

enum ExpenseSectioning {
    /// Groups expenses by month or day, newest section first and newest expense first inside each.
    static func sections(_ expenses: [Expense], grouping: ExpenseGrouping, calendar: Calendar) -> [ExpenseSection] {
        let component: Calendar.Component = grouping == .month ? .month : .day
        var buckets: [Date: [Expense]] = [:]
        for expense in expenses {
            let start = calendar.dateInterval(of: component, for: expense.date)?.start ?? expense.date
            buckets[start, default: []].append(expense)
        }
        return buckets.keys.sorted(by: >).map { start in
            ExpenseSection(start: start, expenses: (buckets[start] ?? []).sorted { $0.date > $1.date })
        }
    }

    /// "May 2026", or for trips "Day 3, Sat, May 10".
    static func title(
        for section: ExpenseSection, grouping: ExpenseGrouping, tripStart: Date?, calendar: Calendar, locale: Locale
    ) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch grouping {
        case .month:
            return section.start.formatted(style.month(.wide).year())
        case .day:
            let day = section.start.formatted(style.weekday(.abbreviated).month(.abbreviated).day())
            guard let number = dayNumber(of: section.start, tripStart: tripStart, calendar: calendar), number >= 1 else {
                return day
            }
            return String(localized: "Day \(number), \(day)")
        }
    }

    /// 1 for the first day of the trip. Nil when the trip has no start date.
    static func dayNumber(of date: Date, tripStart: Date?, calendar: Calendar) -> Int? {
        guard let tripStart else { return nil }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: tripStart), to: calendar.startOfDay(for: date)
        ).day
        return days.map { $0 + 1 }
    }
}
