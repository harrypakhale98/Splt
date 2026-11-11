import Foundation
import SpltCore
import SwiftData

extension SpltSchemaV2 {
    @Model
    final class GroupRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        /// An SF Symbol name.
        var symbol: String
        var currencyCode: String
        var kindRaw: String
        var memberIDs: [UUID]
        var simplifiesDebts: Bool
        var isArchived: Bool
        var tripStart: Date?
        var tripEnd: Date?
        /// A `PinnedRate` as JSON, set when the group fixes an exchange rate for a trip.
        var pinnedRateData: Data?
        /// The cover photo's file name in the covers folder of `PhotoStore`, or nil to show the symbol.
        var coverFileName: String?
        /// A `DefaultSplit` as JSON: how a new expense in this group is split unless changed. Nil splits equally.
        var defaultSplitData: Data?
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
            symbol: String = "person.3.fill",
            currencyCode: String,
            kind: GroupKind = .standard,
            memberIDs: [UUID] = [],
            simplifiesDebts: Bool = true,
            isArchived: Bool = false,
            tripStart: Date? = nil,
            tripEnd: Date? = nil,
            pinnedRateData: Data? = nil,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.currencyCode = currencyCode.uppercased()
            self.kindRaw = kind.rawValue
            self.memberIDs = memberIDs
            self.simplifiesDebts = simplifiesDebts
            self.isArchived = isArchived
            self.tripStart = tripStart
            self.tripEnd = tripEnd
            self.pinnedRateData = pinnedRateData
            self.coverFileName = nil
            self.defaultSplitData = nil
            self.createdAt = createdAt
            self.recordName = id.uuidString
            self.zoneName = id.uuidString
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = createdAt
            self.deletedAt = nil
        }

        var kind: GroupKind {
            get { GroupKind(rawValue: kindRaw) ?? .standard }
            set { kindRaw = newValue.rawValue }
        }

        var groupID: GroupID { GroupID(rawValue: id) }
    }
}

extension GroupRecord: SyncTracked {
    static let syncRecordType = SyncRecordType.group

    var syncFields: SyncFields {
        var fields = SyncFields()
        fields.set("name", name)
        fields.set("symbol", symbol)
        fields.set("currencyCode", currencyCode)
        fields.set("kind", kindRaw)
        fields.set("memberIDs", RecordCoding.encode(memberIDs))
        fields.set("simplifiesDebts", simplifiesDebts)
        fields.set("isArchived", isArchived)
        fields.set("tripStart", tripStart)
        fields.set("tripEnd", tripEnd)
        fields.set("pinnedRate", pinnedRateData)
        fields.set("coverFileName", coverFileName)
        fields.set("defaultSplit", defaultSplitData)
        fields.set("createdAt", createdAt)
        return fields
    }

    func applySyncFields(_ fields: SyncFields) {
        name = fields.string("name") ?? name
        symbol = fields.string("symbol") ?? symbol
        currencyCode = fields.string("currencyCode") ?? currencyCode
        kindRaw = fields.string("kind") ?? kindRaw
        memberIDs = fields.data("memberIDs").flatMap { try? RecordCoding.decode([UUID].self, from: $0) } ?? memberIDs
        simplifiesDebts = fields.bool("simplifiesDebts")
        isArchived = fields.bool("isArchived")
        tripStart = fields.date("tripStart")
        tripEnd = fields.date("tripEnd")
        pinnedRateData = fields.data("pinnedRate")
        coverFileName = fields.string("coverFileName")
        defaultSplitData = fields.data("defaultSplit")
        createdAt = fields.date("createdAt") ?? createdAt
    }

    static func find(recordName: String, in context: ModelContext) throws -> GroupRecord? {
        // the id column is indexed, so a UUID record name is found without scanning the table
        var descriptor: FetchDescriptor<GroupRecord>
        if let uuid = UUID(uuidString: recordName) {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.id == uuid })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.recordName == recordName })
        }
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func dirtyRecords(in context: ModelContext) throws -> [GroupRecord] {
        try context.fetch(FetchDescriptor<GroupRecord>(predicate: #Predicate { $0.isDirty == true }))
    }

    static func tombstones(in context: ModelContext) throws -> [GroupRecord] {
        try context.fetch(FetchDescriptor<GroupRecord>(predicate: #Predicate { $0.deletedAt != nil }))
    }

    static func blank(recordName: String) -> GroupRecord {
        let record = GroupRecord(id: UUID(uuidString: recordName) ?? UUID(), name: "", currencyCode: "USD")
        record.recordName = recordName
        return record
    }
}
