import Foundation
import SpltCore
import SwiftData

extension SpltSchemaV1 {
    @Model
    final class PersonRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        /// An email address or phone number the person was invited with.
        var contactHint: String?
        var kindRaw: String
        /// Set when a placeholder is claimed by someone who joined with their Apple ID.
        var claimedByCloudUserID: String?
        /// Picks the avatar color; stored so it never changes when the name is edited.
        var avatarSeed: Int
        var createdAt: Date

        var recordName: String
        var zoneName: String?
        var systemFields: Data?
        var isDirty: Bool
        var pendingOperationRaw: String?
        var modifiedAt: Date
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            name: String,
            contactHint: String? = nil,
            kind: PersonKind = .friend,
            claimedByCloudUserID: String? = nil,
            avatarSeed: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.contactHint = contactHint
            self.kindRaw = kind.rawValue
            self.claimedByCloudUserID = claimedByCloudUserID
            self.avatarSeed = avatarSeed
            self.createdAt = createdAt
            self.recordName = id.uuidString
            self.zoneName = nil
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = createdAt
            self.deletedAt = nil
        }

        var kind: PersonKind {
            get { PersonKind(rawValue: kindRaw) ?? .friend }
            set { kindRaw = newValue.rawValue }
        }

        var personID: PersonID { PersonID(rawValue: id) }
    }
}

extension PersonRecord: SyncTracked {
    static let syncRecordType = SyncRecordType.person

    var syncFields: SyncFields {
        var fields = SyncFields()
        fields.set("name", name)
        fields.set("contactHint", contactHint)
        fields.set("kind", kind == .me ? PersonKind.friend.rawValue : kindRaw)
        fields.set("claimedByCloudUserID", claimedByCloudUserID)
        fields.set("avatarSeed", Int64(avatarSeed))
        fields.set("createdAt", createdAt)
        return fields
    }

    func applySyncFields(_ fields: SyncFields) {
        name = fields.string("name") ?? name
        contactHint = fields.string("contactHint")
        if kind != .me {
            kindRaw = fields.string("kind") ?? kindRaw
        }
        claimedByCloudUserID = fields.string("claimedByCloudUserID")
        avatarSeed = Int(fields.int("avatarSeed") ?? Int64(avatarSeed))
        createdAt = fields.date("createdAt") ?? createdAt
    }

    static func find(recordName: String, in context: ModelContext) throws -> PersonRecord? {
        var descriptor = FetchDescriptor<PersonRecord>(predicate: #Predicate { $0.recordName == recordName })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func dirtyRecords(in context: ModelContext) throws -> [PersonRecord] {
        try context.fetch(FetchDescriptor<PersonRecord>(predicate: #Predicate { $0.isDirty == true }))
    }

    static func tombstones(in context: ModelContext) throws -> [PersonRecord] {
        try context.fetch(FetchDescriptor<PersonRecord>(predicate: #Predicate { $0.deletedAt != nil }))
    }

    static func blank(recordName: String) -> PersonRecord {
        let record = PersonRecord(id: UUID(uuidString: recordName) ?? UUID(), name: "")
        record.recordName = recordName
        return record
    }
}
