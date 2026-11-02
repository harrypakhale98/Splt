import Foundation
import SpltCore

@MainActor
protocol ExpenseRepository {
    /// Newest first.
    func expenses(in group: GroupID, includeDeleted: Bool) throws -> [Expense]
    /// Expenses in any group where both you and the friend take part, newest first.
    func sharedExpenses(with friend: PersonID) throws -> [Expense]
    func expense(id: ExpenseID) throws -> Expense?
    func details(id: ExpenseID) throws -> ExpenseDetails?

    /// Validates the expense, stores it and writes an activity entry.
    func add(_ expense: Expense, extras: ExpenseExtras) throws
    /// Adds many expenses in one save with a single summary entry per group, for imports and bulk entry.
    /// Nothing is stored if any expense is invalid or already exists.
    func addAll(_ expenses: [Expense]) throws
    /// Stores the edit, appends to the edit history and writes an activity entry.
    /// Pass nil extras to leave the receipt, location and recurrence as they are. Does nothing if nothing changed.
    func update(_ expense: Expense, extras: ExpenseExtras?) throws
    /// Soft deletes the expense. It leaves balances but stays in history.
    func delete(id: ExpenseID) throws
    /// Undoes `delete`.
    func restore(id: ExpenseID) throws

    /// Live expenses in the same group with the same amount and a similar title within a few days of `expense`.
    /// Use it to warn before saving something that looks like a duplicate.
    func duplicates(of expense: Expense, withinDays days: Int) throws -> [Expense]
}

extension ExpenseRepository {
    func expenses(in group: GroupID) throws -> [Expense] {
        try expenses(in: group, includeDeleted: false)
    }

    func add(_ expense: Expense) throws {
        try add(expense, extras: ExpenseExtras())
    }

    func update(_ expense: Expense) throws {
        try update(expense, extras: nil)
    }

    func duplicates(of expense: Expense) throws -> [Expense] {
        try duplicates(of: expense, withinDays: 3)
    }
}
