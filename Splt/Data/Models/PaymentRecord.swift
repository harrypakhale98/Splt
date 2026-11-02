import Foundation
import SpltCore
import SwiftData

extension SpltSchemaV1 {
    @Model
    final class PaymentRecord {
        @Attribute(.unique) var id: UUID
        var groupID: UUID?
        var payerID: UUID
        var receiverID: UUID
        var amountMinorUnits: Int64
        var currencyCode: String
        var date: Date
        var note: String
        var createdAt: Date

        var recordName: String
        var zoneName: String?
        var systemFields: Data?
        var isDirty: Bool
        var pendingOperationRaw: String?
        var modifiedAt: Date
        /// Set when the settlement is undone; the row is kept for history.
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            groupID: UUID? = nil,
            payerID: UUID,
            receiverID: UUID,
            amountMinorUnits: Int64,
            currencyCode: String,
            date: Date,
            note: String = "",
            createdAt: Date = .now
        ) {
            self.id = id
            self.groupID = groupID
            self.payerID = payerID
            self.receiverID = receiverID
            self.amountMinorUnits = amountMinorUnits
            self.currencyCode = currencyCode.uppercased()
            self.date = date
            self.note = note
            self.createdAt = createdAt
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

extension PaymentRecord: SyncTracked {
    static let syncRecordType = SyncRecordType.payment
    static var purgesConfirmedTombstones: Bool { false }

    var syncFields: SyncFields {
        var fields = SyncFields()
        fields.set("groupID", groupID)
        fields.set("payerID", payerID)
        fields.set("receiverID", receiverID)
        fields.set("amountMinorUnits", amountMinorUnits)
        fields.set("currencyCode", currencyCode)
        fields.set("date", date)
        fields.set("note", note)
        fields.set("createdAt", createdAt)
        return fields
    }

    func applySyncFields(_ fields: SyncFields) {
        groupID = fields.uuid("groupID")
        payerID = fields.uuid("payerID") ?? payerID
        receiverID = fields.uuid("receiverID") ?? receiverID
        amountMinorUnits = fields.int("amountMinorUnits") ?? amountMinorUnits
        currencyCode = fields.string("currencyCode") ?? currencyCode
        date = fields.date("date") ?? date
        note = fields.string("note") ?? ""
        createdAt = fields.date("createdAt") ?? createdAt
    }

    static func find(recordName: String, in context: ModelContext) throws -> PaymentRecord? {
        // the id column is indexed, so a UUID record name is found without scanning the table
        var descriptor: FetchDescriptor<PaymentRecord>
        if let uuid = UUID(uuidString: recordName) {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.id == uuid })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.recordName == recordName })
        }
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func dirtyRecords(in context: ModelContext) throws -> [PaymentRecord] {
        try context.fetch(FetchDescriptor<PaymentRecord>(predicate: #Predicate { $0.isDirty == true }))
    }

    static func tombstones(in context: ModelContext) throws -> [PaymentRecord] {
        try context.fetch(FetchDescriptor<PaymentRecord>(predicate: #Predicate { $0.deletedAt != nil }))
    }

    static func blank(recordName: String) -> PaymentRecord {
        let record = PaymentRecord(
            id: UUID(uuidString: recordName) ?? UUID(), payerID: UUID(), receiverID: UUID(),
            amountMinorUnits: 0, currencyCode: "USD", date: .now
        )
        record.recordName = recordName
        return record
    }
}
