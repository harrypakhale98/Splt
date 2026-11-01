import Foundation
import SpltCore

/// An expense row, ready to show.
struct ExpenseRow: Hashable, Sendable, Identifiable {
    var expense: Expense
    /// Who paid, in a stable order.
    var payers: [Person]
    var paidByMe: Bool
    /// What you paid minus what you owe. Nil when you are not part of the expense.
    var myNet: Money?

    var id: ExpenseID { expense.id }
}
