/// A direct amount one person owes another because of a single expense or payment.
struct DebtFlow: Hashable, Sendable {
    let debtor: PersonID
    let creditor: PersonID
    let amount: Int64
}

enum PairwiseFlows {
    /// Works out who owes whom for one entry, given each person's paid-minus-owed amount.
    ///
    /// Every debtor repays the creditors in proportion to what is still outstanding to each
    /// of them. Allocating against the remaining amounts keeps the result exact, so each
    /// person's flows add up to precisely their own balance.
    static func flows(for net: [PersonID: Int64]) throws -> [DebtFlow] {
        var remaining = net.filter { $0.value > 0 }
        var result: [DebtFlow] = []
        for debtor in net.keys.sorted() {
            guard let balance = net[debtor], balance < 0 else { continue }
            guard let deficit = Int64(exactly: -Int128(balance)) else { throw MoneyError.overflow }
            let parts = try LargestRemainderAllocator.allocate(total: deficit, weights: remaining)
            for creditor in parts.keys.sorted() {
                guard let amount = parts[creditor], amount > 0 else { continue }
                result.append(DebtFlow(debtor: debtor, creditor: creditor, amount: amount))
                remaining[creditor, default: 0] -= amount
            }
        }
        return result
    }
}
