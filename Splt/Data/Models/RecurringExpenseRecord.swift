import Foundation
import SpltCore
import SwiftData

extension SpltSchemaV1 {
    @Model
    final class RecurringExpenseRecord {
        @Attribute(.unique) var id: UUID
        var groupID: UUID?
        var title: String
        var totalMinorUnits: Int64
        var currencyCode: String
        var categoryRaw: String
        var payersData: Data
        var splitData: Data
        var note: String
        /// A `RecurrenceRule` as JSON.
        var ruleData: Data
        /// The date of the latest occurrence that was turned into an expense.
        var lastCreatedOccurrence: Date?
        var isActive: Bool
        var createdByID: UUID?
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
            groupID: UUID? = nil,
            title: String,
            totalMinorUnits: Int64,
            currencyCode: String,
            categoryRaw: String = ExpenseCategory.general.rawValue,
            payersData: Data = Data("{}".utf8),
            splitData: Data = Data(),
            note: String = "",
            ruleData: Data = Data(),
            isActive: Bool = true,
            createdAt: Date = .now
        ) {
            self.id = id
            self.groupID = groupID
            self.title = title
            self.totalMinorUnits = totalMinorUnits
            self.currencyCode = currencyCode.uppercased()
            self.categoryRaw = categoryRaw
            self.payersData = payersData
            self.splitData = splitData
            self.note = note
            self.ruleData = ruleData
            self.lastCreatedOccurrence = nil
            self.isActive = isActive
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

extension RecurringExpenseRecord: SyncTracked {
    static let syncRecordType = SyncRecordType.recurringExpense

    var syncFields: SyncFields {
        var fields = SyncFields()
        fields.set("groupID", groupID)
        fields.set("title", title)
        fields.set("totalMinorUnits", totalMinorUnits)
        fields.set("currencyCode", currencyCode)
        fields.set("category", categoryRaw)
        fields.set("payers", payersData)
        fields.set("split", splitData)
        fields.set("note", note)
        fields.set("rule", ruleData)
        fields.set("lastCreatedOccurrence", lastCreatedOccurrence)
        fields.set("isActive", isActive)
        fields.set("createdByID", createdByID)
        fields.set("createdAt", createdAt)
        return fields
    }

    func applySyncFields(_ fields: SyncFields) {
        groupID = fields.uuid("groupID")
        title = fields.string("title") ?? title
        totalMinorUnits = fields.int("totalMinorUnits") ?? totalMinorUnits
        currencyCode = fields.string("currencyCode") ?? currencyCode
        categoryRaw = fields.string("category") ?? categoryRaw
        payersData = fields.data("payers") ?? payersData
        splitData = fields.data("split") ?? splitData
        note = fields.string("note") ?? ""
        ruleData = fields.data("rule") ?? ruleData
        lastCreatedOccurrence = fields.date("lastCreatedOccurrence")
        isActive = fields.bool("isActive")
        createdByID = fields.uuid("createdByID")
        createdAt = fields.date("createdAt") ?? createdAt
    }

    static func find(recordName: String, in context: ModelContext) throws -> RecurringExpenseRecord? {
        var descriptor = FetchDescriptor<RecurringExpenseRecord>(predicate: #Predicate { $0.recordName == recordName })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func dirtyRecords(in context: ModelContext) throws -> [RecurringExpenseRecord] {
        try context.fetch(FetchDescriptor<RecurringExpenseRecord>(predicate: #Predicate { $0.isDirty == true }))
    }

    static func tombstones(in context: ModelContext) throws -> [RecurringExpenseRecord] {
        try context.fetch(FetchDescriptor<RecurringExpenseRecord>(predicate: #Predicate { $0.deletedAt != nil }))
    }

    static func blank(recordName: String) -> RecurringExpenseRecord {
        let record = RecurringExpenseRecord(
            id: UUID(uuidString: recordName) ?? UUID(), title: "", totalMinorUnits: 0, currencyCode: "USD"
        )
        record.recordName = recordName
        return record
    }
}
