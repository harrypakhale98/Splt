import Foundation
import SpltCore

/// Search and filters for a group's expense list.
struct ExpenseFilter: Equatable, Sendable {
    enum Period: String, CaseIterable, Identifiable, Hashable, Sendable {
        case anytime
        case thisMonth
        case lastMonth
        case last30Days
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .anytime: String(localized: "Any Time")
            case .thisMonth: String(localized: "This Month")
            case .lastMonth: String(localized: "Last Month")
            case .last30Days: String(localized: "Last 30 Days")
            case .custom: String(localized: "Custom Range")
            }
        }
    }

    var query = ""
    var payer: PersonID?
    var category: ExpenseCategory?
    var period: Period = .anytime
    var customStart = Date()
    var customEnd = Date()

    init() {}

    /// True when a payer, category or period narrows the list. A search query is not counted.
    var isFiltering: Bool {
        payer != nil || category != nil || period != .anytime
    }

    var isActive: Bool {
        isFiltering || !trimmedQuery.isEmpty
    }

    mutating func clear() {
        self = ExpenseFilter()
    }

    mutating func clearFilters() {
        payer = nil
        category = nil
        period = .anytime
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The dates the period covers: from the first instant to just before the end. Nil for any time.
    func dateRange(now: Date, calendar: Calendar) -> Range<Date>? {
        switch period {
        case .anytime:
            return nil
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now).map { $0.start..<$0.end }
        case .lastMonth:
            guard let current = calendar.dateInterval(of: .month, for: now),
                  let previous = calendar.date(byAdding: .month, value: -1, to: current.start),
                  let interval = calendar.dateInterval(of: .month, for: previous) else { return nil }
            return interval.start..<interval.end
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: -29, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
            return start..<end
        case .custom:
            let first = min(customStart, customEnd)
            let last = max(customStart, customEnd)
            guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else { return nil }
            return calendar.startOfDay(for: first)..<end
        }
    }

    func matches(_ expense: Expense, names: [PersonID: String], now: Date, calendar: Calendar) -> Bool {
        if let payer, expense.payers[payer] == nil { return false }
        if let category, expense.category != category { return false }
        if let range = dateRange(now: now, calendar: calendar), !range.contains(expense.date) { return false }
        let words = trimmedQuery.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = ([expense.title, expense.note, expense.category.title] + expense.payers.keys.compactMap { names[$0] })
            .joined(separator: " ")
        return words.allSatisfy { haystack.localizedStandardContains($0) }
    }

    func apply(to expenses: [Expense], names: [PersonID: String], now: Date, calendar: Calendar) -> [Expense] {
        guard isActive else { return expenses }
        return expenses.filter { matches($0, names: names, now: now, calendar: calendar) }
    }
}
