import Foundation
import SwiftData

/// Reads and rewrites every local record that belongs to one group zone.
extension ChangeTracker {
    func records(inZone zone: String) throws -> [any SyncTracked] {
        let zone: String? = zone
        var all: [any SyncTracked] = []
        all += try context.fetch(FetchDescriptor<GroupRecord>(predicate: #Predicate { $0.zoneName == zone }))
        all += try context.fetch(FetchDescriptor<ExpenseRecord>(predicate: #Predicate { $0.zoneName == zone }))
        all += try context.fetch(FetchDescriptor<PaymentRecord>(predicate: #Predicate { $0.zoneName == zone }))
        all += try context.fetch(FetchDescriptor<CommentRecord>(predicate: #Predicate { $0.zoneName == zone }))
        all += try context.fetch(FetchDescriptor<ActivityRecord>(predicate: #Predicate { $0.zoneName == zone }))
        all += try context.fetch(FetchDescriptor<RecurringExpenseRecord>(predicate: #Predicate { $0.zoneName == zone }))
        return all
    }

    /// Hides a zone's records after the zone is gone from the server. Nothing is uploaded and
    /// nothing is removed from disk, so an expense or payment is still there as history.
    func retireLocally(zone: String) throws {
        let date = now()
        for record in try records(inZone: zone) {
            retire(record, at: date)
        }
        try save()
    }

    /// Prepares a zone to be uploaded from scratch, for when the server lost it but the device still has the data.
    func markAllForUpload(zone: String) throws {
        for record in try records(inZone: zone) where record.deletedAt == nil {
            record.systemFields = nil
            record.isDirty = true
            record.pendingOperation = .save
        }
        try save()
    }

    /// Clears the dirty flag on every record of a zone, for after the zone was deleted on the server on purpose.
    func markZoneSynced(zone: String) throws {
        for record in try records(inZone: zone) {
            record.isDirty = false
            record.pendingOperation = nil
            record.systemFields = nil
        }
        try save()
    }

    func hasUnsentChanges(inZone zone: String) throws -> Bool {
        try records(inZone: zone).contains { $0.isDirty }
    }

    /// Hides a zone's records and marks its group for removal, which plans leaving the zone until the
    /// server confirms it, also across launches.
    func retireForLeaving(zone: String) throws {
        try retireLocally(zone: zone)
        guard let group = try GroupRecord.find(recordName: zone, in: context) else { return }
        group.isDirty = true
        group.pendingOperation = .delete
        try save()
    }

    /// Drops the tombstones of a zone that no longer exists on the server.
    func purgeTombstones(inZone zone: String) throws {
        for record in try records(inZone: zone) where record.deletedAt != nil && !record.isDirty {
            context.delete(record)
        }
        try save()
    }

    private func retire(_ record: some SyncTracked, at date: Date) {
        if record.deletedAt == nil {
            record.deletedAt = max(date, record.modifiedAt)
            record.modifiedAt = max(date, record.modifiedAt)
        }
        record.isDirty = false
        record.pendingOperation = nil
    }
}
