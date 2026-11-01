import SpltCore

/// How the expense form opens: a new expense in a group, or an existing expense to change.
enum ExpenseFormMode: Hashable, Sendable {
    /// A new expense. `prefill` fills in whatever is already known, for example from a duplicate or a scan.
    case add(groupID: GroupID, prefill: ExpenseDraft?)
    case edit(ExpenseID)
}
