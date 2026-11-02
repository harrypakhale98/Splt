import Foundation
import SpltCore
import SwiftData

extension SpltSchemaV1 {
    @Model
    final class ActivityRecord {
        @Attribute(.unique) var id: UUID
        var groupID: UUID?
        var actorID: UUID?
        /// The event's kind as text, kept beside the payload so lists can filter without decoding.
        var kindRaw: String
        /// An `ActivityEvent` as JSON.
        var eventData: Data
        var createdAt: Date
        /// Local to this device: reading an event on one phone does not mark it read on another.
        var isRead: Bool

        var recordName: String
        var zoneName: String?
        var systemFields: Data?
        var isDirty: Bool
        var pendingOperationRaw: String?
        var modifiedAt: Date
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            groupID: UUID? = nil,
            actorID: UUID? = nil,
            kindRaw: String,
            eventData: Data,
            createdAt: Date = .now,
            isRead: Bool = false
        ) {
            self.id = id
            self.groupID = groupID
            self.actorID = actorID
            self.kindRaw = kindRaw
            self.eventData = eventData
            self.createdAt = createdAt
            self.isRead = isRead
            self.recordName = id.uuidString
            self.zoneName = groupID?.uuidString
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = createdAt
            self.deletedAt = nil
        }
    }
}

extension ActivityRecord: SyncTracked {
    static let syncRecordType = SyncRecordType.activity

    var syncFields: SyncFields {
        var fields = SyncFields()
        fields.set("groupID", groupID)
        fields.set("actorID", actorID)
        fields.set("kind", kindRaw)
        fields.set("event", eventData)
        fields.set("createdAt", createdAt)
        return fields
    }

    func applySyncFields(_ fields: SyncFields) {
        groupID = fields.uuid("groupID")
        actorID = fields.uuid("actorID")
        kindRaw = fields.string("kind") ?? kindRaw
        eventData = fields.data("event") ?? eventData
        createdAt = fields.date("createdAt") ?? createdAt
    }

    static func find(recordName: String, in context: ModelContext) throws -> ActivityRecord? {
        // the id column is indexed, so a UUID record name is found without scanning the table
        var descriptor: FetchDescriptor<ActivityRecord>
        if let uuid = UUID(uuidString: recordName) {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.id == uuid })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.recordName == recordName })
        }
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func dirtyRecords(in context: ModelContext) throws -> [ActivityRecord] {
        try context.fetch(FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.isDirty == true }))
    }

    static func tombstones(in context: ModelContext) throws -> [ActivityRecord] {
        try context.fetch(FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.deletedAt != nil }))
    }

    static func blank(recordName: String) -> ActivityRecord {
        let record = ActivityRecord(
            id: UUID(uuidString: recordName) ?? UUID(), kindRaw: "", eventData: Data(), isRead: false
        )
        record.recordName = recordName
        return record
    }
}
