import Foundation
import SpltCore

/// The numbers behind the recap story, worked out in plain code so they can be tested.
/// Everything is in the group's currency. Deleted expenses are ignored.
struct RecapStats: Equatable, Sendable {
    enum Bucket: Equatable, Sendable {
        case day
        case month
    }

    struct Slice: Equatable, Sendable, Identifiable {
        var start: Date
        var total: Money
        var id: Date { start }
    }

    struct Biggest: Equatable, Sendable {
        var title: String
        var amount: Money
        var date: Date
        var category: ExpenseCategory
        var payerName: String?
    }

    struct TopPayer: Equatable, Sendable {
        var id: PersonID
        var name: String
        var paid: Money
        /// Whole percent of everything paid, which can pass 100 only when refunds are involved.
        var percent: Int
    }

    struct CategoryShare: Equatable, Sendable, Identifiable {
        var category: ExpenseCategory
        var amount: Money
        var percent: Int
        var id: ExpenseCategory { category }
    }

    var currencyCode: String
    var total: Money
    var expenseCount: Int
    /// Oldest first, with an entry for every day or month in between so a sparkline has no gaps.
    var slices: [Slice]
    var bucket: Bucket
    var average: Money
    var busiest: Slice?
    var biggest: Biggest?
    var topPayer: TopPayer?
    /// Largest first, at most four, then everything else together.
    var categories: [CategoryShare]
    var first: Date
    var last: Date

    /// Nil when there is no spending in the group's currency.
    init?(
        group: SplitGroup, expenses: [Expense], names: [PersonID: String], now: Date, calendar: Calendar
    ) {
        let live = expenses.filter { !$0.isDeleted && $0.total.currencyCode == group.currencyCode }
        guard let summary = GroupTotals.make(expenses: live, names: names).first, !live.isEmpty else { return nil }
        let code = group.currencyCode
        currencyCode = code
        total = summary.total
        expenseCount = summary.expenseCount

        let dates = live.map(\.date)
        var start = calendar.startOfDay(for: group.tripStart ?? dates.min() ?? now)
        var end = calendar.startOfDay(for: group.tripEnd ?? dates.max() ?? now)
        if let early = dates.min(), calendar.startOfDay(for: early) < start { start = calendar.startOfDay(for: early) }
        if let late = dates.max(), calendar.startOfDay(for: late) > end { end = calendar.startOfDay(for: late) }
        if end < start { end = start }
        first = start
        last = end

        let spanDays = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        bucket = spanDays > 62 ? .month : .day
        let component: Calendar.Component = bucket == .day ? .day : .month

        var totals: [Date: Int64] = [:]
        for expense in live {
            let key = calendar.dateInterval(of: component, for: expense.date)?.start ?? expense.date
            let (value, overflow) = totals[key, default: 0].addingReportingOverflow(expense.total.minorUnits)
            totals[key] = overflow ? Int64.max : value
        }
        var built: [Slice] = []
        var cursor = calendar.dateInterval(of: component, for: start)?.start ?? start
        let limit = calendar.dateInterval(of: component, for: end)?.start ?? end
        while cursor <= limit, built.count < 400 {
            built.append(Slice(start: cursor, total: Money(minorUnits: totals[cursor] ?? 0, currencyCode: code)))
            // Not by adding a day: after a clock change at midnight that lands an hour off the next day's start.
            guard let next = calendar.dateInterval(of: component, for: cursor)?.end else { break }
            cursor = next
        }
        slices = built
        let dayCount = bucket == .day ? max(built.count, 1) : max(spanDays, 1)
        average = Money(minorUnits: summary.total.minorUnits / Int64(dayCount), currencyCode: code)
        busiest = built.filter { $0.total.minorUnits > 0 }.max {
            $0.total.minorUnits != $1.total.minorUnits ? $0.total.minorUnits < $1.total.minorUnits : $0.start > $1.start
        }

        let biggestExpense = live.max { $0.total.minorUnits < $1.total.minorUnits }
        biggest = biggestExpense.map { expense in
            let payer = expense.payers.max { $0.value.minorUnits < $1.value.minorUnits }?.key
            return Biggest(
                title: expense.title, amount: expense.total, date: expense.date, category: expense.category,
                payerName: payer.flatMap { names[$0] }
            )
        }

        let paidTotal = summary.byPerson.reduce(Int64(0)) { $0 &+ max($1.paid.minorUnits, 0) }
        topPayer = summary.byPerson.first.flatMap { person in
            guard person.paid.minorUnits > 0, paidTotal > 0 else { return nil }
            return TopPayer(
                id: person.personID, name: person.name, paid: person.paid,
                percent: InsightSummarizer.percent(person.paid.minorUnits, of: paidTotal)
            )
        }

        let positive = summary.byCategory.filter { $0.amount.minorUnits > 0 }
        let categoryTotal = positive.reduce(Int64(0)) { $0 &+ $1.amount.minorUnits }
        var shares = positive.prefix(4).map {
            CategoryShare(
                category: $0.category, amount: $0.amount,
                percent: InsightSummarizer.percent($0.amount.minorUnits, of: categoryTotal)
            )
        }
        let rest = positive.dropFirst(4)
        if !rest.isEmpty {
            let units = rest.reduce(Int64(0)) { $0 &+ $1.amount.minorUnits }
            shares.append(CategoryShare(
                category: .other, amount: Money(minorUnits: units, currencyCode: code),
                percent: InsightSummarizer.percent(units, of: categoryTotal)
            ))
        }
        categories = shares
    }

    var dayCount: Int {
        max((slices.count), 1)
    }
}
