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

    mutating func clearFilters() {
        payer = nil
        category = nil
        period = .anytime
    }

    var trimmedQuery: String {
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
        let words = trimmedQuery.split(whereSeparator: \.isWhitespace)
        return matches(expense, range: dateRange(now: now, calendar: calendar), words: words) {
            Self.searchText(of: expense, names: names)
        }
    }

    /// Everything a search looks through for one expense: its title, note, category and who paid.
    static func searchText(of expense: Expense, names: [PersonID: String]) -> String {
        ([expense.title, expense.note, expense.category.title] + expense.payers.keys.compactMap { names[$0] })
            .joined(separator: " ")
    }

    /// The date range and search words are worked out once for the whole list, and `searchTexts`, kept by the
    /// screen per load, saves building each expense's text again on every key typed.
    func apply(
        to expenses: [Expense], names: [PersonID: String], now: Date, calendar: Calendar,
        searchTexts: [ExpenseID: String] = [:]
    ) -> [Expense] {
        guard isActive else { return expenses }
        let range = dateRange(now: now, calendar: calendar)
        let words = trimmedQuery.split(whereSeparator: \.isWhitespace)
        return expenses.filter { expense in
            matches(expense, range: range, words: words) {
                searchTexts[expense.id] ?? Self.searchText(of: expense, names: names)
            }
        }
    }

    private func matches(
        _ expense: Expense, range: Range<Date>?, words: [Substring], text: () -> String
    ) -> Bool {
        if let payer, expense.payers[payer] == nil { return false }
        if let category, expense.category != category { return false }
        if let range, !range.contains(expense.date) { return false }
        guard !words.isEmpty else { return true }
        let haystack = text()
        return words.allSatisfy { haystack.localizedStandardContains($0) }
    }
}
