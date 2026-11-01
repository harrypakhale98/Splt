/// Why balances cannot be simplified.
public enum DebtSimplifierError: Error, Equatable, Sendable {
    /// The balances mix currencies. Simplify one currency at a time.
    case mixedCurrencies(String, String)
    /// The balances do not add up to zero, so they cannot be settled between these people.
    case balancesDoNotSumToZero(currencyCode: String, difference: Int64)
}
