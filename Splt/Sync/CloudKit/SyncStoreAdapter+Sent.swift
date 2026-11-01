import CloudKit
import Foundation

/// What to do after one upload failed.
struct SaveFailureOutcome: Equatable {
    var failure: SyncFailure
    /// The change should be queued again, for example after a conflict the local version won.
    var requeue = false
    var recreateZone: CKRecordZone.ID?
    /// A shared zone that is gone, treated like a zone the owner deleted.
    var goneZone: CKRecordZone.ID?
}

extension SyncStoreAdapter {
    /// Records the server accepted and records it deleted.
    func didSend(saved: [CKRecord], deleted: [CKRecord.ID]) throws {
        var copies: [(PersonCopyKey, PersonCopy)] = []
        for record in saved {
            guard let type = SyncRecordType(rawValue: record.recordType) else { continue }
            let sentAt = (record[RecordSchema.modifiedAtKey] as? Date) ?? .distantPast
            let systemFields = RecordMapper.encodeSystemFields(record)
            if type == .person {
                let key = PersonCopyKey(zoneName: record.recordID.zoneID.zoneName, recordName: record.recordID.recordName)
                copies.append((key, PersonCopy(systemFields: systemFields, sentModifiedAt: sentAt)))
            } else {
                try tracker.markSynced(
                    recordType: type, recordName: record.recordID.recordName,
                    sentModifiedAt: sentAt, systemFields: systemFields
                )
            }
        }
        if !copies.isEmpty {
            // an uploaded person is marked with system fields so a later delete is not dropped as "never synced"
            for (key, copy) in copies {
                if let model = try PersonRecord.find(recordName: key.recordName, in: tracker.context), model.systemFields == nil {
                    model.systemFields = copy.systemFields
                }
            }
            try tracker.save()
            updateMetadata { metadata in
                for (key, copy) in copies {
                    metadata.setCopy(copy, zoneName: key.zoneName, recordName: key.recordName)
                    metadata.personQueue.remove(key)
                }
            }
        }
        for id in deleted {
            try didDelete(id)
        }
    }

    private func didDelete(_ id: CKRecord.ID) throws {
        let name = id.recordName
        let isPersonCopy = metadata.copy(zoneName: id.zoneID.zoneName, recordName: name) != nil
        if isPersonCopy {
            updateMetadata { $0.setCopy(nil, zoneName: id.zoneID.zoneName, recordName: name) }
        }
        guard let type = try resolveType(of: id),
              let model = try type.modelType.find(recordName: name, in: tracker.context),
              model.pendingOperation == .delete else { return }
        if type == .person {
            guard metadata.privateZonesHoldingCopy(of: name).isEmpty else { return }
            updateMetadata { metadata in
                for zone in metadata.zonesHoldingCopy(of: name) {
                    metadata.setCopy(nil, zoneName: zone, recordName: name)
                }
            }
        }
        try tracker.markSynced(recordType: type, recordName: name, sentModifiedAt: model.modifiedAt, systemFields: nil)
    }

    /// Decides what a failed upload needs. Conflicts are merged with the data layer's policy.
    func saveFailed(record: CKRecord, error: CKError) throws -> SaveFailureOutcome {
        let failure = SyncFailure(error)
        var outcome = SaveFailureOutcome(failure: failure)
        switch failure {
        case .conflict:
            if let server = error.serverRecord {
                let report = try applyFetched(modifications: [server], deletions: [])
                outcome.requeue = report.requeue.contains(record.recordID)
            } else {
                outcome.requeue = true
            }
        case .itemMissing:
            try forgetSystemFields(of: record.recordID)
            outcome.requeue = true
        case .zoneMissing:
            let zone = record.recordID.zoneID
            if zone.scope == .privateDatabase {
                updateMetadata { $0.zones[zone.zoneName] = nil }
                outcome.recreateZone = zone
                outcome.requeue = true
            } else {
                outcome.goneZone = zone
            }
        default:
            break
        }
        return outcome
    }

    /// A delete that finds nothing to delete has done its job.
    func deleteFailed(id: CKRecord.ID, error: CKError) throws -> SyncFailure {
        let failure = SyncFailure(error)
        if failure == .itemMissing {
            try didSend(saved: [], deleted: [id])
        }
        return failure
    }

    private func forgetSystemFields(of id: CKRecord.ID) throws {
        let zone = id.zoneID.zoneName
        if metadata.copy(zoneName: zone, recordName: id.recordName) != nil {
            updateMetadata { metadata in
                metadata.setCopy(PersonCopy(systemFields: nil, sentModifiedAt: .distantPast), zoneName: zone, recordName: id.recordName)
                metadata.personQueue.insert(PersonCopyKey(zoneName: zone, recordName: id.recordName))
            }
            return
        }
        guard let type = try resolveType(of: id),
              let model = try type.modelType.find(recordName: id.recordName, in: tracker.context) else { return }
        model.systemFields = nil
        try tracker.save()
    }
}
