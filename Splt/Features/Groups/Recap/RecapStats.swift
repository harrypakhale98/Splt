import Foundation
import SpltCore

/// The numbers behind the recap story, worked out in plain code so they can be tested.
/// Everything is in one currency: the group's own when it has spending, otherwise the one with the
/// most, the same one the totals use. Spending in other currencies is named in `leftOut`. Deleted
/// expenses are ignored.
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

    struct Payer: Equatable, Sendable {
        var id: PersonID
        var name: String
    }

    struct TopPayer: Equatable, Sendable {
        var id: PersonID
        var name: String
        var paid: Money
        /// Whole percent of everything paid, which can pass 100 only when refunds are involved.
        var percent: Int
        /// Others who paid exactly as much, so the top spot is shared. Empty when one person paid the most.
        var tiedWith: [Payer] = []

        /// Everyone in the top spot, the first payer first.
        var everyone: [Payer] { [Payer(id: id, name: name)] + tiedWith }
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
    /// The total over the number of days, or of months in month view.
    var average: Money
    var busiest: Slice?
    var biggest: Biggest?
    var topPayer: TopPayer?
    /// Largest first, at most four, then everything else together. The percents add up to 100.
    var categories: [CategoryShare]
    var first: Date
    var last: Date
    /// What was spent in each other currency, which the recap does not count. Largest first.
    var leftOut: [Money]

    /// Nil when nothing was spent.
    init?(
        group: SplitGroup, expenses: [Expense], names: [PersonID: String], now: Date, calendar: Calendar
    ) {
        let all = GroupTotals.make(expenses: expenses, names: names, leadCurrency: group.currencyCode)
        guard let summary = all.first(where: { $0.currencyCode == group.currencyCode }) ?? all.first else { return nil }
        let code = summary.currencyCode
        let live = expenses.filter { !$0.isDeleted && $0.total.currencyCode == code }
        guard !live.isEmpty else { return nil }
        currencyCode = code
        total = summary.total
        expenseCount = summary.expenseCount
        leftOut = all.filter { $0.currencyCode != code && $0.total.minorUnits != 0 }.map(\.total)

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
            totals[key] = overflow ? (expense.total.minorUnits < 0 ? Int64.min : Int64.max) : value
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
        // one slice per day or per month, so the average is per day or per month to match the line
        average = Money(minorUnits: summary.total.minorUnits / Int64(max(built.count, 1)), currencyCode: code)
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
            let tied = summary.byPerson.dropFirst()
                .prefix { $0.paid.minorUnits == person.paid.minorUnits }
                .map { Payer(id: $0.personID, name: $0.name) }
            return TopPayer(
                id: person.personID, name: person.name, paid: person.paid,
                percent: InsightSummarizer.percent(person.paid.minorUnits, of: paidTotal),
                tiedWith: Array(tied)
            )
        }

        let positive = summary.byCategory.filter { $0.amount.minorUnits > 0 }
        var kept = positive.prefix(4).map { (category: $0.category, units: $0.amount.minorUnits) }
        let rest = positive.dropFirst(4)
        if !rest.isEmpty {
            // everything past the top four joins one "other" entry at the end, taking in the
            // category's own "other" when that made the top four, so no category shows twice
            // The sums wrap rather than trap on amounts nobody could have entered.
            var units = rest.reduce(Int64(0)) { $0 &+ $1.amount.minorUnits }
            if let index = kept.firstIndex(where: { $0.category == .other }) {
                units &+= kept.remove(at: index).units
            }
            kept.append((category: .other, units: units))
        }
        let percents = Self.wholePercents(kept.map { $0.units })
        categories = zip(kept, percents).map { entry, percent in
            CategoryShare(category: entry.category, amount: Money(minorUnits: entry.units, currencyCode: code), percent: percent)
        }
    }

    var dayCount: Int {
        max((slices.count), 1)
    }

    /// Whole percents of each part that add up to exactly 100: each part gets its rounded-down
    /// share, then the parts with the largest remainders get one more until the total is 100.
    /// Parts must not be negative. All zeros when the parts add up to nothing.
    static func wholePercents(_ parts: [Int64]) -> [Int] {
        let whole = parts.reduce(Int64(0)) { $0.addingReportingOverflow($1).overflow ? .max : $0 + $1 }
        guard whole > 0 else { return parts.map { _ in 0 } }
        var floors: [Int] = []
        var remainders: [Int64] = []
        for part in parts {
            let wide = max(part, 0).multipliedFullWidth(by: 100)
            let (quotient, remainder) = whole.dividingFullWidth(wide)
            floors.append(Int(quotient))
            remainders.append(remainder)
        }
        let missing = 100 - floors.reduce(0, +)
        guard missing > 0 else { return floors }
        let order = remainders.indices.sorted { remainders[$0] != remainders[$1] ? remainders[$0] > remainders[$1] : $0 < $1 }
        for index in order.prefix(missing) { floors[index] += 1 }
        return floors
    }
}

extension RecapStats {
    /// The height a slice is drawn at, in whole units of the currency.
    static func chartValue(_ money: Money) -> Double {
        NSDecimalNumber(decimal: money.decimalValue).doubleValue
    }

    /// One value range for every chart of the slices, so the story and the share card share a baseline:
    /// from zero, or a little below the biggest refund day, to a little above the busiest day.
    var chartDomain: ClosedRange<Double> {
        let values = slices.map { Self.chartValue($0.total) }
        let high = max(values.max() ?? 0, 0)
        let low = min(values.min() ?? 0, 0)
        let top = high > 0 ? high * 1.1 : (low < 0 ? 0 : 1)
        return (low < 0 ? low * 1.1 : 0)...top
    }

    /// About five evenly spaced slice starts for the date axis, always including the first.
    var axisDates: [Date] {
        guard !slices.isEmpty else { return [] }
        let step = max(Int((Double(slices.count) / 5).rounded(.up)), 1)
        return stride(from: 0, to: slices.count, by: step).map { slices[$0].start }
    }
}
