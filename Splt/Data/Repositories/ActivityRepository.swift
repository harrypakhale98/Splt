import Foundation
import SpltCore

@MainActor
protocol ActivityRepository {
    /// Newest first. Pass a group to see only its events.
    func entries(in group: GroupID?, limit: Int) throws -> [ActivityEntry]
    func unreadCount() throws -> Int
    func markRead(ids: [UUID]) throws
    func markAllRead() throws
}

extension ActivityRepository {
    func entries(limit: Int = 100) throws -> [ActivityEntry] {
        try entries(in: nil, limit: limit)
    }
}
