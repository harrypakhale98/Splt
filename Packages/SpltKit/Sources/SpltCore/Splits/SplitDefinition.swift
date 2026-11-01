/// How an expense total is divided between people.
public enum SplitDefinition: Hashable, Sendable, Codable {
    /// The same amount each, for the listed people.
    case equal(participants: Set<PersonID>)
    /// Fixed amounts that must add up to the total.
    case exact(amounts: [PersonID: Money])
    /// Percentages in basis points (2500 is 25 percent) that must add up to 10000.
    case percentages(basisPoints: [PersonID: Int64])
    /// Proportional weights. Use whole numbers; scale fractions, so 1.5 and 1 become 3 and 2.
    case shares(weights: [PersonID: Int64])
    /// An equal split of whatever is left after each person's own plus or minus amount.
    case adjustments(participants: Set<PersonID>, adjustments: [PersonID: Money])
    /// Line items assigned to people, with tax, tip and discount spread proportionally.
    case itemized(ItemizedSplit)

    /// Everyone who takes part in the split.
    public var participants: Set<PersonID> {
        switch self {
        case .equal(let participants): participants
        case .exact(let amounts): Set(amounts.keys)
        case .percentages(let basisPoints): Set(basisPoints.keys)
        case .shares(let weights): Set(weights.keys)
        case .adjustments(let participants, _): participants
        case .itemized(let itemized): itemized.participants
        }
    }
}
