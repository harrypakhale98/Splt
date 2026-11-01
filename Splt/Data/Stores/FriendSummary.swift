import SpltCore

/// A friend row, ready to show.
struct FriendSummary: Hashable, Sendable, Identifiable {
    var person: Person
    /// What the friend owes you across every group. Positive means they owe you.
    var balance: [Money]
    var byGroup: [GroupAmounts]

    var id: PersonID { person.id }
    var isSettled: Bool { balance.isEmpty }
}
