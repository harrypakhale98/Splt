extension Ledger {
    /// The fewest payments that settle the whole group, per currency, instead of the direct debts in `debts`.
    /// Sorted by currency, then by amount.
    public var simplifiedDebts: [Debt] {
        currencies.flatMap { currency in
            let units = (netBalances[currency] ?? [:]).mapValues(\.minorUnits)
            return DebtSimplifier.debts(from: DebtSimplifier.settle(units), currencyCode: currency)
        }
    }
}
