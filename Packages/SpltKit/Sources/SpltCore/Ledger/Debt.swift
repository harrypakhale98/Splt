/// Money one person owes another.
public struct Debt: Hashable, Sendable, Codable {
    public let debtor: PersonID
    public let creditor: PersonID
    public let amount: Money

    public init(debtor: PersonID, creditor: PersonID, amount: Money) {
        self.debtor = debtor
        self.creditor = creditor
        self.amount = amount
    }
}
