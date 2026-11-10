import SpltCore

/// Who owes what in one group, built on `Ledger`.
struct GroupBalances: Sendable {
    let groupID: GroupID
    let ledger: Ledger
    let simplifiesDebts: Bool

    /// Net balance per person, keyed by currency. Positive means the person is owed money.
    var netBalances: [String: [PersonID: Money]] { ledger.netBalances }

    var isSettled: Bool { ledger.isSettled }

    /// The payments that would settle the group: the fewest possible when the group simplifies
    /// debts, otherwise the direct debts between pairs.
    var suggestedSettlements: [Debt] {
        simplifiesDebts ? ledger.simplifiedDebts : ledger.debts
    }

    /// What one person is owed (positive) or owes (negative), one amount per currency.
    func net(for person: PersonID) -> [Money] {
        ledger.balances(of: person)
    }

    /// True when the person can go without leaving a debt behind. A group that does not simplify
    /// debts settles pair by pair, so a net of zero is not enough there.
    func isSquare(_ person: PersonID) -> Bool {
        guard ledger.balances(of: person).isEmpty else { return false }
        return simplifiesDebts || ledger.balances(with: person).isEmpty
    }
}
