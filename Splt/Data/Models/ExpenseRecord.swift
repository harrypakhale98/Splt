import Foundation
import SpltCore
import SwiftData

extension SpltSchemaV1 {
    @Model
    final class ExpenseRecord {
        @Attribute(.unique) var id: UUID
        var groupID: UUID?
        var title: String
        var totalMinorUnits: Int64
        var currencyCode: String
        var date: Date
        var categoryRaw: String
        /// `[PersonID: Money]` as JSON: what each payer put in.
        var payersData: Data
        /// A `SplitDefinition` as JSON.
        var splitData: Data
        var note: String
        var receiptFileName: String?
        var locationName: String?
        var latitude: Double?
        var longitude: Double?
        /// A `RecurrenceRule` as JSON, when the expense was made to repeat.
        var recurrenceData: Data?
        /// The recurring template that produced this expense, if any.
        var recurringExpenseID: UUID?
        /// `[ExpenseEditEntry]` as JSON, oldest first.
        var editHistoryData: Data
        var createdByID: UUID?
        var createdAt: Date

        var recordName: String
        var zoneName: String?
        var systemFields: Data?
        var isDirty: Bool
        var pendingOperationRaw: String?
        var modifiedAt: Date
        /// The soft delete flag. An expense is deleted when this is set; the row is kept for history.
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            groupID: UUID? = nil,
            title: String,
            totalMinorUnits: Int64,
            currencyCode: String,
            date: Date,
            categoryRaw: String = ExpenseCategory.general.rawValue,
            payersData: Data = Data("{}".utf8),
            splitData: Data = Data(),
            note: String = "",
            createdAt: Date = .now
        ) {
            self.id = id
            self.groupID = groupID
            self.title = title
            self.totalMinorUnits = totalMinorUnits
            self.currencyCode = currencyCode.uppercased()
            self.date = date
            self.categoryRaw = categoryRaw
            self.payersData = payersData
            self.splitData = splitData
            self.note = note
            self.receiptFileName = nil
            self.locationName = nil
            self.latitude = nil
            self.longitude = nil
            self.recurrenceData = nil
            self.recurringExpenseID = nil
            self.editHistoryData = Data("[]".utf8)
            self.createdByID = nil
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

extension ExpenseRecord: SyncTracked {
    static let syncRecordType = SyncRecordType.expense
    static var purgesConfirmedTombstones: Bool { false }

    var syncFields: SyncFields {
        var fields = SyncFields()
        fields.set("groupID", groupID)
        fields.set("title", title)
        fields.set("totalMinorUnits", totalMinorUnits)
        fields.set("currencyCode", currencyCode)
        fields.set("date", date)
        fields.set("category", categoryRaw)
        fields.set("payers", payersData)
        fields.set("split", splitData)
        fields.set("note", note)
        fields.set("receiptFileName", receiptFileName)
        fields.set("locationName", locationName)
        fields.set("latitude", latitude)
        fields.set("longitude", longitude)
        fields.set("recurrence", recurrenceData)
        fields.set("recurringExpenseID", recurringExpenseID)
        fields.set("editHistory", editHistoryData)
        fields.set("createdByID", createdByID)
        fields.set("createdAt", createdAt)
        return fields
    }

    func applySyncFields(_ fields: SyncFields) {
        groupID = fields.uuid("groupID")
        title = fields.string("title") ?? title
        totalMinorUnits = fields.int("totalMinorUnits") ?? totalMinorUnits
        currencyCode = fields.string("currencyCode") ?? currencyCode
        date = fields.date("date") ?? date
        categoryRaw = fields.string("category") ?? categoryRaw
        payersData = fields.data("payers") ?? payersData
        splitData = fields.data("split") ?? splitData
        note = fields.string("note") ?? ""
        receiptFileName = fields.string("receiptFileName")
        locationName = fields.string("locationName")
        latitude = fields.double("latitude")
        longitude = fields.double("longitude")
        recurrenceData = fields.data("recurrence")
        recurringExpenseID = fields.uuid("recurringExpenseID")
        editHistoryData = fields.data("editHistory") ?? editHistoryData
        createdByID = fields.uuid("createdByID")
        createdAt = fields.date("createdAt") ?? createdAt
    }

    static func find(recordName: String, in context: ModelContext) throws -> ExpenseRecord? {
        // the id column is indexed, so a UUID record name is found without scanning the table
        var descriptor: FetchDescriptor<ExpenseRecord>
        if let uuid = UUID(uuidString: recordName) {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.id == uuid })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.recordName == recordName })
        }
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func dirtyRecords(in context: ModelContext) throws -> [ExpenseRecord] {
        try context.fetch(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.isDirty == true }))
    }

    static func tombstones(in context: ModelContext) throws -> [ExpenseRecord] {
        try context.fetch(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.deletedAt != nil }))
    }

    static func blank(recordName: String) -> ExpenseRecord {
        let record = ExpenseRecord(
            id: UUID(uuidString: recordName) ?? UUID(), title: "", totalMinorUnits: 0, currencyCode: "USD", date: .now
        )
        record.recordName = recordName
        return record
    }
}
