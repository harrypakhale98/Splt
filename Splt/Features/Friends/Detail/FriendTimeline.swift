import Foundation
import SpltCore

/// Shared expenses grouped by month, newest first, for the timeline on a friend's screen.
enum FriendTimeline {
    struct Month: Identifiable, Equatable {
        var start: Date
        var expenses: [Expense]

        var id: Date { start }
    }

    static func months(_ expenses: [Expense], calendar: Calendar = .current) -> [Month] {
        var result: [Month] = []
        for expense in expenses.sorted(by: { ($0.date, $0.id) > ($1.date, $1.id) }) {
            let start = calendar.dateInterval(of: .month, for: expense.date)?.start ?? expense.date
            if let last = result.last, last.start == start {
                result[result.count - 1].expenses.append(expense)
            } else {
                result.append(Month(start: start, expenses: [expense]))
            }
        }
        return result
    }
}
