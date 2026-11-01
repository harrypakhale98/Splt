import SpltCore

/// How the expense form opens: a new expense in a group, an existing expense to change, or a recurring template.
enum ExpenseFormMode: Hashable, Sendable {
    /// A new expense. `prefill` fills in whatever is already known, for example from a duplicate or a scan.
    case add(groupID: GroupID, prefill: ExpenseDraft?)
    case edit(ExpenseID)
    /// A recurring template, from the recurring expenses list.
    case editRecurring(RecurringExpense)
}
