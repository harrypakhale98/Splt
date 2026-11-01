import Foundation
import SpltCore
import SwiftData

extension SpltSchemaV1 {
    @Model
    final class CommentRecord {
        @Attribute(.unique) var id: UUID
        var groupID: UUID?
        /// The expense the comment is about, or nil for a comment on the group itself.
        var expenseID: UUID?
        var authorID: UUID
        var text: String
        var createdAt: Date
        var editedAt: Date?
        /// `[CommentReaction]` as JSON.
        var reactionsData: Data

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
            expenseID: UUID? = nil,
            authorID: UUID,
            text: String,
            createdAt: Date = .now
        ) {
            self.id = id
            self.groupID = groupID
            self.expenseID = expenseID
            self.authorID = authorID
            self.text = text
            self.createdAt = createdAt
            self.editedAt = nil
            self.reactionsData = Data("[]".utf8)
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

extension CommentRecord: SyncTracked {
    static let syncRecordType = SyncRecordType.comment

    var syncFields: SyncFields {
        var fields = SyncFields()
        fields.set("groupID", groupID)
        fields.set("expenseID", expenseID)
        fields.set("authorID", authorID)
        fields.set("text", text)
        fields.set("createdAt", createdAt)
        fields.set("editedAt", editedAt)
        fields.set("reactions", reactionsData)
        return fields
    }

    func applySyncFields(_ fields: SyncFields) {
        groupID = fields.uuid("groupID")
        expenseID = fields.uuid("expenseID")
        authorID = fields.uuid("authorID") ?? authorID
        text = fields.string("text") ?? text
        createdAt = fields.date("createdAt") ?? createdAt
        editedAt = fields.date("editedAt")
        reactionsData = fields.data("reactions") ?? reactionsData
    }

    static func find(recordName: String, in context: ModelContext) throws -> CommentRecord? {
        var descriptor = FetchDescriptor<CommentRecord>(predicate: #Predicate { $0.recordName == recordName })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func dirtyRecords(in context: ModelContext) throws -> [CommentRecord] {
        try context.fetch(FetchDescriptor<CommentRecord>(predicate: #Predicate { $0.isDirty == true }))
    }

    static func tombstones(in context: ModelContext) throws -> [CommentRecord] {
        try context.fetch(FetchDescriptor<CommentRecord>(predicate: #Predicate { $0.deletedAt != nil }))
    }

    static func blank(recordName: String) -> CommentRecord {
        let record = CommentRecord(id: UUID(uuidString: recordName) ?? UUID(), authorID: UUID(), text: "")
        record.recordName = recordName
        return record
    }
}
