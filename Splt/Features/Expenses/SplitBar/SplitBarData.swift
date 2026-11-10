import SpltCore

/// One person's piece of the bar.
struct SplitBarSegment: Identifiable, Equatable {
    var person: Person
    var weight: Int64
    /// What the person owes, when the total is known.
    var amount: Money?
    /// For adjusted splits, how far this person is from an equal share.
    var adjustment: Money?

    var id: PersonID { person.id }
}

/// Everything the Split Bar view draws, worked out from the form.
struct SplitBarData: Equatable {
    var method: SplitMethod
    var segments: [SplitBarSegment]
    /// What the weights add up to.
    var scale: Int64
    var total: Money?
    var canDrag: Bool

    var weights: [Int64] { segments.map(\.weight) }

    /// The two segments either side of a divider, or nil when the bar has no such divider.
    /// A bar can lose people while a divider is still held.
    func neighbors(of divider: Int) -> [SplitBarSegment]? {
        guard divider >= 0, divider + 1 < segments.count else { return nil }
        return Array(segments[divider...(divider + 1)])
    }
}
