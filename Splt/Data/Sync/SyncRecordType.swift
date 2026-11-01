import Foundation

/// The kinds of record that take part in sync. The raw value is the CloudKit record type name.
enum SyncRecordType: String, CaseIterable, Hashable, Sendable {
    case person = "Person"
    case group = "Group"
    case expense = "Expense"
    case payment = "Payment"
    case comment = "Comment"
    case activity = "Activity"
    case recurringExpense = "RecurringExpense"
}
