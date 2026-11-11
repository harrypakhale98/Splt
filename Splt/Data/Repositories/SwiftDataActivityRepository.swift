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

    /// Only rows the feed can show count, so a kind from a newer version, which this one can't read,
    /// never leaves a badge that nothing on screen can clear.
    func unreadCount() throws -> Int {
        let me = try env.currentUser()?.personID
        return try env.context.fetch(FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.isRead == false && $0.deletedAt == nil }
        ))
        .compactMap(ActivityEntry.init)
        .filter { $0.isShown(to: me) }
        .count
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

    @discardableResult
    func expireReminders(sentBefore cutoff: Date) throws -> Int {
        guard let me = try env.currentUser()?.id else { return 0 }
        let kind = ActivityKind.reminderSent.rawValue
        let old = try env.context.fetch(FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.kindRaw == kind && $0.deletedAt == nil && $0.createdAt < cutoff }
        ))
        // only the sender's devices remove a reminder; everyone else just receives the deletion
        let mine = old.filter { $0.actorID == me }
        guard !mine.isEmpty else { return 0 }
        for record in mine {
            env.tracker.tombstone(record)
        }
        try env.save()
        return mine.count
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
