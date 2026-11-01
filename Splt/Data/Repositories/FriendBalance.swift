import SpltCore

struct GroupAmounts: Hashable, Sendable, Identifiable {
    var groupID: GroupID
    /// Positive means the friend owes you, one amount per currency.
    var amounts: [Money]

    var id: GroupID { groupID }
}

/// What a friend owes you, or you owe them, across every group you share.
struct FriendBalance: Hashable, Sendable, Identifiable {
    var friendID: PersonID
    /// Positive means the friend owes you. One amount per currency, zeros left out.
    var total: [Money]
    /// The groups behind the total, only those where the two of you are not square.
    var byGroup: [GroupAmounts]

    var id: PersonID { friendID }
    var isSettled: Bool { total.isEmpty }
}
