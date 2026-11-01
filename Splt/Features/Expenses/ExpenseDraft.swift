import Foundation
import SpltCore

/// Starting values for the expense form. Every field is optional; the form fills the rest
/// with the group's currency, today's date, you as the payer and an equal split.
struct ExpenseDraft: Hashable, Sendable {
    var title: String = ""
    var total: Money?
    var date: Date?
    var category: ExpenseCategory?
    var note: String = ""
    /// Empty means you paid.
    var payers: [PersonID: Money] = [:]
    /// Nil means an equal split between the whole group.
    var split: SplitDefinition?

    init(
        title: String = "",
        total: Money? = nil,
        date: Date? = nil,
        category: ExpenseCategory? = nil,
        note: String = "",
        payers: [PersonID: Money] = [:],
        split: SplitDefinition? = nil
    ) {
        self.title = title
        self.total = total
        self.date = date
        self.category = category
        self.note = note
        self.payers = payers
        self.split = split
    }

    /// A copy of an existing expense, for "duplicate". The date becomes today.
    init(copying expense: Expense) {
        self.init(
            title: expense.title, total: expense.total, date: nil, category: expense.category,
            note: expense.note, payers: expense.payers, split: expense.split
        )
    }
}
