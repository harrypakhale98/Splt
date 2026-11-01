import Foundation
import SpltCore

/// A group row, ready to show.
struct GroupSummary: Hashable, Sendable, Identifiable {
    var group: SplitGroup
    var memberCount: Int
    /// Your net balance, one amount per currency. Positive means the group owes you.
    var myBalance: [Money]
    var lastActivity: Date?

    var id: GroupID { group.id }
    var isSettled: Bool { myBalance.isEmpty }
}
