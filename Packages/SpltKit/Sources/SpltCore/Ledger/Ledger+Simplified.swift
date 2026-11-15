import Synchronization

extension Ledger {
    /// The fewest payments that settle the whole group, per currency, instead of the direct debts in `debts`.
    /// Sorted by currency, then by amount. Worked out once per ledger.
    public var simplifiedDebts: [Debt] {
        if let known = simplified.debts.withLock({ $0 }) { return known }
        let debts = currencies.flatMap { currency in
            let units = (netBalances[currency] ?? [:]).mapValues(\.minorUnits)
            return DebtSimplifier.debts(from: DebtSimplifier.settle(units), currencyCode: currency)
        }
        simplified.debts.withLock { $0 = debts }
        return debts
    }
}

/// Where a ledger keeps its simplified debts once worked out. The ledger never changes, so neither do they.
final class SimplifiedDebts: Sendable {
    let debts = Mutex<[Debt]?>(nil)
}
