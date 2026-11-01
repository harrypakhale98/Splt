import Foundation
import SwiftData

/// The hooks the sync engine uses. Nothing here marks a record dirty except what the engine asks for.
extension ChangeTracker {
    /// Local changes waiting to be uploaded, oldest first.
    func pendingChanges() throws -> [PendingChange] {
        var changes: [PendingChange] = []
        for type in SyncRecordType.allCases {
            for record in try type.modelType.dirtyRecords(in: context) {
                guard let operation = record.pendingOperation else { continue }
                changes.append(PendingChange(
                    recordType: type, recordName: record.recordName, zoneName: record.zoneName,
                    operation: operation, modifiedAt: record.modifiedAt
                ))
            }
        }
        return changes.sorted { lhs, rhs in
            lhs.modifiedAt != rhs.modifiedAt ? lhs.modifiedAt < rhs.modifiedAt : lhs.recordName < rhs.recordName
        }
    }

    /// The current state of a record, or nil if it is gone.
    func payload(recordType: SyncRecordType, recordName: String) throws -> SyncPayload? {
        try recordType.modelType.find(recordName: recordName, in: context)?.syncPayload
    }

    /// Call when the server accepted an upload. `sentModifiedAt` is the modified date of the
    /// payload that was sent: if the record changed again meanwhile it stays dirty.
    func markSynced(
        recordType: SyncRecordType, recordName: String, sentModifiedAt: Date, systemFields: Data?
    ) throws {
        guard let record = try recordType.modelType.find(recordName: recordName, in: context) else { return }
        if let systemFields {
            record.systemFields = systemFields
        }
        if record.modifiedAt <= sentModifiedAt {
            record.isDirty = false
            record.pendingOperation = nil
        }
        try save()
    }

    /// Applies versions received from the server and saves once. Nothing is marked dirty.
    @discardableResult
    func applyRemote(_ payloads: [SyncPayload]) throws -> [RemoteApplyOutcome] {
        let outcomes = try payloads.map(applyWithoutSaving)
        try save()
        return outcomes
    }

    @discardableResult
    func applyRemote(_ payload: SyncPayload) throws -> RemoteApplyOutcome {
        try applyRemote([payload])[0]
    }

    /// Applies a record the server deleted outright. The local copy becomes a tombstone that is not dirty.
    @discardableResult
    func applyRemoteDeletion(
        recordType: SyncRecordType, recordName: String, at date: Date? = nil
    ) throws -> RemoteApplyOutcome? {
        guard let local = try recordType.modelType.find(recordName: recordName, in: context) else { return nil }
        let deletedAt = date ?? now()
        let remote = SyncStamp(modifiedAt: deletedAt, deletedAt: deletedAt, tieBreaker: "")
        let outcome: RemoteApplyOutcome
        if MergePolicy.winner(local: local.syncStamp, remote: remote) == .remote {
            let wasDirty = local.isDirty
            local.deletedAt = deletedAt
            local.modifiedAt = deletedAt
            local.isDirty = false
            local.pendingOperation = nil
            outcome = wasDirty ? .replacedLocalChanges : .updated
        } else {
            outcome = .keptLocal
        }
        try save()
        return outcome
    }

    /// Drops tombstones the server already knows about once they are older than `cutoff`.
    /// Expenses and payments are kept because their soft delete is part of history, unless the
    /// group they belonged to is gone.
    @discardableResult
    func purgeConfirmedTombstones(olderThan cutoff: Date) throws -> Int {
        var count = 0
        for type in SyncRecordType.allCases {
            for record in try type.modelType.tombstones(in: context) {
                guard !record.isDirty, let deletedAt = record.deletedAt, deletedAt < cutoff else { continue }
                if !type.modelType.purgesConfirmedTombstones {
                    guard try isInGoneGroup(record) else { continue }
                }
                context.delete(record)
                count += 1
            }
        }
        try save()
        return count
    }

    private func isInGoneGroup(_ record: some SyncTracked) throws -> Bool {
        guard let zone = record.zoneName else { return false }
        guard let group = try GroupRecord.find(recordName: zone, in: context) else { return true }
        return group.deletedAt != nil
    }

    private func applyWithoutSaving(_ payload: SyncPayload) throws -> RemoteApplyOutcome {
        guard let local = try payload.recordType.modelType.find(recordName: payload.recordName, in: context) else {
            let record = payload.recordType.modelType.blank(recordName: payload.recordName)
            adopt(payload, into: record)
            context.insert(record)
            return .inserted
        }
        if let systemFields = payload.systemFields {
            local.systemFields = systemFields
        }
        guard local.isDirty else {
            adopt(payload, into: local)
            return .updated
        }
        guard MergePolicy.winner(local: local.syncStamp, remote: payload.stamp) == .remote else {
            return .keptLocal
        }
        adopt(payload, into: local)
        return .replacedLocalChanges
    }

    private func adopt(_ payload: SyncPayload, into record: some SyncTracked) {
        record.applySyncFields(payload.fields)
        record.zoneName = payload.zoneName
        record.systemFields = payload.systemFields ?? record.systemFields
        record.modifiedAt = payload.modifiedAt
        record.deletedAt = payload.deletedAt
        record.isDirty = false
        record.pendingOperation = nil
    }
}
