enum GreedySettlement {
    /// Repeatedly pays the largest outstanding debt to the largest outstanding credit.
    /// Ties go to the lower person id, so the result is the same on every device.
    static func transfers(for balances: [PersonID: Int64]) -> [DebtFlow] {
        var creditors = balances.filter { $0.value > 0 }.map { (person: $0.key, amount: $0.value) }
        var debtors = balances.filter { $0.value < 0 }.map { (person: $0.key, amount: -$0.value) }
        var result: [DebtFlow] = []

        while !creditors.isEmpty && !debtors.isEmpty {
            let creditorIndex = largest(creditors)
            let debtorIndex = largest(debtors)
            let amount = min(creditors[creditorIndex].amount, debtors[debtorIndex].amount)
            result.append(DebtFlow(
                debtor: debtors[debtorIndex].person,
                creditor: creditors[creditorIndex].person,
                amount: amount
            ))
            creditors[creditorIndex].amount -= amount
            debtors[debtorIndex].amount -= amount
            if creditors[creditorIndex].amount == 0 { creditors.remove(at: creditorIndex) }
            if debtors[debtorIndex].amount == 0 { debtors.remove(at: debtorIndex) }
        }
        return result
    }

    private static func largest(_ entries: [(person: PersonID, amount: Int64)]) -> Int {
        var best = 0
        for index in entries.indices.dropFirst() {
            let candidate = entries[index]
            let current = entries[best]
            if candidate.amount > current.amount || (candidate.amount == current.amount && candidate.person < current.person) {
                best = index
            }
        }
        return best
    }
}
