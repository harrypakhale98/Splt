/// An entry the ledger skipped because it could not be used.
public enum LedgerIssue: Equatable, Sendable {
    case expense(ExpenseID, ExpenseError)
    case payment(PaymentID, PaymentError)
}
