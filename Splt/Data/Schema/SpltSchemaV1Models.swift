import Foundation
import SwiftData

// The models exactly as version 1 stored them, frozen so a store saved by 1.0 can be read and
// migrated. Only the stored properties matter here; the app itself runs on the current version.
extension SpltSchemaV1 {
    @Model
    final class ActivityRecord {
        @Attribute(.unique) var id: UUID
        var groupID: UUID?
        var actorID: UUID?
        var kindRaw: String
        var eventData: Data
        var createdAt: Date
        var isRead: Bool
        var recordName: String
        var zoneName: String?
        var systemFields: Data?
        var isDirty: Bool
        var pendingOperationRaw: String?
        var modifiedAt: Date
        var deletedAt: Date?

        init() {
            self.id = UUID()
            self.groupID = nil
            self.actorID = nil
            self.kindRaw = ""
            self.eventData = Data()
            self.createdAt = .distantPast
            self.isRead = false
            self.recordName = ""
            self.zoneName = nil
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = .distantPast
            self.deletedAt = nil
        }
    }

    @Model
    final class CommentRecord {
        @Attribute(.unique) var id: UUID
        var groupID: UUID?
        var expenseID: UUID?
        var authorID: UUID
        var text: String
        var createdAt: Date
        var editedAt: Date?
        var reactionsData: Data
        var recordName: String
        var zoneName: String?
        var systemFields: Data?
        var isDirty: Bool
        var pendingOperationRaw: String?
        var modifiedAt: Date
        var deletedAt: Date?

        init() {
            self.id = UUID()
            self.groupID = nil
            self.expenseID = nil
            self.authorID = UUID()
            self.text = ""
            self.createdAt = .distantPast
            self.editedAt = nil
            self.reactionsData = Data()
            self.recordName = ""
            self.zoneName = nil
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = .distantPast
            self.deletedAt = nil
        }
    }

    @Model
    final class ExpenseRecord {
        @Attribute(.unique) var id: UUID
        var groupID: UUID?
        var title: String
        var totalMinorUnits: Int64
        var currencyCode: String
        var date: Date
        var categoryRaw: String
        var payersData: Data
        var splitData: Data
        var note: String
        var receiptFileName: String?
        var locationName: String?
        var latitude: Double?
        var longitude: Double?
        var recurrenceData: Data?
        var recurringExpenseID: UUID?
        var editHistoryData: Data
        var createdByID: UUID?
        var createdAt: Date
        var recordName: String
        var zoneName: String?
        var systemFields: Data?
        var isDirty: Bool
        var pendingOperationRaw: String?
        var modifiedAt: Date
        var deletedAt: Date?

        init() {
            self.id = UUID()
            self.groupID = nil
            self.title = ""
            self.totalMinorUnits = 0
            self.currencyCode = ""
            self.date = .distantPast
            self.categoryRaw = ""
            self.payersData = Data()
            self.splitData = Data()
            self.note = ""
            self.receiptFileName = nil
            self.locationName = nil
            self.latitude = nil
            self.longitude = nil
            self.recurrenceData = nil
            self.recurringExpenseID = nil
            self.editHistoryData = Data()
            self.createdByID = nil
            self.createdAt = .distantPast
            self.recordName = ""
            self.zoneName = nil
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = .distantPast
            self.deletedAt = nil
        }
    }

    @Model
    final class GroupRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var symbol: String
        var currencyCode: String
        var kindRaw: String
        var memberIDs: [UUID]
        var simplifiesDebts: Bool
        var isArchived: Bool
        var tripStart: Date?
        var tripEnd: Date?
        var pinnedRateData: Data?
        var createdAt: Date
        var recordName: String
        var zoneName: String?
        var systemFields: Data?
        var isDirty: Bool
        var pendingOperationRaw: String?
        var modifiedAt: Date
        var deletedAt: Date?

        init() {
            self.id = UUID()
            self.name = ""
            self.symbol = ""
            self.currencyCode = ""
            self.kindRaw = ""
            self.memberIDs = []
            self.simplifiesDebts = false
            self.isArchived = false
            self.tripStart = nil
            self.tripEnd = nil
            self.pinnedRateData = nil
            self.createdAt = .distantPast
            self.recordName = ""
            self.zoneName = nil
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = .distantPast
            self.deletedAt = nil
        }
    }

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
        var deletedAt: Date?

        init() {
            self.id = UUID()
            self.groupID = nil
            self.payerID = UUID()
            self.receiverID = UUID()
            self.amountMinorUnits = 0
            self.currencyCode = ""
            self.date = .distantPast
            self.note = ""
            self.createdAt = .distantPast
            self.recordName = ""
            self.zoneName = nil
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = .distantPast
            self.deletedAt = nil
        }
    }

    @Model
    final class PersonRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var contactHint: String?
        var kindRaw: String
        var claimedByCloudUserID: String?
        var avatarSeed: Int
        var createdAt: Date
        var recordName: String
        var zoneName: String?
        var systemFields: Data?
        var isDirty: Bool
        var pendingOperationRaw: String?
        var modifiedAt: Date
        var deletedAt: Date?

        init() {
            self.id = UUID()
            self.name = ""
            self.contactHint = nil
            self.kindRaw = ""
            self.claimedByCloudUserID = nil
            self.avatarSeed = 0
            self.createdAt = .distantPast
            self.recordName = ""
            self.zoneName = nil
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = .distantPast
            self.deletedAt = nil
        }
    }

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
        var ruleData: Data
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

        init() {
            self.id = UUID()
            self.groupID = nil
            self.title = ""
            self.totalMinorUnits = 0
            self.currencyCode = ""
            self.categoryRaw = ""
            self.payersData = Data()
            self.splitData = Data()
            self.note = ""
            self.ruleData = Data()
            self.lastCreatedOccurrence = nil
            self.isActive = false
            self.createdByID = nil
            self.createdAt = .distantPast
            self.recordName = ""
            self.zoneName = nil
            self.systemFields = nil
            self.isDirty = false
            self.pendingOperationRaw = nil
            self.modifiedAt = .distantPast
            self.deletedAt = nil
        }
    }
}
