import Foundation
import SpltCore

/// A short look back at a trip: what it cost and where the money went.
struct TripRecap: Equatable, Sendable {
    var total: Money
    var expenseCount: Int
    var dayCount: Int
    var averagePerDay: Money
    var topCategory: GroupTotals.CategoryAmount?
    var biggestExpenseTitle: String?
    var biggestExpense: Money?

    /// Nil when the group is not a trip or has no spending in its own currency yet.
    init?(group: SplitGroup, expenses: [Expense], now: Date, calendar: Calendar) {
        guard group.kind == .trip else { return nil }
        let live = expenses.filter { !$0.isDeleted && $0.total.currencyCode == group.currencyCode }
        guard !live.isEmpty else { return nil }
        let totals = GroupTotals.make(expenses: live, names: [:])
        guard let summary = totals.first else { return nil }

        let first = calendar.startOfDay(for: group.tripStart ?? live.map(\.date).min() ?? now)
        let today = calendar.startOfDay(for: now)
        var last = max(today, first)
        if let end = group.tripEnd {
            last = min(last, max(calendar.startOfDay(for: end), first))
        }
        let days = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1

        total = summary.total
        expenseCount = summary.expenseCount
        dayCount = max(days, 1)
        averagePerDay = Money(minorUnits: summary.total.minorUnits / Int64(max(days, 1)), currencyCode: group.currencyCode)
        topCategory = summary.byCategory.first { $0.amount.minorUnits > 0 }
        let biggest = live.max { $0.total.minorUnits < $1.total.minorUnits }
        biggestExpenseTitle = biggest?.title
        biggestExpense = biggest?.total
    }
}
