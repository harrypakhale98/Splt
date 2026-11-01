import Foundation
import SwiftData

/// What every persisted record shares so the change tracker and the sync engine can treat them alike.
///
/// The bookkeeping lives in plain stored properties, not an embedded struct, so SwiftData
/// can filter on `isDirty` and `recordName` in a fetch.
protocol SyncTracked: PersistentModel {
    static var syncRecordType: SyncRecordType { get }

    /// Stable name of the CloudKit record, the record's UUID in text form.
    var recordName: String { get set }
    /// The record zone: the owning group's UUID text, or nil for records outside any group.
    var zoneName: String? { get set }
    /// The archived CKRecord system fields from the last sync, needed to upload a later change.
    var systemFields: Data? { get set }
    var isDirty: Bool { get set }
    var pendingOperationRaw: String? { get set }
    var modifiedAt: Date { get set }
    /// A tombstone. For expenses and payments this is also the user visible soft delete.
    var deletedAt: Date? { get set }

    /// The domain fields to upload. Device local state such as read flags is left out.
    var syncFields: SyncFields { get }
    func applySyncFields(_ fields: SyncFields)

    /// False when a tombstone is a real part of history (expenses and payments) and must be kept for good.
    static var purgesConfirmedTombstones: Bool { get }

    static func find(recordName: String, in context: ModelContext) throws -> Self?
    static func dirtyRecords(in context: ModelContext) throws -> [Self]
    static func tombstones(in context: ModelContext) throws -> [Self]
    /// A record built from remote fields; the caller applies the fields and the stamp afterwards.
    static func blank(recordName: String) -> Self
}

extension SyncTracked {
    static var purgesConfirmedTombstones: Bool { true }

    var pendingOperation: PendingOperation? {
        get { pendingOperationRaw.flatMap(PendingOperation.init(rawValue:)) }
        set { pendingOperationRaw = newValue?.rawValue }
    }

    var isTombstone: Bool { deletedAt != nil }

    var syncPayload: SyncPayload {
        SyncPayload(
            recordType: Self.syncRecordType, recordName: recordName, zoneName: zoneName,
            systemFields: systemFields, modifiedAt: modifiedAt, deletedAt: deletedAt, fields: syncFields
        )
    }

    var syncStamp: SyncStamp {
        SyncStamp(modifiedAt: modifiedAt, deletedAt: deletedAt, tieBreaker: syncFields.canonicalText)
    }
}
