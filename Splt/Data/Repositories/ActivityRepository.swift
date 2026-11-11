import Foundation
import SpltCore

@MainActor
protocol ActivityRepository {
    /// Newest first. Pass a group to see only its events.
    func entries(in group: GroupID?, limit: Int) throws -> [ActivityEntry]
    func unreadCount() throws -> Int
    func markRead(ids: [UUID]) throws
    func markAllRead() throws
    /// Writes a row in the group saying you reminded `person` of what they owe you there. It syncs to
    /// the group, which is how the reminder reaches them.
    func recordReminder(to person: PersonID, amounts: [Money], in group: GroupID) throws
}

extension ActivityRepository {
    func entries(limit: Int = 100) throws -> [ActivityEntry] {
        try entries(in: nil, limit: limit)
    }
}
