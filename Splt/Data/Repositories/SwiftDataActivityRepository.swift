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
        let me = try env.currentUser()?.personID
        return try env.context.fetch(descriptor).compactMap(ActivityEntry.init).filter { $0.isShown(to: me) }
    }

    func unreadCount() throws -> Int {
        try env.context.fetchCount(FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.isRead == false && $0.deletedAt == nil }
        ))
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

    func recordReminder(to person: PersonID, amounts: [Money], in group: GroupID) throws {
        try env.log(.reminderSent(to: person, amounts: amounts), groupID: group)
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
