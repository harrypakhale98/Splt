import SpltCore

/// The expense an event is about, with enough detail to show a row without loading the expense.
struct ExpenseReference: Hashable, Sendable, Codable {
    var id: ExpenseID
    var title: String
    var amount: Money
    /// What an edit changed, field by field. Only `expenseEdited` sets it, from version 1.1 on.
    /// Left out of the JSON when nil, so every other event is stored exactly as before, and
    /// version 1.0 ignores the key when it reads an edit.
    var changes: ExpenseChanges? = nil
}

struct PaymentReference: Hashable, Sendable, Codable {
    var id: PaymentID
    var payer: PersonID
    var receiver: PersonID
    var amount: Money
}

enum ActivityKind: String, Hashable, Sendable, Codable, CaseIterable {
    case groupCreated
    case groupRenamed
    case groupArchived
    case groupRestored
    case memberAdded
    case memberRemoved
    case expenseAdded
    case expenseEdited
    case expenseDeleted
    case expenseRestored
    case paymentRecorded
    case paymentUndone
    case commentAdded
    case expensesImported
    case reminderSent
}

/// Something that happened in a group, with the details needed to describe it.
enum ActivityEvent: Hashable, Sendable, Codable {
    case groupCreated(name: String)
    case groupRenamed(from: String, to: String)
    case groupArchived
    case groupRestored
    case memberAdded(PersonID)
    case memberRemoved(PersonID)
    case expenseAdded(ExpenseReference)
    case expenseEdited(ExpenseReference)
    case expenseDeleted(ExpenseReference)
    case expenseRestored(ExpenseReference)
    case paymentRecorded(PaymentReference)
    case paymentUndone(PaymentReference)
    case commentAdded(expense: ExpenseReference?, text: String)
    case expensesImported(expenses: Int, payments: Int)
    /// Someone asked `to` to pay them back what they owe in this group, one amount per currency.
    /// Version 1.0 can't read it and leaves the row out of its feed.
    case reminderSent(to: PersonID, amounts: [Money])

    var kind: ActivityKind {
        switch self {
        case .groupCreated: .groupCreated
        case .groupRenamed: .groupRenamed
        case .groupArchived: .groupArchived
        case .groupRestored: .groupRestored
        case .memberAdded: .memberAdded
        case .memberRemoved: .memberRemoved
        case .expenseAdded: .expenseAdded
        case .expenseEdited: .expenseEdited
        case .expenseDeleted: .expenseDeleted
        case .expenseRestored: .expenseRestored
        case .paymentRecorded: .paymentRecorded
        case .paymentUndone: .paymentUndone
        case .commentAdded: .commentAdded
        case .expensesImported: .expensesImported
        case .reminderSent: .reminderSent
        }
    }
}
