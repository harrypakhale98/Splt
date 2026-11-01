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

    /// One entry per currency, the one with the most spending first. Deleted expenses are ignored and
    /// refunds reduce what they refund.
    static func make(expenses: [Expense], names: [PersonID: String]) -> [GroupTotals] {
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
        return totals.sorted {
            $0.total.minorUnits != $1.total.minorUnits ? $0.total.minorUnits > $1.total.minorUnits : $0.currencyCode < $1.currencyCode
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

private extension Int64 {
    func addingSaturating(_ other: Int64) -> Int64 {
        let (value, overflow) = addingReportingOverflow(other)
        return overflow ? (other < 0 ? .min : .max) : value
    }
}
