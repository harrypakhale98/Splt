import Foundation
import SpltCore
import SwiftData

@MainActor
final class SwiftDataActivityRepository: ActivityRepository {
    private let env: RepositoryContext

    init(_ env: RepositoryContext) {
        self.env = env
    }

    func entries(in group: GroupID?, limit: Int) throws -> [ActivityEntry] {
        let gid: UUID? = group?.rawValue
        var descriptor = FetchDescriptor<ActivityRecord>(
            predicate: group == nil
                ? #Predicate { $0.deletedAt == nil }
                : #Predicate { $0.groupID == gid && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try env.context.fetch(descriptor).compactMap(ActivityEntry.init)
    }

    /// Counts only what the Activity screen can show. A later version may sync kinds of activity
    /// this one cannot read, and a badge for a row nobody can see or mark read would never clear.
    func unreadCount() throws -> Int {
        try env.context.fetch(FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.isRead == false && $0.deletedAt == nil }
        )).compactMap(ActivityEntry.init).count
    }

    func markRead(ids: [UUID]) throws {
        let wanted = Set(ids)
        let unread = try env.context.fetch(FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.isRead == false }
        ))
        for record in unread where wanted.contains(record.id) {
            record.isRead = true
        }
        try env.save()
    }

    func markAllRead() throws {
        let unread = try env.context.fetch(FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.isRead == false }
        ))
        for record in unread {
            record.isRead = true
        }
        try env.save()
    }
}
