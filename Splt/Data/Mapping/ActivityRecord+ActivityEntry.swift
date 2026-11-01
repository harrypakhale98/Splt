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

extension ActivityRecord {
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
