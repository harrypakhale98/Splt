import SpltCore

/// Why a repository call could not be completed.
enum DataError: Error, Equatable, Sendable {
    case notFound(String)
    case invalidExpense(ExpenseError)
    case invalidPayment(PaymentError)
    /// A stored blob could not be decoded, for example data written by a newer app version.
    case corruptRecord(String)
    case memberStillHasBalance(PersonID)
    /// A recurring expense, named here, would keep charging the person after they left the group.
    case memberOnRecurringExpense(String)
    /// Every expense and payment belongs to a group; friends without a shared group use a hidden friend group.
    case missingGroup
    case alreadyExists(String)
    case unreadableCSV(String)
}
