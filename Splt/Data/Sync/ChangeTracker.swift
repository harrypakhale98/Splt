import Foundation
import SwiftData

/// Marks records dirty on local edits and clears them when sync reports success.
///
/// The tracker works on one `ModelContext` and is used from whatever actor owns that
/// context. A context does not keep its container alive, so hold the container as long as you
/// use the tracker. Local edits go through `recordEdit`, `softDelete`, `tombstone` and `restore`.
///
/// The sync engine's side of the contract, in `ChangeTracker+Sync`:
/// 1. `pendingChanges()` lists what to send, and `payload(recordType:recordName:)` reads a record.
/// 2. After the server accepts an upload, `markSynced` stores the new system fields and clears
///    the dirty flag, unless the record was edited again while the upload was in flight.
/// 3. `applyRemote` and `applyRemoteDeletion` apply what the server sent without marking
///    anything dirty. Conflicts follow `MergePolicy`; the outcome says whether local changes
///    were thrown away, so the engine can drop the matching pending upload.
/// 4. `purgeConfirmedTombstones` cleans up deletes the server has seen.
struct ChangeTracker {
    let context: ModelContext
    let now: @Sendable () -> Date

    init(context: ModelContext, now: @escaping @Sendable () -> Date = { Date() }) {
        self.context = context
        self.now = now
    }

    /// Call after creating or changing a record. The modified date never moves backwards.
    func recordEdit(_ record: some SyncTracked) {
        record.modifiedAt = stampedDate(after: record.modifiedAt)
        record.isDirty = true
        record.pendingOperation = .save
    }

    /// Marks an expense or payment as deleted but keeps it, so history survives. It uploads as a save.
    func softDelete(_ record: some SyncTracked) {
        let date = stampedDate(after: record.modifiedAt)
        record.deletedAt = date
        record.modifiedAt = date
        record.isDirty = true
        record.pendingOperation = .save
    }

    /// Deletes a record that has no history worth keeping. It stays as a tombstone until sync
    /// confirms the delete, unless it never reached the server, in which case it is dropped.
    func tombstone(_ record: some SyncTracked) {
        guard record.systemFields != nil else {
            context.delete(record)
            return
        }
        let date = stampedDate(after: record.modifiedAt)
        record.deletedAt = date
        record.modifiedAt = date
        record.isDirty = true
        record.pendingOperation = .delete
    }

    /// Undoes a soft delete. The later modified date lets it beat the older tombstone on other devices.
    func restore(_ record: some SyncTracked) {
        record.deletedAt = nil
        recordEdit(record)
    }

    func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func stampedDate(after previous: Date) -> Date {
        max(now(), previous)
    }
}
