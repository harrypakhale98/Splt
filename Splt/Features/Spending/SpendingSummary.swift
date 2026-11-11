import Foundation
import SpltCore

/// What was spent over a range: your share by month, by category and by group, and what the whole
/// group spent and who paid it.
///
/// Amounts are kept in buckets, one per currency. A group's tab keeps each currency apart, because
/// amounts in different currencies can't be added without rates. The all-groups screen converts
/// everything into one currency, and what can't be converted is kept aside in its own currency
/// rather than given a made-up rate.
struct SpendingSummary: Equatable, Sendable {
    /// One currency's figures. Amounts are in minor units of `currencyCode`.
    struct Bucket: Equatable, Sendable, Identifiable {
        var currencyCode: String
        /// Your share. Refunds pull it down.
        var share: Int64 = 0
        /// What the expenses came to, whoever's share it was.
        var total: Int64 = 0
        /// Every expense in the range in this bucket.
        var expenseCount = 0
        /// Your share per month, in the same order as `SpendingSummary.months`.
        var months: [Int64]
        /// Your share per category.
        var categories: [ExpenseCategory: Int64] = [:]
        /// What each person paid, for the whole group.
        var payers: [PersonID: Int64] = [:]
        /// Your share per group.
        var groups: [GroupID: Int64] = [:]

        var id: String { currencyCode }

        var shareMoney: Money { Money(minorUnits: share, currencyCode: currencyCode) }
        var totalMoney: Money { Money(minorUnits: total, currencyCode: currencyCode) }

        func monthMoney(_ index: Int) -> Money {
            Money(minorUnits: months.indices.contains(index) ? months[index] : 0, currencyCode: currencyCode)
        }
    }

    /// The first instant of each month in the range, oldest first.
    var months: [Date]
    /// The lead currency first, then the one with the most expenses, then by code.
    var buckets: [Bucket]
    /// Your share in currencies that could not be converted, in their own currency, by code.
    var notConverted: [String: Int64] = [:]
    /// Your share in other currencies that was converted, as it was before, by code.
    var converted: [String: Int64] = [:]
    /// The currencies converted in each group.
    var convertedByGroup: [GroupID: Set<String>] = [:]
    /// Expenses in the range you had a share of, converted or not.
    var yourExpenseCount = 0
    /// Groups where you had a share of something in the range.
    var yourGroups: Set<GroupID> = []

    var isEmpty: Bool { buckets.isEmpty && notConverted.isEmpty }

    /// Turns a share in an expense's own currency into the bucket's currency. Nil when that is not possible.
    typealias Converter = (_ amount: Money, _ expense: Expense) -> Money?

    /// - Parameters:
    ///   - me: whose share to count. Without one, every share is zero.
    ///   - target: the one currency to convert into, or nil to keep a bucket per currency.
    ///   - convert: how to convert into `target`. Only asked about amounts in other currencies.
    ///   - lead: the currency that goes first when there are several buckets.
    static func make(
        expenses: [Expense],
        me: PersonID?,
        range: SpendingRange,
        now: Date,
        calendar: Calendar,
        target: String? = nil,
        convert: Converter = { _, _ in nil },
        lead: String? = nil
    ) -> SpendingSummary {
        let live = expenses.filter { !$0.isDeleted }
        let months = range.months(now: now, earliest: live.map(\.date).min(), calendar: calendar)
        guard let first = months.first, let end = calendar.dateInterval(of: .month, for: now)?.end else {
            return SpendingSummary(months: [], buckets: [])
        }
        let monthIndex = Dictionary(uniqueKeysWithValues: months.enumerated().map { ($0.element, $0.offset) })
        var summary = SpendingSummary(months: months, buckets: [])
        var buckets: [String: Bucket] = [:]
        let target = target?.uppercased()

        for expense in live where expense.date >= first && expense.date < end {
            guard let month = calendar.dateInterval(of: .month, for: expense.date)?.start,
                  let index = monthIndex[month] else { continue }
            let code = expense.total.currencyCode
            let mine = me.flatMap { try? expense.shares().share(for: $0) } ?? .zero(currencyCode: code)
            let bucketCode = target ?? code
            let isForeign = bucketCode != code

            // what the expense adds to the bucket, in the bucket's currency
            let share: Money?
            let total: Money?
            if isForeign {
                share = mine.minorUnits == 0 ? .zero(currencyCode: bucketCode) : convert(mine, expense)
                total = convert(expense.total, expense)
            } else {
                share = mine
                total = expense.total
            }

            if mine.minorUnits != 0 {
                summary.yourExpenseCount += 1
                if let group = expense.groupID { summary.yourGroups.insert(group) }
                if isForeign {
                    if share == nil {
                        summary.notConverted[code, default: 0] = summary.notConverted[code, default: 0].adding(mine.minorUnits)
                    } else {
                        summary.converted[code, default: 0] = summary.converted[code, default: 0].adding(mine.minorUnits)
                        if let group = expense.groupID { summary.convertedByGroup[group, default: []].insert(code) }
                    }
                }
            }
            // an expense that can't be brought into the bucket stays out of it entirely
            guard let share, let total else { continue }

            var bucket = buckets[bucketCode] ?? Bucket(currencyCode: bucketCode, months: Array(repeating: 0, count: months.count))
            bucket.expenseCount += 1
            bucket.total = bucket.total.adding(total.minorUnits)
            bucket.share = bucket.share.adding(share.minorUnits)
            bucket.months[index] = bucket.months[index].adding(share.minorUnits)
            if share.minorUnits != 0 {
                bucket.categories[expense.category, default: 0] = bucket.categories[expense.category, default: 0]
                    .adding(share.minorUnits)
                if let group = expense.groupID {
                    bucket.groups[group, default: 0] = bucket.groups[group, default: 0].adding(share.minorUnits)
                }
            }
            for (person, paid) in expense.payers {
                let amount: Int64
                if isForeign {
                    guard let converted = convert(paid, expense) else { continue }
                    amount = converted.minorUnits
                } else {
                    amount = paid.minorUnits
                }
                bucket.payers[person, default: 0] = bucket.payers[person, default: 0].adding(amount)
            }
            buckets[bucketCode] = bucket
        }

        summary.buckets = buckets.values.sorted { lhs, rhs in
            let leftLeads = lhs.currencyCode == lead, rightLeads = rhs.currencyCode == lead
            if leftLeads != rightLeads { return leftLeads }
            if lhs.expenseCount != rhs.expenseCount { return lhs.expenseCount > rhs.expenseCount }
            return lhs.currencyCode < rhs.currencyCode
        }
        return summary
    }

    /// Converts with exchange rates found for each expense, such as the rates of its day and its group's pinned rate.
    static func converter(
        into target: String, rates: @escaping (Expense) -> ExchangeRates?
    ) -> Converter {
        { amount, expense in
            guard let rates = rates(expense), rates.rate(from: amount.currencyCode, to: target) != nil else { return nil }
            return try? rates.convert(amount, to: target)
        }
    }
}

extension SpendingSummary.Bucket {
    /// Who paid, largest first, without anyone whose payments cancel out.
    func personRows(names: [PersonID: String]) -> [SpendingRow] {
        let unknown = String(localized: "Someone")
        return payers.filter { $0.value != 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map {
                SpendingRow(
                    id: "person-\($0.key.rawValue.uuidString)", label: names[$0.key] ?? unknown,
                    money: Money(minorUnits: $0.value, currencyCode: currencyCode), personID: $0.key
                )
            }
    }

    /// Your share by category, largest first.
    var categoryRows: [SpendingRow] {
        categories.filter { $0.value != 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
            .map {
                SpendingRow(
                    id: "category-\($0.key.rawValue)", label: $0.key.title,
                    money: Money(minorUnits: $0.value, currencyCode: currencyCode), personID: nil, category: $0.key
                )
            }
    }
}

private extension Int64 {
    func adding(_ other: Int64) -> Int64 {
        let (value, overflow) = addingReportingOverflow(other)
        return overflow ? (other < 0 ? .min : .max) : value
    }
}
