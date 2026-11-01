/// How one person's share of an itemized bill is made up.
public struct ShareBreakdown: Hashable, Sendable, Codable {
    public let items: Money
    public let tax: Money
    public let tip: Money
    public let discount: Money
    /// Items plus tax plus tip minus discount.
    public let total: Money

    public init(items: Money, tax: Money, tip: Money, discount: Money, total: Money) {
        self.items = items
        self.tax = tax
        self.tip = tip
        self.discount = discount
        self.total = total
    }
}
