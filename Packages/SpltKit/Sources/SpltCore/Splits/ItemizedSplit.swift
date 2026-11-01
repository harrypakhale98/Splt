/// A bill split by line item, with tax, tip and discount spread in proportion to what each person ordered.
///
/// The expense total must equal items plus tax plus tip minus discount. Amounts must not be
/// negative, so refunds cannot be itemized; use another strategy for those.
public struct ItemizedSplit: Hashable, Sendable, Codable {
    public var items: [SplitItem]
    public var tax: Money?
    public var tip: Money?
    /// An amount taken off the bill, entered as a positive number.
    public var discount: Money?

    public init(items: [SplitItem], tax: Money? = nil, tip: Money? = nil, discount: Money? = nil) {
        self.items = items
        self.tax = tax
        self.tip = tip
        self.discount = discount
    }

    /// Everyone who has at least one item.
    public var participants: Set<PersonID> {
        items.reduce(into: Set<PersonID>()) { $0.formUnion($1.assignees) }
    }
}
