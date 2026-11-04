import Foundation
import SpltCore
import SwiftData
import Synchronization

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
    /// Told about every change that can move a group's balances, so cached ledgers never go stale.
    let balanceCache: BalanceCache?
    /// Groups touched since the last save. They are dropped from the cache again once the data is saved,
    /// so a reader on another context cannot cache the old state in between.
    private let unsaved = UnsavedGroups()

    init(context: ModelContext, balanceCache: BalanceCache? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.context = context
        self.balanceCache = balanceCache
        self.now = now
    }

    /// Call after creating or changing a record. The modified date always moves forwards.
    func recordEdit(_ record: some SyncTracked) {
        noteBalanceChange(record)
        record.modifiedAt = stampedDate(after: record.modifiedAt)
        record.isDirty = true
        record.pendingOperation = .save
    }

    /// Queues a change every device works out for itself. The modified date stays, so it never beats a real edit.
    func recordBookkeeping(_ record: some SyncTracked) {
        record.isDirty = true
        record.pendingOperation = .save
    }

    /// Marks an expense or payment as deleted but keeps it, so history survives. It uploads as a save.
    func softDelete(_ record: some SyncTracked) {
        noteBalanceChange(record)
        let date = stampedDate(after: record.modifiedAt)
        record.deletedAt = date
        record.modifiedAt = date
        record.isDirty = true
        record.pendingOperation = .save
    }

    /// Deletes a record that has no history worth keeping. It stays as a tombstone until sync
    /// confirms the delete, unless it never reached the server, in which case it is dropped.
    func tombstone(_ record: some SyncTracked) {
        noteBalanceChange(record)
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
        noteBalanceChange(record)
        record.deletedAt = nil
        recordEdit(record)
    }

    func save() throws {
        if context.hasChanges {
            try context.save()
        }
        flushUnsavedGroups()
    }

    /// Throws away unsaved changes, as after a failed batch.
    func rollback() {
        context.rollback()
        flushUnsavedGroups()
    }

    /// Always later than `previous`, even when the clock is behind it, so an edit made during an upload
    /// is told apart from what was sent. See `Date.isLaterEdit(than:)` for why the step is two milliseconds.
    private func stampedDate(after previous: Date) -> Date {
        let current = (now().timeIntervalSinceReferenceDate * 1000).rounded(.down)
        let next = (previous.timeIntervalSinceReferenceDate * 1000).rounded() + 2
        return Date(timeIntervalSinceReferenceDate: max(current, next) / 1000)
    }

    /// Drops the cached ledger of the group a record belongs to, when the record can change balances.
    /// Pass the group's id text when it is known better than the record's own zone, for example before a move.
    func noteBalanceChange(_ record: some SyncTracked, zone: String? = nil) {
        noteBalanceChange(type: type(of: record).syncRecordType, zone: zone ?? record.zoneName)
    }

    func noteBalanceChange(type: SyncRecordType, zone: String?) {
        guard let balanceCache, type == .expense || type == .payment || type == .group else { return }
        if let zone, let id = UUID(uuidString: zone) {
            let group = GroupID(rawValue: id)
            balanceCache.invalidate(group)
            unsaved.add(group)
        } else {
            balanceCache.invalidateAll()
            unsaved.addAll()
        }
    }

    private func flushUnsavedGroups() {
        guard let balanceCache else { return }
        let (all, groups) = unsaved.take()
        if all { balanceCache.invalidateAll() }
        for group in groups { balanceCache.invalidate(group) }
    }
}

private final class UnsavedGroups: Sendable {
    private let state = Mutex<(all: Bool, groups: Set<GroupID>)>((false, []))

    func add(_ group: GroupID) {
        state.withLock { _ = $0.groups.insert(group) }
    }

    func addAll() {
        state.withLock { $0.all = true }
    }

    func take() -> (all: Bool, groups: Set<GroupID>) {
        state.withLock { state in
            defer { state = (false, []) }
            return state
        }
    }
}
