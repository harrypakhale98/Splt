/// Errors from money arithmetic.
public enum MoneyError: Error, Equatable, Sendable {
    /// Two amounts in different currencies were combined.
    case currencyMismatch(String, String)
    /// The result does not fit in 64 bit minor units.
    case overflow
}
