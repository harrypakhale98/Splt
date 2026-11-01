/// What each person owes for one expense. Shares always add up exactly to the total.
public struct ShareResult: Hashable, Sendable, Codable {
    public let total: Money
    public let shares: [PersonID: Money]
    /// Per person detail for itemized splits, nil for every other strategy.
    public let breakdown: [PersonID: ShareBreakdown]?

    public init(total: Money, shares: [PersonID: Money], breakdown: [PersonID: ShareBreakdown]? = nil) {
        self.total = total
        self.shares = shares
        self.breakdown = breakdown
    }

    /// One person's share, zero if they are not in the split.
    public func share(for person: PersonID) -> Money {
        shares[person] ?? .zero(currencyCode: total.currencyCode)
    }
}
