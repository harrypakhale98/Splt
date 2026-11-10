/// Turns balances into a short list of payments that settles everyone.
///
/// The greedy pass pays the largest debt to the largest credit until nothing is left. For
/// groups of up to 12 people with open balances it also searches for the fewest possible
/// payments, by splitting the group into as many independent zero-sum circles as it can,
/// and keeps whichever answer needs fewer payments. Results are deterministic: ties are
/// broken by person id and the output is sorted by amount, then debtor, then creditor.
public enum DebtSimplifier {
    /// Settles balances that share one currency. Positive balances are owed money, negative balances owe.
    public static func simplify(_ balances: [PersonID: Money]) throws -> [Debt] {
        guard let currencyCode = balances.values.first?.currencyCode else { return [] }
        var units: [PersonID: Int64] = [:]
        var difference: Int128 = 0
        for (person, amount) in balances {
            guard amount.currencyCode == currencyCode else {
                throw DebtSimplifierError.mixedCurrencies(currencyCode, amount.currencyCode)
            }
            // The smallest 64 bit number has no positive twin, so it cannot be paid back.
            guard amount.minorUnits != .min else { throw DebtSimplifierError.amountOutOfRange }
            units[person] = amount.minorUnits
            difference += Int128(amount.minorUnits)
        }
        guard difference == 0 else {
            throw DebtSimplifierError.balancesDoNotSumToZero(
                currencyCode: currencyCode, difference: Int64(clamping: difference)
            )
        }
        return debts(from: settle(units), currencyCode: currencyCode)
    }

    /// Settles each currency on its own, as returned by `Ledger.netBalances`.
    public static func simplify(_ balancesByCurrency: [String: [PersonID: Money]]) throws -> [Debt] {
        try balancesByCurrency.keys.sorted().flatMap { try simplify(balancesByCurrency[$0] ?? [:]) }
    }

    /// The plain greedy answer, without the exact search. Mostly useful for comparison.
    public static func greedy(_ balances: [PersonID: Money]) throws -> [Debt] {
        guard let currencyCode = balances.values.first?.currencyCode else { return [] }
        for amount in balances.values {
            guard amount.currencyCode == currencyCode else {
                throw DebtSimplifierError.mixedCurrencies(currencyCode, amount.currencyCode)
            }
            guard amount.minorUnits != .min else { throw DebtSimplifierError.amountOutOfRange }
        }
        return debts(from: GreedySettlement.transfers(for: balances.mapValues(\.minorUnits)), currencyCode: currencyCode)
    }

    /// Settles balances that are already known to add up to zero.
    static func settle(_ balances: [PersonID: Int64]) -> [DebtFlow] {
        let greedy = GreedySettlement.transfers(for: balances)
        if let exact = ExactSettlement.transfers(for: balances), exact.count < greedy.count {
            return exact
        }
        return greedy
    }

    static func debts(from flows: [DebtFlow], currencyCode: String) -> [Debt] {
        flows
            .map { Debt(debtor: $0.debtor, creditor: $0.creditor, amount: Money(minorUnits: $0.amount, currencyCode: currencyCode)) }
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount { return lhs.amount.minorUnits > rhs.amount.minorUnits }
                if lhs.debtor != rhs.debtor { return lhs.debtor < rhs.debtor }
                return lhs.creditor < rhs.creditor
            }
    }
}
