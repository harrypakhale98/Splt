import CloudKit
import Foundation
import SwiftData

/// What applying a batch from the server turned up.
struct ApplyReport {
    /// Changes the local version won, to be uploaded again with fresh system fields.
    var requeue: [CKRecord.ID] = []
    var inserted: [SyncPayload] = []
    var shares: [CKShare] = []
    var touchedZones: Set<String> = []
}

enum ZoneDeletionReason: Equatable, Sendable {
    case deleted
    /// The server dropped the zone, for example the user cleared the app's iCloud data.
    case purged
    case encryptedDataReset
}

extension SyncStoreAdapter {
    @discardableResult
    func applyFetched(modifications: [CKRecord], deletions: [(id: CKRecord.ID, recordType: String)]) throws -> ApplyReport {
        var report = ApplyReport()
        var payloads: [SyncPayload] = []
        var sources: [CKRecord.ID] = []
        var copyUpdates: [(PersonCopyKey, PersonCopy)] = []
        var queueAdds: Set<PersonCopyKey> = []

        for record in modifications {
            if let share = record as? CKShare {
                report.shares.append(share)
                continue
            }
            guard var payload = try? RecordMapper.payload(from: record) else { continue }
            registerZone(record.recordID.zoneID)
            report.touchedZones.insert(record.recordID.zoneID.zoneName)
            if payload.recordType == .person {
                let key = PersonCopyKey(zoneName: record.recordID.zoneID.zoneName, recordName: payload.recordName)
                copyUpdates.append((key, PersonCopy(systemFields: payload.systemFields, sentModifiedAt: payload.modifiedAt)))
                payload.zoneName = nil
                payload.systemFields = nil
                if let local = try PersonRecord.find(recordName: payload.recordName, in: tracker.context),
                   local.modifiedAt.isLaterEdit(than: payload.modifiedAt) {
                    queueAdds.insert(key)
                    report.requeue.append(record.recordID)
                    continue
                }
            }
            payloads.append(payload)
            sources.append(record.recordID)
        }

        let outcomes = try tracker.applyRemote(payloads)
        for (index, outcome) in outcomes.enumerated() {
            switch outcome {
            case .inserted:
                report.inserted.append(payloads[index])
            case .keptLocal:
                report.requeue.append(sources[index])
                if payloads[index].recordType == .person {
                    queueAdds.insert(PersonCopyKey(zoneName: sources[index].zoneID.zoneName, recordName: payloads[index].recordName))
                }
            case .updated, .replacedLocalChanges:
                break
            }
        }

        for deletion in deletions {
            try applyDeletion(id: deletion.id, recordType: deletion.recordType)
        }
        if !copyUpdates.isEmpty || !queueAdds.isEmpty {
            updateMetadata { metadata in
                for (key, copy) in copyUpdates {
                    metadata.setCopy(copy, zoneName: key.zoneName, recordName: key.recordName)
                }
                metadata.personQueue.formUnion(queueAdds)
            }
        }
        return report
    }

    private func applyDeletion(id: CKRecord.ID, recordType: String) throws {
        guard let type = SyncRecordType(rawValue: recordType) else { return }
        guard type == .person else {
            try applyServerDeletion(type: type, recordName: id.recordName)
            return
        }
        let zone = id.zoneID.zoneName
        updateMetadata {
            $0.setCopy(nil, zoneName: zone, recordName: id.recordName)
            $0.personQueue.remove(PersonCopyKey(zoneName: zone, recordName: id.recordName))
        }
        guard metadata.zonesHoldingCopy(of: id.recordName).isEmpty,
              let local = try PersonRecord.find(recordName: id.recordName, in: tracker.context),
              local.kind != .me else { return }
        try applyServerDeletion(type: .person, recordName: id.recordName)
    }

    /// The server does not say when a record was deleted. A clean local copy simply follows the server,
    /// even if this device's clock runs behind; a copy with unsent edits is judged by the time it arrived.
    private func applyServerDeletion(type: SyncRecordType, recordName: String) throws {
        guard let local = try type.modelType.find(recordName: recordName, in: tracker.context) else { return }
        let received = tracker.now()
        let date = local.isDirty ? received : max(received, local.modifiedAt)
        try tracker.applyRemoteDeletion(recordType: type, recordName: recordName, at: date)
    }

    // MARK: Zones

    func registerZone(_ id: CKRecordZone.ID) {
        let info = ZoneInfo(ownerName: id.ownerName, scope: id.scope)
        guard metadata.zones[id.zoneName] != info else { return }
        updateMetadata { $0.zones[id.zoneName] = info }
    }

    func zonesSaved(_ zones: [CKRecordZone]) {
        zones.forEach { registerZone($0.zoneID) }
    }

    /// The server removed a zone. Returns true when records were marked for upload and a send should follow.
    @discardableResult
    func zoneDeleted(_ id: CKRecordZone.ID, reason: ZoneDeletionReason) throws -> Bool {
        let zone = id.zoneName
        defer { updateMetadata { $0.forget(zoneName: zone) } }
        if reason != .deleted, id.scope == .privateDatabase {
            try tracker.markAllForUpload(zone: zone)
            return true
        }
        try tracker.retireLocally(zone: zone)
        return false
    }

    /// A zone this device deleted, or left, is gone from the server. Its records are no longer pending.
    func zoneDeleteConfirmed(_ id: CKRecordZone.ID) throws {
        try tracker.markZoneSynced(zone: id.zoneName)
        updateMetadata { $0.forget(zoneName: id.zoneName) }
        try tracker.purgeConfirmedTombstones(olderThan: tracker.now().addingTimeInterval(1))
    }

    /// Removes tombstones the server has long known about.
    func purgeOldTombstones(olderThan days: Int = 30) throws {
        let cutoff = tracker.now().addingTimeInterval(-Double(days) * 86_400)
        try tracker.purgeConfirmedTombstones(olderThan: cutoff)
    }

    /// Sync bookkeeping belongs to one iCloud account. For a different account, local data stays
    /// on the device but is cut loose: it is not uploaded to someone else's iCloud.
    func resetForNewAccount(userRecordName: String?) throws {
        store.reset()
        replaceMetadata(SyncMetadata(userRecordName: userRecordName))
        let context = tracker.context
        for type in SyncRecordType.allCases {
            for record in try type.modelType.dirtyRecords(in: context) {
                record.isDirty = false
                record.pendingOperation = nil
            }
        }
        for type in SyncRecordType.allCases {
            try clearSystemFields(of: type)
        }
        try tracker.save()
    }

    private func clearSystemFields(of type: SyncRecordType) throws {
        let context = tracker.context
        switch type {
        case .person: try context.fetch(FetchDescriptor<PersonRecord>()).forEach { $0.systemFields = nil }
        case .group: try context.fetch(FetchDescriptor<GroupRecord>()).forEach { $0.systemFields = nil }
        case .expense: try context.fetch(FetchDescriptor<ExpenseRecord>()).forEach { $0.systemFields = nil }
        case .payment: try context.fetch(FetchDescriptor<PaymentRecord>()).forEach { $0.systemFields = nil }
        case .comment: try context.fetch(FetchDescriptor<CommentRecord>()).forEach { $0.systemFields = nil }
        case .activity: try context.fetch(FetchDescriptor<ActivityRecord>()).forEach { $0.systemFields = nil }
        case .recurringExpense: try context.fetch(FetchDescriptor<RecurringExpenseRecord>()).forEach { $0.systemFields = nil }
        }
    }
}
