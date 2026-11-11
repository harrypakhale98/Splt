import Foundation
import SpltCore

/// A group row, ready to show.
struct GroupSummary: Hashable, Sendable, Identifiable {
    var group: SplitGroup
    var memberCount: Int
    /// Your net balance, one amount per currency. Positive means the group owes you.
    var myBalance: [Money]
    var lastActivity: Date?
    /// True when your net is even but the group settles pair by pair and you still owe or are owed.
    var hasPairDebts = false

    var id: GroupID { group.id }
    var isSettled: Bool { myBalance.isEmpty && !hasPairDebts }
}
