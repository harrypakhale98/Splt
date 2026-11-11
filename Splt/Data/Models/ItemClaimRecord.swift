import CryptoKit
import Foundation
import SpltCore
import SwiftData

extension SpltSchemaV2 {
    /// One person's picks from the items of an expense split by item.
    ///
    /// Each person writes only their own claim, so people picking items at the same time never
    /// overwrite each other, as they would if they all edited the expense. A person has at most one
    /// claim per expense: its id comes from the expense and the person, so every device makes the same one.
    @Model
    final class ItemClaimRecord {
        @Attribute(.unique) var id: UUID
        var groupID: UUID?
        var expenseID: UUID
        var personID: UUID
        /// The ids of the claimed `SplitItem`s as JSON `[UUID]`.
        var itemIDsData: Data
        var createdAt: Date

        var recordName: String
        var zoneName: String?
        var systemFields: Data?
        var isDirty: Bool
        var pendingOperationRaw: String?
        var modifiedAt: Date
        var deletedAt: Date?

        init(groupID: UUID?, expenseID: UUID, personID: UUID, itemIDs: [UUID] = [], createdAt: Date = .now) {
            let id = ItemClaimRecord.claimID(expenseID: expenseID, personID: personID)
            self.id = id
            self.groupID = groupID
            self.expenseID = expenseID
            self.personID = personID
            self.itemIDsData = RecordCoding.encode(itemIDs.sorted { $0.uuidString < $1.uuidString })
            self.createdAt = createdAt
            self.recordName = id.uuidString
            self.zoneName = groupID?.uuidString
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = createdAt
            self.deletedAt = nil
        }

        var itemIDs: [UUID] {
            get { (try? RecordCoding.decode([UUID].self, from: itemIDsData)) ?? [] }
            set { itemIDsData = RecordCoding.encode(newValue.sorted { $0.uuidString < $1.uuidString }) }
        }

        /// The one id a person's claim on an expense has on every device.
        static func claimID(expenseID: UUID, personID: UUID) -> UUID {
            let digest = SHA256.hash(data: Data("claim:\(expenseID.uuidString):\(personID.uuidString)".utf8))
            var bytes = Array(digest.prefix(16))
            bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 style, name based
            bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
            return UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        }
    }
}

extension ItemClaimRecord: SyncTracked {
    static let syncRecordType = SyncRecordType.itemClaim

    var syncFields: SyncFields {
        var fields = SyncFields()
        fields.set("groupID", groupID)
        fields.set("expenseID", expenseID)
        fields.set("personID", personID)
        fields.set("itemIDs", itemIDsData)
        fields.set("createdAt", createdAt)
        return fields
    }

    func applySyncFields(_ fields: SyncFields) {
        groupID = fields.uuid("groupID")
        expenseID = fields.uuid("expenseID") ?? expenseID
        personID = fields.uuid("personID") ?? personID
        itemIDsData = fields.data("itemIDs") ?? itemIDsData
        createdAt = fields.date("createdAt") ?? createdAt
    }

    static func find(recordName: String, in context: ModelContext) throws -> ItemClaimRecord? {
        var descriptor: FetchDescriptor<ItemClaimRecord>
        if let uuid = UUID(uuidString: recordName) {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.id == uuid })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.recordName == recordName })
        }
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func dirtyRecords(in context: ModelContext) throws -> [ItemClaimRecord] {
        try context.fetch(FetchDescriptor<ItemClaimRecord>(predicate: #Predicate { $0.isDirty == true }))
    }

    static func tombstones(in context: ModelContext) throws -> [ItemClaimRecord] {
        try context.fetch(FetchDescriptor<ItemClaimRecord>(predicate: #Predicate { $0.deletedAt != nil }))
    }

    static func blank(recordName: String) -> ItemClaimRecord {
        let record = ItemClaimRecord(groupID: nil, expenseID: UUID(), personID: UUID())
        record.id = UUID(uuidString: recordName) ?? record.id
        record.recordName = recordName
        return record
    }
}
