/// Why a payment cannot be used in a ledger.
public enum PaymentError: Error, Equatable, Sendable {
    /// Payer and receiver are the same person.
    case samePerson
    /// The amount is zero or negative.
    case nonPositiveAmount
    /// Adding the payment to the running totals does not fit in 64 bits.
    case overflow
}
