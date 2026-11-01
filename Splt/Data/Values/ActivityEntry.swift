import Foundation
import SpltCore

/// One row of the activity feed.
struct ActivityEntry: Hashable, Sendable, Identifiable {
    var id: UUID
    var groupID: GroupID?
    var actorID: PersonID?
    var event: ActivityEvent
    var createdAt: Date
    var isRead: Bool

    init(
        id: UUID = UUID(),
        groupID: GroupID? = nil,
        actorID: PersonID? = nil,
        event: ActivityEvent,
        createdAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.groupID = groupID
        self.actorID = actorID
        self.event = event
        self.createdAt = createdAt
        self.isRead = isRead
    }
}
