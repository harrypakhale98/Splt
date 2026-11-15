import CryptoKit
import Foundation
import SpltCore
import SwiftData

// The models exactly as version 2 (Splt 1.1) stored them, frozen so a store saved by 1.1 can be read and
// migrated to version 3, which only adds indexes. The app itself runs on the current version.
extension SpltSchemaV2 {
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
