/// Why an expense cannot be used in a ledger.
public enum ExpenseError: Error, Equatable, Sendable {
    /// Nobody is recorded as having paid.
    case noPayers
    /// A payer amount uses a different currency than the total.
    case currencyMismatch(expected: String, found: String)
    /// What the payers paid does not add up to the total.
    case payersDoNotMatchTotal(expected: Money, actual: Money)
    /// A payer amount is negative on a purchase or positive on a refund.
    case payerAmountPointsWrongWay(PersonID)
    /// The split definition is invalid for this total.
    case invalidSplit(SplitError)
    /// A calculation does not fit in 64 bits.
    case overflow
}
