import Foundation
import SpltCore

extension ActivityEntry {
    /// Nil when the event was written by a newer app version this build cannot read.
    init?(_ record: ActivityRecord) {
        guard let event = try? RecordCoding.decode(ActivityEvent.self, from: record.eventData) else { return nil }
        self.init(
            id: record.id,
            groupID: record.groupID.map { GroupID(rawValue: $0) },
            actorID: record.actorID.map { PersonID(rawValue: $0) },
            event: event,
            createdAt: record.createdAt,
            isRead: record.isRead
        )
    }
}

extension ActivityEntry {
    /// A reminder is between the person who sent it and the one it was for. It syncs to the whole
    /// group, as every activity row does, but the others never see it.
    func isShown(to me: PersonID?) -> Bool {
        guard case .reminderSent(let recipient, _) = event else { return true }
        return me != nil && (actorID == me || recipient == me)
    }
}

extension ActivityRecord {
    /// Who a reminder row was sent to, as stored. Nil for every other kind of row.
    var reminderRecipient: UUID? {
        guard kindRaw == ActivityKind.reminderSent.rawValue,
              case .reminderSent(let recipient, _)? = try? RecordCoding.decode(ActivityEvent.self, from: eventData) else { return nil }
        return recipient.rawValue
    }

    convenience init(_ entry: ActivityEntry) {
        self.init(
            id: entry.id,
            groupID: entry.groupID?.rawValue,
            actorID: entry.actorID?.rawValue,
            kindRaw: entry.event.kind.rawValue,
            eventData: RecordCoding.encode(entry.event),
            createdAt: entry.createdAt,
            isRead: entry.isRead
        )
    }
}
