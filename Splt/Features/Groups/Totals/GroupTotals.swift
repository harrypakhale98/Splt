import Foundation
import SpltCore

/// What a group spent in one currency: in total, by who paid and by category.
struct GroupTotals: Equatable, Sendable, Identifiable {
    struct PersonAmount: Equatable, Sendable, Identifiable {
        var personID: PersonID
        var name: String
        /// What the person paid out of pocket.
        var paid: Money

        var id: PersonID { personID }
    }

    struct CategoryAmount: Equatable, Sendable, Identifiable {
        var category: ExpenseCategory
        var amount: Money

        var id: ExpenseCategory { category }
    }

    var currencyCode: String
    var total: Money
    var expenseCount: Int
    /// Largest first.
    var byPerson: [PersonAmount]
    /// Largest first.
    var byCategory: [CategoryAmount]

    var id: String { currencyCode }

    /// One entry per currency. Deleted expenses are ignored and refunds reduce what they refund.
    /// Amounts in different currencies can't be compared without rates, so the order is the lead
    /// currency (usually the group's own) first, then the currency used by the most expenses, then
    /// by code.
    static func make(expenses: [Expense], names: [PersonID: String], leadCurrency: String? = nil) -> [GroupTotals] {
        struct Accumulator {
            var total: Int64 = 0
            var count = 0
            var paid: [PersonID: Int64] = [:]
            var categories: [ExpenseCategory: Int64] = [:]
        }
        var byCurrency: [String: Accumulator] = [:]
        for expense in expenses where !expense.isDeleted {
            let code = expense.total.currencyCode
            var entry = byCurrency[code, default: Accumulator()]
            entry.total = entry.total.addingSaturating(expense.total.minorUnits)
            entry.count += 1
            entry.categories[expense.category, default: 0] = entry.categories[expense.category, default: 0]
                .addingSaturating(expense.total.minorUnits)
            for (person, amount) in expense.payers {
                entry.paid[person, default: 0] = entry.paid[person, default: 0].addingSaturating(amount.minorUnits)
            }
            byCurrency[code] = entry
        }
        let unknown = String(localized: "Someone")
        let totals = byCurrency.map { code, entry in
            GroupTotals(
                currencyCode: code,
                total: Money(minorUnits: entry.total, currencyCode: code),
                expenseCount: entry.count,
                byPerson: entry.paid
                    .map { PersonAmount(personID: $0.key, name: names[$0.key] ?? unknown, paid: Money(minorUnits: $0.value, currencyCode: code)) }
                    .sorted { $0.paid.minorUnits != $1.paid.minorUnits ? $0.paid.minorUnits > $1.paid.minorUnits : $0.personID < $1.personID },
                byCategory: entry.categories
                    .map { CategoryAmount(category: $0.key, amount: Money(minorUnits: $0.value, currencyCode: code)) }
                    .sorted {
                        $0.amount.minorUnits != $1.amount.minorUnits
                            ? $0.amount.minorUnits > $1.amount.minorUnits
                            : $0.category.rawValue < $1.category.rawValue
                    }
            )
        }
        return ordered(totals, lead: leadCurrency)
    }

    /// The lead currency first, then by number of expenses, then by code.
    static func ordered(_ totals: [GroupTotals], lead: String?) -> [GroupTotals] {
        totals.sorted { lhs, rhs in
            let leftLeads = lhs.currencyCode == lead, rightLeads = rhs.currencyCode == lead
            if leftLeads != rightLeads { return leftLeads }
            if lhs.expenseCount != rhs.expenseCount { return lhs.expenseCount > rhs.expenseCount }
            return lhs.currencyCode < rhs.currencyCode
        }
    }

    /// The facts the on-device summarizer describes.
    func insightInput(groupName: String, kind: GroupKind) -> InsightInput {
        let insightKind: InsightInput.Kind
        switch kind {
        case .trip: insightKind = .trip
        case .couple: insightKind = .household
        case .standard, .friend: insightKind = .other
        }
        return InsightInput(
            groupName: groupName,
            kind: insightKind,
            expenseCount: expenseCount,
            categories: byCategory.map { InsightInput.CategoryAmount(name: $0.category.title, minorUnits: $0.amount.minorUnits) },
            members: byPerson.map { InsightInput.MemberAmount(name: $0.name, paidMinorUnits: $0.paid.minorUnits) }
        )
    }
}

/// One row of a spending chart: a person or a category and what it adds to the total.
struct SpendingRow: Equatable, Sendable, Identifiable {
    /// The person or category the row stands for. Two people can share a name, so the name is only the label.
    var id: String
    var label: String
    /// Signed: a refund is negative and pulls the total down.
    var money: Money
    var personID: PersonID?

    /// The amount as printed beside the bar, with a minus sign for a refund so it never reads as spending.
    func amountText(locale: Locale) -> String {
        MoneyFormatting.string(money, locale: locale, showsSign: money.minorUnits < 0)
    }

    /// One sentence for VoiceOver covering every row, with refunds named as such.
    static func spokenSummary(_ rows: [SpendingRow], locale: Locale) -> String {
        rows.map { row in
            let amount = MoneyFormatting.magnitudeString(row.money, locale: locale)
            return row.money.minorUnits < 0
                ? String(localized: "\(row.label), refund \(amount)")
                : String(localized: "\(row.label), \(amount)")
        }
        .joined(separator: "; ")
    }

    /// Labels that are never repeated, since a chart's categories must be distinct.
    static func distinctLabels(_ rows: [SpendingRow]) -> [String] {
        var seen: [String: Int] = [:]
        return rows.map { row in
            let count = seen[row.label, default: 0] + 1
            seen[row.label] = count
            return count == 1 ? row.label : "\(row.label) (\(count))"
        }
    }
}

extension GroupTotals {
    /// Everyone whose payments did not cancel out, refunds included, so the rows add up to `total`.
    var personRows: [SpendingRow] {
        byPerson.filter { $0.paid.minorUnits != 0 }.map {
            SpendingRow(id: "person-\($0.personID.rawValue.uuidString)", label: $0.name, money: $0.paid, personID: $0.personID)
        }
    }

    /// Every category that did not cancel out, refunds included, so the rows add up to `total`.
    var categoryRows: [SpendingRow] {
        byCategory.filter { $0.amount.minorUnits != 0 }.map {
            SpendingRow(id: "category-\($0.category.rawValue)", label: $0.category.title, money: $0.amount, personID: nil)
        }
    }
}

/// Where each bar of a spending chart starts and how long it is, as fractions of the chart's width.
/// Refunds run left from a zero line, so every bar is to scale and together they add up to the total.
struct SpendingScale: Equatable, Sendable {
    /// Where zero sits, from 0 (the left edge) to 1.
    let zero: Double
    let lowest: Int64
    let highest: Int64

    init(values: [Int64]) {
        lowest = min(0, values.min() ?? 0)
        highest = max(0, values.max() ?? 0)
        let span = Double(highest) - Double(lowest)
        zero = span > 0 ? -Double(lowest) / span : 0
    }

    /// Whether any bar runs left of zero, which is when the zero line is drawn.
    var hasNegatives: Bool { lowest < 0 }

    func bar(for value: Int64) -> (start: Double, length: Double) {
        let span = Double(highest) - Double(lowest)
        guard span > 0 else { return (zero, 0) }
        let length = Double(value.magnitude) / span
        return (value < 0 ? zero - length : zero, length)
    }
}

private extension Int64 {
    func addingSaturating(_ other: Int64) -> Int64 {
        let (value, overflow) = addingReportingOverflow(other)
        return overflow ? (other < 0 ? .min : .max) : value
    }
}
